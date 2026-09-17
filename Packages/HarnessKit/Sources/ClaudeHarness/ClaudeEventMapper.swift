import Foundation
import HarnessCore

/// Traduz as linhas do stdout deste CLI para os dois fluxos da spec §4.4.
///
/// **Sem estado, de propósito.** `content_block_delta` já traz o índice do
/// bloco e o tipo do delta; nada precisa ser lembrado entre linhas. Um
/// mapeador com estado precisaria de dono, de ciclo de vida e de um teste de
/// reentrância — e a consolidação, que é o único lugar onde estado pareceria
/// necessário, o próprio CLI já faz por nós: ele reemite o turno inteiro na
/// linha `assistant`.
///
/// **Uma fonte por destino.** É o invariante central: `stream_event` só
/// alimenta `events`, `assistant`/`user`/`result` só alimentam `entries`.
/// Medido no corpus: 298 `stream_event` contra 17 `assistant` — as duas fontes
/// carregam o MESMO texto, e alimentar as duas ao transcript multiplicaria
/// cada turno por centenas.
public struct ClaudeEventMapper: Sendable {
    /// Prefixo de todo discriminador que este mapeador cunha.
    ///
    /// Existe para tornar impossível a colisão com um caso conhecido de
    /// `TranscriptEntry.Kind`: sem ele, uma linha `{"type":"turnResult"}` de
    /// uma versão futura viraria `{"turnResult": <linha crua>}` no disco, que
    /// um leitor reconheceria como o caso conhecido e tentaria decodificar
    /// como `TurnResult` — estourando a entrada inteira. Nenhum caso de `Kind`
    /// se chama `claude:*`.
    static let discriminatorPrefix = "claude:"

    /// `internal`, não `private`: a extension durável da Task 4 e o arquivo
    /// `ClaudeEventMapper+Permission.swift` da Task 5 precisam dele, e um
    /// `private` obrigaria tudo a caber num arquivo só. Segue invisível fora
    /// do módulo.
    let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// Mapeia uma linha já decodificada.
    public func map(_ line: JSONValue) -> MappedOutput {
        guard let type = line["type"]?.stringValue else {
            return MappedOutput(entries: [unrecognized("line", line)])
        }
        switch type {
        case "stream_event":
            return ephemeral(line)
        case "assistant":
            return assistant(line)
        case "user":
            return user(line)
        case "result":
            return result(line)
        case "system":
            return system(line)
        case "rate_limit_event":
            return rateLimit(line)
        case "control_request", "control_response":
            // O `ControlChannel` é o dono destes quadros (Etapa 3). Mapeá-los
            // aqui também poria o mesmo pedido de permissão duas vezes no
            // transcript.
            return .empty
        default:
            return MappedOutput(entries: [unrecognized(type, line)])
        }
    }

    /// Mapeia uma linha crua do transporte.
    ///
    /// Uma linha que não é JSON não é um erro a propagar: a spec §5.4 manda
    /// preservar. Os bytes viram `.string` — decodificados como UTF-8 com
    /// substituição, então uma sequência inválida vira U+FFFD em vez de
    /// derrubar a linha.
    public func map(line data: Data) -> MappedOutput {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            let text = JSONValue.string(String(decoding: data, as: UTF8.self))
            return MappedOutput(entries: [unrecognized("nonJSON", text)])
        }
        return map(value)
    }

    // MARK: - Efêmero

    private func ephemeral(_ line: JSONValue) -> MappedOutput {
        guard let event = line["event"], let kind = event["type"]?.stringValue else {
            return .empty
        }
        switch kind {
        case "message_start":
            return MappedOutput(events: [.turnStarted])
        case "content_block_delta":
            return MappedOutput(events: delta(event).map { [$0] } ?? [])
        default:
            // content_block_start, content_block_stop, message_delta,
            // message_stop: moldura do stream. O começo e o fim de um bloco a
            // UI infere do índice dos deltas, e o fim da mensagem chega
            // consolidado na linha `assistant`.
            return .empty
        }
    }

    private func delta(_ event: JSONValue) -> SessionEvent? {
        guard let index = event["index"]?.intValue,
              let delta = event["delta"],
              let kind = delta["type"]?.stringValue
        else { return nil }

        switch kind {
        case "text_delta":
            guard let text = delta["text"]?.stringValue else { return nil }
            return .textDelta(blockIndex: index, text: text)
        case "thinking_delta":
            guard let text = delta["thinking"]?.stringValue else { return nil }
            return .thinkingDelta(blockIndex: index, text: text)
        case "input_json_delta":
            guard let partial = delta["partial_json"]?.stringValue else { return nil }
            return .toolInputDelta(blockIndex: index, partialJSON: partial)
        default:
            // signature_delta e o que a API inventar depois: nada a mostrar
            // delta a delta. O conteúdo chega inteiro no bloco consolidado.
            return nil
        }
    }

    // MARK: - Degradação

    /// Preserva o que não sabemos mapear (spec §5.4).
    ///
    /// `at` só é passado quando a linha trouxe `timestamp` próprio; senão vale
    /// o relógio injetado.
    func unrecognized(_ discriminator: String, _ payload: JSONValue,
                      at moment: Date? = nil) -> TranscriptEntry {
        TranscriptEntry(
            timestamp: moment ?? now(),
            kind: .unrecognized(discriminator: Self.discriminatorPrefix + discriminator,
                                payload: payload),
            raw: payload
        )
    }
}

// MARK: - Durável

private extension ClaudeEventMapper {
    /// Uma entrada por bloco de conteúdo.
    ///
    /// A linha `assistant` é a forma CONSOLIDADA do mesmo turno que os
    /// `stream_event` entregaram delta a delta. É ela que vai para o
    /// transcript, e são eles que vão para a UI — as duas fontes carregam o
    /// mesmo texto (D1).
    func assistant(_ line: JSONValue) -> MappedOutput {
        let moment = timestamp(of: line)
        guard let blocks = line["message"]?["content"]?.arrayValue else {
            return MappedOutput(entries: [unrecognized("assistant", line, at: moment)])
        }
        return MappedOutput(entries: blocks.map { assistantBlock($0, at: moment) })
    }

    func assistantBlock(_ block: JSONValue, at moment: Date) -> TranscriptEntry {
        switch block["type"]?.stringValue {
        case "text":
            guard let text = block["text"]?.stringValue else { break }
            return TranscriptEntry(timestamp: moment, kind: .assistantText(text), raw: block)
        case "thinking":
            // A assinatura criptográfica do bloco fica no `raw` — ver D7.
            guard let text = block["thinking"]?.stringValue else { break }
            return TranscriptEntry(timestamp: moment, kind: .assistantThinking(text), raw: block)
        case "tool_use":
            guard let id = block["id"]?.stringValue,
                  let name = block["name"]?.stringValue else { break }
            let call = ToolCall(
                id: id,
                rawName: name,
                canonical: ClaudeToolVocabulary.canonical(for: name),
                input: block["input"] ?? .null
            )
            return TranscriptEntry(timestamp: moment, kind: .toolCall(call), raw: block)
        default:
            break
        }
        return unrecognizedBlock(block, at: moment)
    }

    /// Uma entrada por bloco `tool_result` — ou uma só, quando o conteúdo é a
    /// mensagem em texto.
    func user(_ line: JSONValue) -> MappedOutput {
        let moment = timestamp(of: line)
        guard let content = line["message"]?["content"] else {
            return MappedOutput(entries: [unrecognized("user", line, at: moment)])
        }
        // A forma em string é a que NÓS escrevemos no stdin; o CLI observado
        // não a ecoa de volta, então o corpus não a exercita. Mapeá-la mesmo
        // assim não inventa nada: `role: "user"` com conteúdo em texto é
        // exatamente o que `.userMessage` significa.
        if let text = content.stringValue {
            return MappedOutput(entries: [
                TranscriptEntry(timestamp: moment,
                                kind: .userMessage(text: text, attachments: []),
                                raw: line)
            ])
        }
        guard let blocks = content.arrayValue else {
            return MappedOutput(entries: [unrecognized("user", line, at: moment)])
        }
        return MappedOutput(entries: blocks.map { userBlock($0, at: moment) })
    }

    func userBlock(_ block: JSONValue, at moment: Date) -> TranscriptEntry {
        guard block["type"]?.stringValue == "tool_result",
              let callID = block["tool_use_id"]?.stringValue
        else { return unrecognizedBlock(block, at: moment) }

        let result = ToolResult(
            callID: callID,
            // Ausente significa "deu certo". O CLI só escreve a chave quando
            // a ferramenta falhou.
            isError: block["is_error"]?.boolValue ?? false,
            content: block["content"] ?? .null
        )
        return TranscriptEntry(timestamp: moment, kind: .toolResult(result), raw: block)
    }

    /// Como o turno fechou, com a contabilidade daquele turno.
    ///
    /// O campo `result` da linha NÃO vira `.assistantText`: ele repete a prosa
    /// do último bloco `text` da linha `assistant` anterior, e mapeá-lo
    /// duplicaria o último parágrafo de todo turno (D3). A linha inteira fica
    /// no `raw`, então nada se perde.
    func result(_ line: JSONValue) -> MappedOutput {
        let usage = line["usage"]
        let totals = UsageTotals(
            inputTokens: usage?["input_tokens"]?.intValue ?? 0,
            outputTokens: usage?["output_tokens"]?.intValue ?? 0,
            cacheReadTokens: usage?["cache_read_input_tokens"]?.intValue ?? 0,
            cacheCreationTokens: usage?["cache_creation_input_tokens"]?.intValue ?? 0,
            costUSD: line["total_cost_usd"]?.doubleValue ?? 0
        )
        let turn = TurnResult(
            usage: totals,
            stopReason: line["stop_reason"]?.stringValue,
            isError: line["is_error"]?.boolValue ?? false
        )
        return MappedOutput(entries: [
            TranscriptEntry(timestamp: timestamp(of: line), kind: .turnResult(turn), raw: line)
        ])
    }

    func unrecognizedBlock(_ block: JSONValue, at moment: Date) -> TranscriptEntry {
        unrecognized("content/" + (block["type"]?.stringValue ?? "?"), block, at: moment)
    }

    /// O `timestamp` da linha, quando ela traz um.
    ///
    /// Só `assistant` e `user` trazem; `system`, `result`, `stream_event` e
    /// `rate_limit_event` não trazem nenhum, e para essas vale o relógio
    /// injetado. Um carimbo que não analisa também cai no relógio, em vez de
    /// derrubar a entrada (spec §5.4).
    func timestamp(of line: JSONValue) -> Date {
        guard let text = line["timestamp"]?.stringValue else { return now() }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) {
            return date
        }
        return now()
    }

    /// As linhas `system`, separadas por subtipo em efêmeras e duráveis.
    ///
    /// Dos 30 `system` do corpus, 21 são `status` (rótulo de spinner) e
    /// `thinking_tokens` (estimativa corrente de tokens): progresso de
    /// exibição, não semântica da conversa. Vão para a UI e morrem ali — o
    /// transcript é registro semântico (spec §4.2), e um replay para outro
    /// harness não ganha nada com eles.
    func system(_ line: JSONValue) -> MappedOutput {
        guard let subtype = line["subtype"]?.stringValue else {
            return MappedOutput(entries: [unrecognized("system", line)])
        }
        switch subtype {
        case "init":
            let model = line["model"]?.stringValue ?? ""
            return MappedOutput(
                events: [.sessionInitialized(
                    model: model,
                    harnessSessionID: line["session_id"]?.stringValue ?? ""
                )],
                entries: [TranscriptEntry(
                    timestamp: now(),
                    kind: .systemNotice(subtype: "init", text: model),
                    raw: line
                )]
            )

        case "status":
            return MappedOutput(events: [
                .notice(subtype: subtype, text: line["status"]?.stringValue ?? "")
            ])

        case "thinking_tokens":
            return MappedOutput(events: [
                .notice(subtype: subtype,
                        text: line["estimated_tokens"]?.intValue.map { String($0) } ?? "")
            ])

        case "permission_denied":
            // As regras do harness negaram sozinhas — o `can_use_tool` só
            // chega ao cliente quando elas avaliam para "ask". Isso é uma
            // decisão de permissão de verdade, feita pelo harness. Registrar
            // como aviso perderia a semântica de que a ferramenta foi barrada.
            //
            // `interrupt: false` porque o turno observado segue: nas 6
            // negações do corpus veio um `tool_result` com `is_error: true`
            // logo depois e a conversa continuou.
            guard let toolUseID = line["tool_use_id"]?.stringValue else {
                return MappedOutput(entries: [unrecognized("system/" + subtype, line)])
            }
            return MappedOutput(entries: [TranscriptEntry(
                timestamp: now(),
                kind: .permissionDecision(
                    requestID: toolUseID,
                    .deny(message: line["message"]?.stringValue ?? "", interrupt: false)
                ),
                raw: line
            )])

        default:
            return MappedOutput(entries: [unrecognized("system/" + subtype, line)])
        }
    }

    /// Durável: é o que explica, meses depois, um turno que parou no meio.
    func rateLimit(_ line: JSONValue) -> MappedOutput {
        MappedOutput(entries: [TranscriptEntry(
            timestamp: now(),
            kind: .systemNotice(
                subtype: "rate_limit",
                text: line["rate_limit_info"]?["status"]?.stringValue ?? ""
            ),
            raw: line
        )])
    }
}

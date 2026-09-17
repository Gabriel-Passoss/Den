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

import Foundation
import Observation
import HarnessCore
import ClaudeHarness

/// O estado de uma conversa, do jeito que a tela precisa dele.
///
/// Fica entre o `ClaudeSession` (que fala o protocolo) e a view (que desenha).
/// A tradução que acontece aqui é só de apresentação: nada de semântica nova.
@MainActor
@Observable
final class CockpitModel {
    /// Uma linha do transcript, já pronta para desenhar.
    struct Line: Identifiable {
        enum Role { case user, assistant, thinking, tool, toolResult, notice, turn, unknown }
        let id: UUID
        let role: Role
        let text: String
    }

    var lines: [Line] = []
    /// O que está chegando agora, delta a delta. Vira uma `Line` quando o
    /// turno consolida — é a distinção efêmero/durável da spec §4.4 aparecendo
    /// na tela.
    var streaming: String = ""
    var pending: PermissionRequest?
    var prompt: String = ""
    var status: String = "parada"
    var isBusy = false
    var workingDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())

    private var session: ClaudeSession?
    private var consumer: Task<Void, Never>?

    var isRunning: Bool { session != nil }

    // MARK: - Ciclo de vida

    func start() async {
        guard session == nil else { return }
        status = "procurando o claude…"
        do {
            let installation = try await ClaudeDiscovery().discover()
            status = "claude \(installation.version)"

            let launch = ClaudeLaunch.make(
                installation: installation,
                workingDirectory: workingDirectory,
                session: .fresh(sessionID: UUID())
            )
            let session = ClaudeSession(channel: ControlChannel(transport: ProcessTransport()))
            let updates = try await session.start(launch)
            self.session = session

            // O `Task` herda o isolamento do `@MainActor` deste tipo, então
            // `apply` corre sem salto de ator — é por isso que não há `await`.
            consumer = Task { [weak self] in
                for await update in updates {
                    self?.apply(update)
                }
            }
        } catch {
            status = "falhou: \(error)"
        }
    }

    func send() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let session else { return }
        prompt = ""
        append(.user, text)
        isBusy = true
        do {
            try await session.send(text)
        } catch {
            append(.notice, "não consegui mandar o turno: \(error)")
            isBusy = false
        }
    }

    func resolve(allow: Bool) async {
        guard let request = pending, let session else { return }
        pending = nil
        let decision: PermissionDecision = allow
            ? .allow(updatedInput: nil)
            : .deny(message: "o usuário negou", interrupt: false)
        do {
            try await session.resolve(request.id, decision)
            append(.notice, allow ? "permitiu \(request.toolName)" : "negou \(request.toolName)")
        } catch {
            append(.notice, "não consegui responder a permissão: \(error)")
        }
    }

    func stop() async {
        consumer?.cancel()
        consumer = nil
        await session?.stop()
        session = nil
        isBusy = false
        status = "parada"
    }

    // MARK: - Tradução para a tela

    private func apply(_ update: ClaudeSession.Update) {
        switch update {
        case .event(let event):
            switch event {
            case .sessionInitialized(let model, _):
                status = model
            case .turnStarted:
                streaming = ""
            case .textDelta(_, let text):
                streaming += text
            case .thinkingDelta, .toolInputDelta:
                // Ainda não desenhados: o raciocínio e o input parcial chegam
                // consolidados logo em seguida.
                break
            case .notice(let subtype, let text):
                if subtype == "status" { status = text }
            }

        case .entry(let entry):
            switch entry.kind {
            case .assistantText(let text):
                streaming = ""
                append(.assistant, text)
            case .assistantThinking(let text):
                append(.thinking, text)
            case .toolCall(let call):
                let verb = call.canonical.map { "\($0.rawValue) · " } ?? ""
                append(.tool, "\(verb)\(call.rawName)  \(oneLine(call.input))")
            case .toolResult(let result):
                append(.toolResult, (result.isError ? "erro: " : "") + oneLine(result.content))
            case .permissionDecision(_, let decision):
                if case .deny(let message, _) = decision { append(.notice, message) }
            case .systemNotice(let subtype, let text):
                if subtype != "init" { append(.notice, "\(subtype): \(text)") }
            case .turnResult(let result):
                isBusy = false
                streaming = ""
                let cost = String(format: "US$ %.4f", result.usage.costUSD)
                append(.turn, "turno fechado · \(result.usage.outputTokens) tokens · \(cost)")
            case .userMessage(let text, _):
                append(.user, text)
            case .permissionRequest, .unrecognized:
                append(.unknown, oneLine(entry.raw))
            }

        case .permission(let request):
            pending = request

        case .unrecognizedControl(let unrecognized):
            append(.unknown, "quadro de controle não reconhecido"
                   + (unrecognized.wasAnswered ? " (recusado automaticamente)" : " — SESSÃO PODE ESTAR TRAVADA"))

        case .ended(let error):
            isBusy = false
            status = error.map { "encerrada: \($0)" } ?? "encerrada"
            session = nil
        }
    }

    private func append(_ role: Line.Role, _ text: String) {
        lines.append(Line(id: UUID(), role: role, text: text))
    }

    /// Um resumo de uma linha só para um payload arbitrário.
    private func oneLine(_ value: JSONValue) -> String {
        let text: String
        switch value {
        case .string(let s): text = s
        case .object(let members):
            text = members.map { "\($0.key)=\(oneLine($0.value))" }.sorted().joined(separator: " ")
        case .array(let items): text = items.map(oneLine).joined(separator: ", ")
        case .int(let i): text = String(i)
        case .double(let d): text = String(d)
        case .bool(let b): text = String(b)
        case .null: text = "—"
        }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 240 ? String(flat.prefix(240)) + "…" : flat
    }
}

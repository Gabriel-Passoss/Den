import Foundation
import Observation
import HarnessCore
import ClaudeHarness

/// Uma conversa, do jeito que a tela precisa dela.
///
/// Fica entre o `ClaudeSession` (que fala o protocolo) e a view (que desenha),
/// e é quem grava no store: é o único ponto que enxerga as entradas duráveis
/// no instante em que nascem.
@MainActor
@Observable
final class CockpitModel {
    struct Line: Identifiable {
        enum Role { case user, assistant, thinking, tool, toolResult, notice, unknown }
        let id: UUID
        let role: Role
        let text: String
        /// Só para `.tool`: o verbo canônico, quando existe.
        var verb: CanonicalTool?
    }

    let sessionID: UUID
    let segmentID: UUID
    var title: String
    var workingDirectory: URL

    var lines: [Line] = []
    /// O que está chegando agora, delta a delta. Vira linha quando o turno
    /// consolida — a distinção efêmero/durável da spec §4.4 na tela.
    var streaming: String = ""
    var pending: PermissionRequest?
    var prompt: String = ""
    var status: String = ""
    var model: String = ""
    var isBusy = false

    private let store: FileTranscriptStore
    private var session: ClaudeSession?
    private var consumer: Task<Void, Never>?
    private var hasTitle = false
    /// O `--session-id` que demos ao harness. Igual ao nosso id na primeira
    /// vez; é por ele que a retomada acontece.
    private let harnessSessionID: UUID
    /// Uma conversa reaberta do disco retoma, não recomeça.
    private let isRestored: Bool

    var isLive: Bool { session != nil }

    // MARK: - Nascimento

    init(store: FileTranscriptStore, workingDirectory: URL) {
        self.store = store
        self.sessionID = UUID()
        self.segmentID = UUID()
        self.title = "Nova conversa"
        self.workingDirectory = workingDirectory
        self.harnessSessionID = self.sessionID
        self.isRestored = false
    }

    /// Reabre uma conversa que já está em disco.
    init(store: FileTranscriptStore, restoring session: Session) {
        self.store = store
        self.sessionID = session.id
        self.segmentID = session.segments.last?.id ?? UUID()
        self.title = session.title
        self.workingDirectory = session.workingDirectory
        self.model = session.segments.last?.model ?? ""
        self.hasTitle = true
        self.harnessSessionID = session.segments.last?.harnessSessionID ?? session.id
        self.isRestored = true
        self.status = "fria"
        for entry in session.allEntries { render(entry, persist: false) }
    }

    private var domainSession: Session {
        Session(id: sessionID, title: title, workingDirectory: workingDirectory,
                segments: [Segment(id: segmentID, harness: .claudeCode,
                                   harnessSessionID: harnessSessionID, model: model)])
    }

    func persistMetadata() async {
        try? await store.saveMetadata(domainSession)
    }

    // MARK: - Ciclo de vida

    func start() async {
        guard session == nil else { return }
        status = "procurando o claude…"
        do {
            let installation = try await ClaudeDiscovery().discover()
            // O ciclo `idle → hot` da spec §5.1: reabrir uma conversa fria
            // RETOMA a sessão do harness, não começa outra. Sem isto, o CLI
            // receberia um `--session-id` que ele já conhece e a conversa
            // reabriria vazia.
            let start: SessionStart = isRestored
                ? .resume(harnessSessionID: harnessSessionID)
                : .fresh(sessionID: harnessSessionID)
            let launch = ClaudeLaunch.make(
                installation: installation,
                workingDirectory: workingDirectory,
                session: start
            )
            let live = ClaudeSession(channel: ControlChannel(transport: ProcessTransport()))
            let updates = try await live.start(launch)
            session = live
            status = "pronta"

            // O `Task` herda o isolamento do `@MainActor` deste tipo, então
            // `apply` corre sem salto de ator — é por isso que não há `await`.
            consumer = Task { [weak self] in
                for await update in updates { self?.apply(update) }
            }
        } catch {
            status = "falhou: \(error)"
        }
    }

    func send() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if session == nil { await start() }
        guard let session else { return }
        prompt = ""

        // O CLI não ecoa de volta o turno que escrevemos, então quem o registra
        // é quem o envia — senão o transcript teria respostas sem perguntas.
        let entry = TranscriptEntry(
            timestamp: Date(),
            kind: .userMessage(text: text, attachments: []),
            raw: .object(["type": .string("user"), "text": .string(text)])
        )
        render(entry, persist: true)
        await nameFromFirstTurn(text)

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
        status = "fria"
    }

    /// O título sai do primeiro turno, que é o que o usuário reconhece na lista.
    private func nameFromFirstTurn(_ text: String) async {
        guard !hasTitle else { return }
        hasTitle = true
        title = text.count > 60 ? String(text.prefix(60)) + "…" : text
        await persistMetadata()
    }

    // MARK: - Tradução para a tela

    private func apply(_ update: ClaudeSession.Update) {
        switch update {
        case .event(let event):
            switch event {
            case .sessionInitialized(let model, _):
                self.model = model
                Task { await persistMetadata() }
            case .turnStarted:
                streaming = ""
            case .textDelta(_, let text):
                streaming += text
            case .notice(let subtype, let text):
                if subtype == "status" { status = text }
            case .thinkingDelta, .toolInputDelta:
                break
            }

        case .entry(let entry):
            render(entry, persist: true)

        case .permission(let request):
            pending = request

        case .unrecognizedControl(let unrecognized):
            append(.unknown, "quadro de controle não reconhecido"
                   + (unrecognized.wasAnswered ? "" : " — a sessão pode estar travada"))

        case .ended(let error):
            isBusy = false
            status = error.map { "encerrada: \($0)" } ?? "fria"
            session = nil
        }
    }

    private func render(_ entry: TranscriptEntry, persist: Bool) {
        if persist {
            Task { [store, sessionID, segmentID] in
                try? await store.append(entry, to: segmentID, in: sessionID)
            }
        }

        switch entry.kind {
        case .userMessage(let text, _):
            append(.user, text)
        case .assistantText(let text):
            streaming = ""
            append(.assistant, text)
        case .assistantThinking(let text):
            append(.thinking, text)
        case .toolCall(let call):
            append(.tool, summary(of: call), verb: call.canonical)
        case .toolResult(let result):
            append(.toolResult, (result.isError ? "falhou: " : "") + oneLine(result.content))
        case .permissionDecision(_, let decision):
            if case .deny(let message, _) = decision { append(.notice, message) }
        case .systemNotice(let subtype, let text):
            if subtype != "init" && subtype != "rate_limit" { append(.notice, text) }
        case .turnResult:
            // Nada na tela: tokens e custo não são a conversa, e o custo de uma
            // conta de assinatura não é dinheiro que o usuário paga por turno.
            isBusy = false
            streaming = ""
        case .permissionRequest, .unrecognized:
            append(.unknown, oneLine(entry.raw))
        }
    }

    private func append(_ role: Line.Role, _ text: String, verb: CanonicalTool? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append(Line(id: UUID(), role: role, text: trimmed, verb: verb))
    }

    /// Uma chamada de ferramenta, resumida do jeito que se lê.
    private func summary(of call: ToolCall) -> String {
        let input = call.input
        if let command = input["command"]?.stringValue { return command }
        if let path = input["file_path"]?.stringValue {
            return (path as NSString).lastPathComponent
        }
        if let pattern = input["pattern"]?.stringValue { return pattern }
        if let url = input["url"]?.stringValue { return url }
        return oneLine(input)
    }

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
        return flat.count > 200 ? String(flat.prefix(200)) + "…" : flat
    }

    // MARK: - Agrupamento para desenhar

    /// Corridas consecutivas de eventos não reconhecidos viram UM bloco
    /// recolhido. Spec §5.4: preservado e exibido, sem afogar a conversa.
    var blocks: [Block] {
        var result: [Block] = []
        var run: [Line] = []
        func flush() {
            guard !run.isEmpty else { return }
            result.append(.collapsed(id: run[0].id, lines: run))
            run = []
        }
        for line in lines {
            if line.role == .unknown { run.append(line) }
            else { flush(); result.append(.line(line)) }
        }
        flush()
        return result
    }

    enum Block: Identifiable {
        case line(Line)
        case collapsed(id: UUID, lines: [Line])
        var id: UUID {
            switch self {
            case .line(let line): return line.id
            case .collapsed(let id, _): return id
            }
        }
    }
}

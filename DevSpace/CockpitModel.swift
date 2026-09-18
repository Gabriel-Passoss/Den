import Foundation
import Observation
import HarnessCore
import ClaudeHarness

@MainActor
@Observable
final class CockpitModel {
    struct Line: Identifiable {
        enum Role { case user, assistant, thinking, tool, toolResult, notice, unknown }
        let id: UUID
        let role: Role
        let text: String

        let timestamp: Date

        var verb: CanonicalTool?
    }

    let sessionID: UUID
    let segmentID: UUID
    var title: String
    var workingDirectory: URL

    var lines: [Line] = []

    var streaming: String = ""
    var pending: PermissionRequest?
    var prompt: String = ""
    var status: String = ""
    var model: String = ""
    var isBusy = false

    var branch: String?

    var preferredModel: String?

    var preferredEffort: EffortLevel?

    var detectedEffort: EffortLevel?

    static let modelChoices: [(name: String, id: String?)] = [
        ("Fable", "fable"),
        ("Opus", "opus"),
        ("Sonnet", "sonnet"),
        ("Haiku", "haiku"),
    ]

    static let effortChoices: [(name: String, id: EffortLevel?)] = [
        ("Baixo", .low),
        ("Médio", .medium),
        ("Alto", .high),
        ("Muito alto", .xhigh),
        ("Máximo", .max),
    ]

    private let store: FileTranscriptStore
    private var session: ClaudeSession?
    private var consumer: Task<Void, Never>?
    private var hasTitle = false

    private var harnessSessionID: UUID

    private let isRestored: Bool

    private var hasLaunched = false

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
        self.detectedEffort = ClaudeSettings.effortLevel(forWorkingDirectory: workingDirectory)
    }

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
        self.detectedEffort = ClaudeSettings.effortLevel(forWorkingDirectory: session.workingDirectory)
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

    func loadBranch() async {
        let output = try? await SystemCommandRunner().run(
            "/usr/bin/git", ["-C", workingDirectory.path, "rev-parse", "--abbrev-ref", "HEAD"])
        let name = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        branch = (name?.isEmpty == false) ? name : nil
    }

    var locationSummary: String {
        let folder = workingDirectory.lastPathComponent
        guard let branch else { return folder }
        return "\(folder) · branch \(branch)"
    }

    // MARK: - Ciclo de vida

    func start() async {
        guard session == nil else { return }
        status = "procurando o claude…"
        do {
            let installation = try await ClaudeDiscovery().discover()

            let start: SessionStart
            if lines.contains(where: { $0.role == .assistant }) {
                start = .resume(harnessSessionID: harnessSessionID)
            } else {
                if isRestored || hasLaunched {
                    harnessSessionID = UUID()
                    await persistMetadata()
                }
                start = .fresh(sessionID: harnessSessionID)
            }
            hasLaunched = true
            let launch = ClaudeLaunch.make(
                installation: installation,
                workingDirectory: workingDirectory,
                session: start,
                model: preferredModel,
                effort: preferredEffort
            )
            let live = ClaudeSession(channel: ControlChannel(transport: ProcessTransport()))
            let updates = try await live.start(launch)
            session = live
            status = "pronta"

            consumer = Task { [weak self] in
                for await update in updates { self?.apply(update) }
            }
        } catch {
            status = "falhou: \(error)"

            append(.notice, "não consegui subir o harness: \(error)")
        }
    }

    func send() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if session == nil { await start() }
        guard let session else { return }
        prompt = ""

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

    nonisolated static func displayName(for modelID: String) -> String {
        var words = modelID.split(separator: "-").map(String.init)
        if words.first?.lowercased() == "claude" { words.removeFirst() }
        if let last = words.last, last.count == 8, last.allSatisfy(\.isNumber) {
            words.removeLast()
        }
        var parts: [String] = []
        for word in words {
            if word.allSatisfy(\.isNumber), let previous = parts.last,
               previous.last?.isNumber == true {
                parts[parts.count - 1] = previous + "." + word
            } else {
                parts.append(word.allSatisfy(\.isNumber) ? word : word.capitalized)
            }
        }
        return parts.joined(separator: " ")
    }

    func choose(model id: String?) async {
        guard preferredModel != id else { return }
        preferredModel = id
        await relaunchIfIdle()
    }

    func choose(effort level: EffortLevel?) async {
        guard preferredEffort != level else { return }
        preferredEffort = level
        await relaunchIfIdle()
    }

    private func relaunchIfIdle() async {
        guard !isBusy else { return }
        if session != nil { await stop() }
        await start()
    }

    func stop() async {
        consumer?.cancel()
        consumer = nil
        await session?.stop()
        session = nil
        isBusy = false
        status = "fria"
    }

    func adoptTitle(_ newTitle: String) {
        title = newTitle
        hasTitle = true
    }

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

            let midTurn = isBusy
            isBusy = false
            status = error.map { "encerrada: \($0)" } ?? "fria"
            session = nil
            if let error {
                append(.notice, "a sessão caiu: \(error)")
            } else if midTurn {
                append(.notice, "o harness encerrou sem responder ao turno "
                       + "— a inicialização pode ter travado (um servidor MCP "
                       + "lento ou sem autorização atrasa o init)")
            }
        }
    }

    private func render(_ entry: TranscriptEntry, persist: Bool) {
        if persist {
            Task { [store, sessionID, segmentID] in
                try? await store.append(entry, to: segmentID, in: sessionID)
            }
        }

        let moment = entry.timestamp
        switch entry.kind {
        case .userMessage(let text, _):
            append(.user, text, at: moment)
        case .assistantText(let text):
            streaming = ""
            append(.assistant, text, at: moment)
        case .assistantThinking(let text):
            append(.thinking, text, at: moment)
        case .toolCall(let call):
            append(.tool, summary(of: call), at: moment, verb: call.canonical)
        case .toolResult(let result):
            append(.toolResult, (result.isError ? "falhou: " : "") + oneLine(result.content),
                   at: moment)
        case .permissionDecision(_, let decision):
            if case .deny(let message, _) = decision { append(.notice, message, at: moment) }
        case .systemNotice(let subtype, let text):
            if subtype != "init" && subtype != "rate_limit" { append(.notice, text, at: moment) }
        case .turnResult(let result):

            isBusy = false
            streaming = ""
            if result.isError {
                append(.notice, "o turno falhou no harness"
                       + (result.stopReason.map { " (\($0))" } ?? ""), at: moment)
            }
        case .permissionRequest, .unrecognized:

            if entry.raw["type"]?.stringValue == "system",
               let subtype = entry.raw["subtype"]?.stringValue,
               subtype == "hook_started" || subtype == "hook_response" { return }
            append(.unknown, oneLine(entry.raw), at: moment)
        }
    }

    private func append(_ role: Line.Role, _ text: String,
                        at moment: Date = Date(), verb: CanonicalTool? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append(Line(id: UUID(), role: role, text: trimmed,
                          timestamp: moment, verb: verb))
    }

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

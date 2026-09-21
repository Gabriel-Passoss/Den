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
        var images: [Data] = []
        var files: [String] = []

        let timestamp: Date

        var verb: CanonicalTool?
    }

    let sessionID: UUID
    let segmentID: UUID
    var title: String
    var workingDirectory: URL

    var lines: [Line] = []

    var streaming: String = ""

    /// Deltas chegam dezenas de vezes por segundo; publicar cada um invalida a
    /// transcrição inteira. O buffer agrupa os tokens em ~12 atualizações/s.
    private var streamBuffer = ""
    private var streamFlush: Task<Void, Never>?

    private func appendStreaming(_ text: String) {
        streamBuffer += text
        guard streamFlush == nil else { return }
        streamFlush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self else { return }
            self.streamFlush = nil
            guard !self.streamBuffer.isEmpty else { return }
            self.streaming += self.streamBuffer
            self.streamBuffer = ""
        }
    }

    #if DEBUG
    /// Só para os hooks DEVSPACE_FAKE_*: simula deltas pelo caminho real.
    func debugStream(_ text: String) { appendStreaming(text) }
    #endif

    private func resetStreaming() {
        streamFlush?.cancel()
        streamFlush = nil
        streamBuffer = ""
        streaming = ""
    }
    var pending: PermissionRequest?
    var prompt: String = ""
    var status: String = ""
    var model: String = ""
    var isBusy = false
    var turnStartedAt: Date?
    var hasUnread = false
    var isRateLimited = false
    var isViewed: (() -> Bool)?
    var metadataDidChange: (() -> Void)?

    struct PendingAttachment: Identifiable, Equatable {
        let id = UUID()
        let data: Data
        let mediaType: String
        var name: String?

        var isImage: Bool { mediaType.hasPrefix("image/") }
    }

    var pendingAttachments: [PendingAttachment] = []

    struct QuestionPrompt: Identifiable {
        struct Option { let label: String; let detail: String }
        struct Question {
            let text: String
            let header: String
            let multiSelect: Bool
            let options: [Option]
        }
        let id: String
        let questions: [Question]
        let request: PermissionRequest
    }

    var pendingQuestion: QuestionPrompt?

    var branch: String?

    var preferredModel: String?

    var preferredEffort: EffortLevel?

    var preferredMode: PermissionMode?

    var detectedMode: PermissionMode?

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
    private var userRenamed = false

    private var harnessSessionID: UUID

    private let isRestored: Bool

    private var hasLaunched = false

    var isLive: Bool { session != nil }

    // MARK: - Nascimento

    init(store: FileTranscriptStore, workingDirectory: URL) {
        self.store = store
        self.sessionID = UUID()
        self.segmentID = UUID()
        self.title = "Nova sessão"
        self.workingDirectory = workingDirectory
        self.harnessSessionID = self.sessionID
        self.isRestored = false
        self.detectedEffort = ClaudeSettings.effortLevel(forWorkingDirectory: workingDirectory)
        self.detectedMode = ClaudeSettings.permissionMode(forWorkingDirectory: workingDirectory)
        restorePreferences()
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
        self.detectedMode = ClaudeSettings.permissionMode(forWorkingDirectory: session.workingDirectory)
        restorePreferences()
        for entry in session.allEntries { render(entry, persist: false) }
    }

    private var domainSession: Session {
        Session(id: sessionID, title: title, workingDirectory: workingDirectory,
                segments: [Segment(id: segmentID, harness: .claudeCode,
                                   harnessSessionID: harnessSessionID, model: model)])
    }

    func persistMetadata() async {
        try? await store.saveMetadata(domainSession)
        metadataDidChange?()
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
                effort: preferredEffort,
                permissionMode: preferredMode
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

    func attach(imageData: Data) {
        pendingAttachments.append(PendingAttachment(data: imageData, mediaType: "image/png"))
    }

    func attach(fileData: Data, name: String, mediaType: String) {
        pendingAttachments.append(
            PendingAttachment(data: fileData, mediaType: mediaType, name: name))
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    private static var attachmentsRoot: URL {
        URL.applicationSupportDirectory.appending(path: "DevSpace/attachments")
    }

    private func persistAttachment(_ pending: PendingAttachment) -> Attachment? {
        let root = Self.attachmentsRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ext = pending.isImage
            ? "png"
            : ((pending.name as NSString?)?.pathExtension).flatMap { $0.isEmpty ? nil : $0 } ?? "bin"
        let file = root.appending(path: "\(UUID().uuidString).\(ext)")
        guard (try? pending.data.write(to: file)) != nil else { return nil }
        var raw: [String: JSONValue] = ["media_type": .string(pending.mediaType)]
        if let name = pending.name { raw["name"] = .string(name) }
        return Attachment(kind: pending.isImage ? "image" : "file",
                          path: file.path, raw: .object(raw))
    }

    func send(text explicit: String? = nil) async {
        let text = (explicit ?? prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = pendingAttachments
        guard !text.isEmpty || !attached.isEmpty else { return }
        prompt = ""
        pendingAttachments = []
        if session == nil { await start() }
        guard let session else { return }

        let stored = attached.compactMap { persistAttachment($0) }
        let entry = TranscriptEntry(
            timestamp: Date(),
            kind: .userMessage(text: text, attachments: stored),
            raw: .object(["type": .string("user"), "text": .string(text)])
        )
        render(entry, persist: true)
        await nameFromFirstTurn(text.isEmpty ? "Anexo" : text)

        isBusy = true
        turnStartedAt = Date()
        do {
            try await session.send(text, attachments: attached.map {
                MediaAttachment(mediaType: $0.mediaType, data: $0.data)
            })
        } catch {
            append(.notice, "não consegui mandar o turno: \(error)")
            isBusy = false
            turnStartedAt = nil
        }
    }

    static func questionPrompt(from request: PermissionRequest) -> QuestionPrompt? {
        guard let items = request.input["questions"]?.arrayValue else { return nil }
        let questions = items.compactMap { item -> QuestionPrompt.Question? in
            guard let text = item["question"]?.stringValue,
                  let options = item["options"]?.arrayValue else { return nil }
            let parsed = options.compactMap { option -> QuestionPrompt.Option? in
                guard let label = option["label"]?.stringValue else { return nil }
                return QuestionPrompt.Option(
                    label: label, detail: option["description"]?.stringValue ?? "")
            }
            guard !parsed.isEmpty else { return nil }
            return QuestionPrompt.Question(
                text: text,
                header: item["header"]?.stringValue ?? "",
                multiSelect: item["multiSelect"]?.boolValue ?? false,
                options: parsed)
        }
        guard !questions.isEmpty else { return nil }
        return QuestionPrompt(id: request.id, questions: questions, request: request)
    }

    func answerQuestion(_ selections: [String: [String]]) async {
        guard let prompt = pendingQuestion, let session else { return }
        pendingQuestion = nil
        var input = prompt.request.input
        if case .object(var members) = input {
            members["answers"] = .object(selections.mapValues {
                .string($0.joined(separator: ", "))
            })
            input = .object(members)
        }
        do {
            try await session.resolve(prompt.id, .allow(updatedInput: input))
            let chosen = prompt.questions.compactMap { question -> String? in
                guard let labels = selections[question.text], !labels.isEmpty else { return nil }
                let joined = labels.joined(separator: ", ")
                guard prompt.questions.count > 1 else { return joined }
                let name = question.header.isEmpty ? question.text : question.header
                return "\(name): \(joined)"
            }.joined(separator: "\n")
            if !chosen.isEmpty {
                let entry = TranscriptEntry(
                    timestamp: Date(),
                    kind: .userMessage(text: chosen, attachments: []),
                    raw: .object(["type": .string("user"), "text": .string(chosen)])
                )
                render(entry, persist: true)
            }
        } catch {
            append(.notice, "não consegui responder a pergunta: \(error)")
        }
    }

    func dismissQuestion() async {
        guard let prompt = pendingQuestion, let session else { return }
        pendingQuestion = nil
        do {
            try await session.resolve(prompt.id, .deny(
                message: "o usuário dispensou a pergunta", interrupt: false))
        } catch {
            append(.notice, "não consegui dispensar a pergunta: \(error)")
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
        persistPreferences()
        await relaunchIfIdle()
    }

    func choose(effort level: EffortLevel?) async {
        guard preferredEffort != level else { return }
        preferredEffort = level
        persistPreferences()
        await relaunchIfIdle()
    }

    func choose(mode: PermissionMode) async {
        guard preferredMode != mode else { return }
        preferredMode = mode
        persistPreferences()
        await relaunchIfIdle()
    }

    func choose(directory: URL) async {
        guard directory.path != workingDirectory.path else { return }
        workingDirectory = directory
        detectedEffort = ClaudeSettings.effortLevel(forWorkingDirectory: directory)
        detectedMode = ClaudeSettings.permissionMode(forWorkingDirectory: directory)
        await persistMetadata()
        await loadBranch()
        await relaunchIfIdle()
    }

    private static let preferencesKey = "DevSpace.sessionPreferences"

    private func restorePreferences() {
        let all = UserDefaults.standard.dictionary(forKey: Self.preferencesKey)
            as? [String: [String: String]] ?? [:]
        guard let mine = all[sessionID.uuidString] else { return }
        preferredModel = mine["model"]
        preferredEffort = mine["effort"].flatMap(EffortLevel.init(rawValue:))
        preferredMode = mine["mode"].flatMap(PermissionMode.init(rawValue:))
    }

    private func persistPreferences() {
        var all = UserDefaults.standard.dictionary(forKey: Self.preferencesKey)
            as? [String: [String: String]] ?? [:]
        var mine: [String: String] = [:]
        mine["model"] = preferredModel
        mine["effort"] = preferredEffort?.rawValue
        mine["mode"] = preferredMode?.rawValue
        all[sessionID.uuidString] = mine.isEmpty ? nil : mine
        UserDefaults.standard.set(all, forKey: Self.preferencesKey)
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
        turnStartedAt = nil
        status = "fria"
    }

    func adoptTitle(_ newTitle: String) {
        title = newTitle
        hasTitle = true
        userRenamed = true
    }

    private func nameFromFirstTurn(_ text: String) async {
        guard !hasTitle else { return }
        hasTitle = true
        title = text.count > 60 ? String(text.prefix(60)) + "…" : text
        await persistMetadata()
        generateTitle(from: text)
    }

    private func generateTitle(from text: String) {
        Task { [weak self] in
            guard let installation = try? await ClaudeDiscovery().discover() else { return }
            let instruction = "Gere um título curto (3 a 5 palavras, sem aspas e sem "
                + "ponto final) que resuma o pedido a seguir, na mesma língua dele. "
                + "Responda somente o título.\n\nPedido: \(text.prefix(600))"
            guard let output = try? await SystemCommandRunner().run(
                installation.executable, ["-p", instruction, "--model", "haiku"]
            ) else { return }
            let cleaned = output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
            guard !cleaned.isEmpty, cleaned.count <= 80, !cleaned.contains("\n") else { return }
            await self?.applyGeneratedTitle(cleaned)
        }
    }

    private func applyGeneratedTitle(_ generated: String) async {
        guard !userRenamed else { return }
        title = generated
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
                resetStreaming()
            case .textDelta(_, let text):
                appendStreaming(text)
            case .notice(let subtype, let text):
                if subtype == "status" { status = text }
            case .thinkingDelta, .toolInputDelta:
                break
            }

        case .entry(let entry):
            render(entry, persist: true)

        case .permission(let request):
            if request.toolName == "AskUserQuestion",
               let prompt = Self.questionPrompt(from: request) {
                pendingQuestion = prompt
            } else {
                pending = request
            }

        case .unrecognizedControl(let unrecognized):
            append(.unknown, "quadro de controle não reconhecido"
                   + (unrecognized.wasAnswered ? "" : " — a sessão pode estar travada"))

        case .ended(let error):

            let midTurn = isBusy
            isBusy = false
            turnStartedAt = nil
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

    private var questionCallIDs: Set<String> = []

    private func render(_ entry: TranscriptEntry, persist: Bool) {
        if persist {
            Task { [store, sessionID, segmentID] in
                try? await store.append(entry, to: segmentID, in: sessionID)
            }
        }

        let moment = entry.timestamp
        switch entry.kind {
        case .userMessage(let text, let attachments):
            let images = attachments.filter { $0.kind == "image" }
                .compactMap { try? Data(contentsOf: URL(fileURLWithPath: $0.path)) }
            let files = attachments.filter { $0.kind == "file" }.map { attachment in
                attachment.raw["name"]?.stringValue
                    ?? (attachment.path as NSString).lastPathComponent
            }
            if images.isEmpty, files.isEmpty {
                append(.user, text, at: moment)
            } else {
                lines.append(Line(id: UUID(), role: .user, text: text,
                                  images: images, files: files, timestamp: moment))
            }
        case .assistantText(let text):
            resetStreaming()
            append(.assistant, text, at: moment)
            if persist, !(isViewed?() ?? false) { hasUnread = true }
        case .assistantThinking(let text):
            append(.thinking, text, at: moment)
        case .toolCall(let call):
            if call.rawName == "AskUserQuestion" {
                questionCallIDs.insert(call.id)
            } else {
                append(.tool, summary(of: call), at: moment, verb: call.canonical)
            }
        case .toolResult(let result):
            if !questionCallIDs.contains(result.callID) {
                append(.toolResult,
                       (result.isError ? "falhou: " : "") + oneLine(result.content),
                       at: moment)
            }
        case .permissionDecision(_, let decision):
            if case .deny(let message, _) = decision { append(.notice, message, at: moment) }
        case .systemNotice(let subtype, let text):
            if subtype == "init", let raw = entry.raw["permissionMode"]?.stringValue {
                detectedMode = raw == "default" ? .manual : PermissionMode(rawValue: raw)
            }
            if subtype == "rate_limit",
               let state = entry.raw["rate_limit_info"]?["status"]?.stringValue {
                isRateLimited = state != "allowed"
            }
            if subtype != "init" && subtype != "rate_limit" { append(.notice, text, at: moment) }
        case .turnResult(let result):

            isBusy = false
            turnStartedAt = nil
            resetStreaming()
            if !result.isError { isRateLimited = false }
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

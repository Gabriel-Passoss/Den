import Foundation
import Observation
import HarnessCore

@MainActor
@Observable
final class ChatModel {

    let sessionID: UUID
    private(set) var segments: [Segment]

    var segmentID: UUID { segments.last?.id ?? UUID() }
    var title: String
    var workingDirectory: URL

    var lines: [ChatLine] = []

    var streaming: String = ""

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

    private func resetStreaming() {
        streamFlush?.cancel()
        streamFlush = nil
        streamBuffer = ""
        streaming = ""
    }

    var compactingSince: Date?

    private(set) var contextTokens: Int = 0

    var contextLabel: String? {
        contextTokens > 0 ? "\(TranscriptFormatter.tokens(contextTokens)) tokens" : nil
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

    var pendingAttachments: [PendingAttachment] = []

    var pendingQuestion: QuestionPrompt?

    var branch: String?

    var catalog: CommandCatalog = .empty {
        didSet { SessionCache.remember(catalog, for: workingDirectory, harness: harness) }
    }

    func run(command: String) async {
        await send(text: command)
    }

    private(set) var harness: HarnessID

    var knobs: [HarnessKnob] = [] {
        didSet { SessionCache.remember(knobs, for: harness) }
    }

    var capabilities = HarnessCapabilities()

    private var settings: [String: String] = [:]

    var harnessName: String { HarnessRegistry.displayName(for: harness) }

    func knob(_ id: String) -> HarnessKnob? { knobs.first { $0.id == id } }

    private let store: FileTranscriptStore
    private var session: (any HarnessSession)?
    private var consumer: Task<Void, Never>?
    private var hasTitle = false
    private var userRenamed = false

    private var harnessSessionID: String

    private var entries: [TranscriptEntry] = []

    private var pendingSeed: String?

    private let isRestored: Bool

    private var hasLaunched = false

    var isLive: Bool { session != nil }

    // MARK: - Nascimento

    init(store: FileTranscriptStore, workingDirectory: URL,
         harness: HarnessID? = nil) {
        self.store = store
        let harness = harness ?? HarnessRegistry.preferred
        let id = UUID()
        self.sessionID = id
        self.title = "Nova sessão"
        self.workingDirectory = workingDirectory
        self.harness = harness
        self.segments = [Segment(harness: harness, harnessSessionID: "", model: "")]

        self.harnessSessionID = ""
        self.isRestored = false
        restorePreferences()
        loadKnobs()
        catalog = SessionCache.rememberedCatalog(for: workingDirectory, harness: harness)
    }

    init(store: FileTranscriptStore, restoring session: Session) {
        self.store = store
        self.sessionID = session.id
        self.segments = session.segments.isEmpty
            ? [Segment(harness: HarnessRegistry.fallback, harnessSessionID: "", model: "")]
            : session.segments.map { var bare = $0; bare.entries = []; return bare }
        self.title = session.title
        self.workingDirectory = session.workingDirectory
        self.model = session.segments.last?.model ?? ""
        self.hasTitle = true
        self.harnessSessionID = session.segments.last?.harnessSessionID ?? ""
        self.harness = session.segments.last?.harness ?? HarnessRegistry.fallback
        self.isRestored = true
        self.status = "fria"
        restorePreferences()
        loadKnobs()
        catalog = SessionCache.rememberedCatalog(for: workingDirectory, harness: harness)
        for entry in session.allEntries { render(entry, persist: false) }

        if let last = session.segments.last, last.seededBy != nil, last.entries.isEmpty {
            pendingSeed = HandoffSeed.make(entries)?.text
        }
    }

    private var domainSession: Session {
        var current = segments
        if !current.isEmpty {

            current[current.count - 1].harnessSessionID = harnessSessionID
            current[current.count - 1].model = model
        }
        return Session(id: sessionID, title: title,
                       workingDirectory: workingDirectory, segments: current)
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
        guard let adapter = HarnessRegistry.harness(for: harness) else {
            status = "falhou: harness desconhecido"
            append(.notice, "não conheço o harness \(harness.rawValue)")
            return
        }
        status = "procurando o \(adapter.displayName)…"
        do {
            let installation = try await adapter.discover()
            capabilities = adapter.capabilities(for: installation)

            let resumable = capabilities.canResumeSession
                && !harnessSessionID.isEmpty
                && lines.contains(where: { $0.role == .assistant })

            let start: SessionStart = resumable
                ? .resume(harnessSessionID: harnessSessionID)
                : .fresh
            hasLaunched = true

            let live = adapter.makeSession(
                installation: installation,
                workingDirectory: workingDirectory,
                settings: settings)
            let updates = try await live.start(start)
            session = live
            knobs = await live.knobs()
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

        if text == SlashCatalog.compactCommand {
            compactingSince = Date()
        } else {
            let stored = attached.compactMap { persistAttachment($0) }
            let entry = TranscriptEntry(
                timestamp: Date(),
                kind: .userMessage(text: text, attachments: stored),
                raw: .object(["type": .string("user"), "text": .string(text)])
            )
            render(entry, persist: true)
            await nameFromFirstTurn(text.isEmpty ? "Anexo" : text)
        }

        let outgoing = pendingSeed.map { HandoffSeed.message(seed: $0, request: text) } ?? text
        pendingSeed = nil

        isBusy = true
        turnStartedAt = Date()
        do {
            try await session.send(UserTurn(text: outgoing, attachments: attached.map {
                MediaAttachment(mediaType: $0.mediaType, data: $0.data)
            }))
        } catch {
            append(.notice, "não consegui mandar o turno: \(error)")
            isBusy = false
            turnStartedAt = nil
        }
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

    func resolve(_ option: PermissionOption) async {
        guard let request = pending, let session else { return }
        pending = nil
        do {
            try await session.resolve(request.id, .option(id: option.id))
        } catch {
            append(.notice, "não consegui responder a permissão: \(error)")
        }
    }

    func resolve(allow: Bool) async {
        guard let request = pending else { return }
        let fallback = allow
            ? request.options.first(where: \.isAllow)
            : request.options.first(where: { !$0.isAllow })
        guard let fallback else { return }
        await resolve(fallback)
    }

    func choose(knob id: String, value: String?) async {
        guard settings[id] != value else { return }
        settings[id] = value
        adopt(knob: id, value: value)
        persistPreferences()

        let live = knob(id)?.category == .model
            ? capabilities.canSetModelInSession
            : capabilities.canSetPermissionMode

        guard let session, live else {
            await relaunchIfIdle()
            return
        }
        do {
            try await session.apply(knob: id, value: value)
            knobs = await session.knobs()
        } catch {
            append(.notice, "não consegui trocar \(id): \(error)")
        }
    }

    static let silentNotices: Set<String> = ["init", "rate_limit", "harness_switch"]

    private func adopt(knob id: String, value: String?) {
        guard let index = knobs.firstIndex(where: { $0.id == id }) else { return }
        knobs[index].currentValue = value
    }

    private func loadKnobs() {
        guard let adapter = HarnessRegistry.harness(for: harness) else { return }

        var discovered = adapter.knobs(for: HarnessInstallation(executable: "", version: ""),
                                       workingDirectory: workingDirectory)
        if discovered.isEmpty { discovered = SessionCache.rememberedKnobs(for: harness) }
        for index in discovered.indices {
            if let chosen = settings[discovered[index].id] {
                discovered[index].currentValue = chosen
            }
        }
        knobs = discovered
    }

    func choose(directory: URL) async {
        guard directory.path != workingDirectory.path else { return }
        workingDirectory = directory
        loadKnobs()
        catalog = SessionCache.rememberedCatalog(for: directory, harness: harness)
        await persistMetadata()
        await loadBranch()
        await relaunchIfIdle()
    }

    private func restorePreferences() {
        settings = SessionCache.preferences(for: sessionID)
    }

    private func persistPreferences() {
        SessionCache.setPreferences(
            settings.compactMapValues { $0.isEmpty ? nil : $0 }, for: sessionID)
    }

    private func relaunchIfIdle() async {
        guard !isBusy else { return }
        if session != nil { await stop() }
        await start()
    }

    var canSwitchHarness: Bool {
        !isBusy && HarnessRegistry.all.count > 1
    }

    func switchHarness(to newHarness: HarnessID) async {
        guard newHarness != harness,
              HarnessRegistry.harness(for: newHarness) != nil else { return }

        let seed = HandoffSeed.make(entries)
        await stop()

        segments.append(Segment(harness: newHarness, harnessSessionID: "",
                                model: "", seededBy: seed?.handoff))
        harness = newHarness
        harnessSessionID = ""
        model = ""
        hasLaunched = false
        settings = [:]
        loadKnobs()
        catalog = SessionCache.rememberedCatalog(for: workingDirectory, harness: newHarness)

        await persistMetadata()

        pendingSeed = seed?.text

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
        guard let adapter = HarnessRegistry.harness(for: harness) else { return }
        let instruction = "Gere um título curto (3 a 5 palavras, sem aspas e sem "
            + "ponto final) que resuma o pedido a seguir, na mesma língua dele. "
            + "Responda somente o título.\n\nPedido: \(text.prefix(600))"

        guard let arguments = adapter.titleArguments(for: instruction) else { return }

        Task { [weak self] in
            guard let installation = try? await adapter.discover() else { return }
            guard let output = try? await SystemCommandRunner().run(
                installation.executable, arguments
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

    private func apply(_ update: SessionUpdate) {
        switch update {
        case .event(let event):
            switch event {
            case .sessionInitialized(let model, let reportedSessionID, let catalog):
                self.model = model
                if !catalog.isEmpty { self.catalog = catalog }

                if !reportedSessionID.isEmpty, reportedSessionID != harnessSessionID {
                    harnessSessionID = reportedSessionID
                }
                Task { await persistMetadata() }
            case .turnStarted:
                resetStreaming()
            case .textDelta(_, let text):
                appendStreaming(text)
            case .notice(let subtype, let text):
                if subtype == "status" { status = text }
            case .contextUsage(let tokens):
                contextTokens = tokens
            case .catalogUpdated(let updated):
                if !updated.isEmpty { catalog = updated }
            case .compaction(let phase):
                switch phase {
                case .started:
                    if compactingSince == nil { compactingSince = Date() }
                case .finished:
                    compactingSince = nil
                case .failed(let reason):
                    compactingSince = nil
                    append(.notice, reason.isEmpty
                           ? "não deu para compactar a conversa"
                           : "não deu para compactar: \(reason)")
                }
            case .thinkingDelta, .toolInputDelta:
                break
            }

        case .entry(let entry):
            render(entry, persist: true)

        case .permission(let request):
            if request.toolName == "AskUserQuestion",
               let prompt = QuestionPrompt(from: request) {
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
            compactingSince = nil
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

        entries.append(entry)
        if persist {
            Task { [store, sessionID, segmentID] in
                try? await store.append(entry, to: segmentID, in: sessionID)
            }
        }

        let moment = entry.timestamp
        switch entry.kind {
        case .userMessage(let text, let attachments):
            if text == SlashCatalog.compactCommand { return }
            if let title = digestTitle(for: text) {
                append(.digest, TranscriptFormatter.unwrapped(text), at: moment, title: title)
                return
            }
            let images = attachments.filter { $0.kind == "image" }
                .compactMap { try? Data(contentsOf: URL(fileURLWithPath: $0.path)) }
            let files = attachments.filter { $0.kind == "file" }.map { attachment in
                attachment.raw["name"]?.stringValue
                    ?? (attachment.path as NSString).lastPathComponent
            }
            if images.isEmpty, files.isEmpty {
                append(.user, text, at: moment)
            } else {
                lines.append(ChatLine(id: UUID(), role: .user, text: text,
                                  images: images, files: files, timestamp: moment))
            }
        case .assistantText(let text):
            resetStreaming()
            if awaitingCompactionSummary {
                awaitingCompactionSummary = false
                append(.digest, text, at: moment, title: Digest.summary)
                return
            }
            append(.assistant, text, at: moment)
            if persist, !(isViewed?() ?? false) { hasUnread = true }
        case .assistantThinking(let text):
            append(.thinking, text, at: moment)
        case .toolCall(let call):
            if call.rawName == "AskUserQuestion" {
                questionCallIDs.insert(call.id)
            } else {
                append(.tool, TranscriptFormatter.summary(of: call), at: moment, verb: call.canonical)
            }
        case .toolResult(let result):
            if !questionCallIDs.contains(result.callID) {
                append(.toolResult,
                       (result.isError ? "falhou: " : "") + TranscriptFormatter.oneLine(result.content),
                       at: moment)
            }
        case .permissionDecision(_, let decision):
            if case .deny(let message, _) = decision { append(.notice, message, at: moment) }
        case .systemNotice(let subtype, let text):
            if subtype == "init", let raw = entry.raw["permissionMode"]?.stringValue,
               let mode = knobs.first(where: { $0.category == .mode }) {
                adopt(knob: mode.id, value: raw == "default" ? "manual" : raw)
            }
            if subtype == "rate_limit",
               let state = entry.raw["rate_limit_info"]?["status"]?.stringValue {
                isRateLimited = state != "allowed"
            }
            if !Self.silentNotices.contains(subtype) { append(.notice, text, at: moment) }
        case .turnResult(let result):

            isBusy = false
            turnStartedAt = nil
            compactingSince = nil
            resetStreaming()
            if !result.isError { isRateLimited = false }
            if let tokens = result.contextTokens { contextTokens = tokens }
            if result.isError {
                append(.notice, "o turno falhou no harness"
                       + (result.stopReason.map { " (\($0))" } ?? ""), at: moment)
            }
        case .contextCompacted(let compaction):
            compactingSince = nil
            if compaction.tokensAfter > 0 { contextTokens = compaction.tokensAfter }
            awaitingCompactionSummary = true
            append(.compaction, TranscriptFormatter.headline(of: compaction), at: moment)
        case .permissionRequest, .unrecognized:

            if entry.raw["type"]?.stringValue == "system",
               let subtype = entry.raw["subtype"]?.stringValue,
               subtype == "hook_started" || subtype == "hook_response" { return }
            append(.unknown, TranscriptFormatter.oneLine(entry.raw), at: moment)
        }
    }

    private func append(_ role: ChatLine.Role, _ text: String,
                        at moment: Date = Date(), verb: CanonicalTool? = nil,
                        title: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append(ChatLine(id: UUID(), role: role, text: trimmed,
                          timestamp: moment, verb: verb, title: title))
    }

    // MARK: - Recados de sistema que chegam como mensagem do usuário

    private var awaitingCompactionSummary = false

    private func digestTitle(for text: String) -> String? {
        if awaitingCompactionSummary
            || text.hasPrefix("This session is being continued") {
            awaitingCompactionSummary = false
            return Digest.summary
        }
        return TranscriptFormatter.envelopes.contains(where: { text.contains("<" + $0 + ">") })
            ? Digest.command
            : nil
    }

}

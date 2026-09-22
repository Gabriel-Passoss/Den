import Foundation
import Observation
import HarnessCore

@MainActor
@Observable
final class CockpitModel {
    struct Line: Identifiable {
        enum Role {
            case user, assistant, thinking, tool, toolResult, notice, unknown
            case compaction, digest

            var isStep: Bool {
                switch self {
                case .thinking, .tool, .toolResult, .notice, .unknown: true
                case .user, .assistant, .compaction, .digest: false
                }
            }
        }
        let id: UUID
        let role: Role
        let text: String
        var images: [Data] = []
        var files: [String] = []

        let timestamp: Date

        var verb: CanonicalTool?

        var title: String?
    }

    let sessionID: UUID
    /// A sessão do DevSpace atravessa harnesses; cada trecho contínuo dentro
    /// de um deles é um Segment. Trocar de harness fecha um e abre o próximo.
    private(set) var segments: [Segment]

    var segmentID: UUID { segments.last?.id ?? UUID() }
    var title: String
    var workingDirectory: URL

    var lines: [Line] = []

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

    /// Compactar leva minutos e não emite nada no meio: o instante de início
    /// é o que sustenta a barra de progresso na tela.
    var compactingSince: Date?

    /// O contexto que o harness reportou na última ida ao modelo: é o que
    /// diz quando vale compactar.
    private(set) var contextTokens: Int = 0

    var contextLabel: String? {
        contextTokens > 0 ? "\(Self.tokens(contextTokens)) tokens" : nil
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

    var catalog: CommandCatalog = .empty {
        didSet { Self.remember(catalog, for: workingDirectory, harness: harness) }
    }

    /// O catálogo é de um harness, não da pasta: guardar os dois juntos faria
    /// o menu do OpenCode abrir com as skills do Claude.
    private static func catalogKey(_ directory: URL, _ harness: HarnessID) -> String {
        "DevSpace.catalog." + harness.rawValue + "." + directory.standardizedFileURL.path
    }

    /// O catálogo só chega quando a sessão sobe; guardar por pasta deixa o
    /// menu de comandos pronto já na primeira digitada de uma sessão fria.
    private static func lastCatalogKey(_ harness: HarnessID) -> String {
        "DevSpace.catalog.last." + harness.rawValue
    }

    static func remember(_ catalog: CommandCatalog, for directory: URL,
                         harness: HarnessID) {
        guard !catalog.isEmpty,
              let data = try? JSONEncoder().encode(catalog) else { return }
        UserDefaults.standard.set(data, forKey: catalogKey(directory, harness))
        UserDefaults.standard.set(data, forKey: lastCatalogKey(harness))
    }

    /// Pasta ainda sem catálogo cai no último conhecido: skills e MCP são
    /// quase sempre do usuário, e o catálogo real chega no primeiro turno.
    static func rememberedCatalog(for directory: URL,
                                  harness: HarnessID) -> CommandCatalog {
        for key in [catalogKey(directory, harness), lastCatalogKey(harness)] {
            if let data = UserDefaults.standard.data(forKey: key),
               let catalog = try? JSONDecoder().decode(CommandCatalog.self, from: data) {
                return catalog
            }
        }
        return .empty
    }

    /// Comandos são enviados como turno: o CLI os interpreta e responde com
    /// os eventos de status correspondentes.
    func run(command: String) async {
        await send(text: command)
    }

    private(set) var harness: HarnessID

    var knobs: [HarnessKnob] = [] {
        didSet { Self.remember(knobs, for: harness) }
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

    /// O transcript semântico, que é o que atravessa a troca de harness.
    /// As `lines` são a tradução dele para a tela e não servem à semente.
    private var entries: [TranscriptEntry] = []

    /// Conversa do segmento anterior, esperando o primeiro pedido do usuário
    /// no harness novo para viajar junto. Some assim que é entregue.
    private var pendingSeed: String?

    private let isRestored: Bool

    private var hasLaunched = false

    var isLive: Bool { session != nil }

    // MARK: - Nascimento

    /// O harness resolve-se no corpo, não no argumento padrão: expressão de
    /// argumento padrão roda fora do ator, e `HarnessRegistry` é do main actor.
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
        catalog = Self.rememberedCatalog(for: workingDirectory, harness: harness)
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
        catalog = Self.rememberedCatalog(for: workingDirectory, harness: harness)
        for entry in session.allEntries { render(entry, persist: false) }

        /// Trocou de harness e fechou o app antes de escrever: a semente nunca
        /// chegou a ninguém, então ela volta a esperar o primeiro pedido.
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

        /// O balão e o transcript guardam o que o usuário escreveu; só o que
        /// sai pelo cabo carrega a conversa herdada da troca de harness.
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

    /// Alguns harnesses trocam o botão em sessão viva; os que não trocam
    /// precisam de um relançamento. `HarnessCapabilities` diz qual é qual, em
    /// vez de a UI supor.
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

    /// Avisos que o transcript guarda mas a tela não mostra. `harness_switch`
    /// está aqui pelas sessões gravadas antes de a troca virar silenciosa —
    /// elas seguem no disco, só não falam mais.
    static let silentNotices: Set<String> = ["init", "rate_limit", "harness_switch"]

    private func adopt(knob id: String, value: String?) {
        guard let index = knobs.firstIndex(where: { $0.id == id }) else { return }
        knobs[index].currentValue = value
    }

    /// Modelo e modo do OpenCode só existem depois do handshake, então numa
    /// sessão ainda fria a barra ficaria vazia. O último conjunto conhecido
    /// segura o lugar até a sessão subir e dizer o que vale agora.
    private static func knobsKey(_ harness: HarnessID) -> String {
        "DevSpace.knobs." + harness.rawValue
    }

    static func remember(_ knobs: [HarnessKnob], for harness: HarnessID) {
        guard !knobs.isEmpty, let data = try? JSONEncoder().encode(knobs) else { return }
        UserDefaults.standard.set(data, forKey: knobsKey(harness))
    }

    static func rememberedKnobs(for harness: HarnessID) -> [HarnessKnob] {
        guard let data = UserDefaults.standard.data(forKey: knobsKey(harness)),
              let knobs = try? JSONDecoder().decode([HarnessKnob].self, from: data)
        else { return [] }
        return knobs
    }

    private func loadKnobs() {
        guard let adapter = HarnessRegistry.harness(for: harness) else { return }

        var discovered = adapter.knobs(for: HarnessInstallation(executable: "", version: ""),
                                       workingDirectory: workingDirectory)
        if discovered.isEmpty { discovered = Self.rememberedKnobs(for: harness) }
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
        catalog = Self.rememberedCatalog(for: directory, harness: harness)
        await persistMetadata()
        await loadBranch()
        await relaunchIfIdle()
    }

    private static let preferencesKey = "DevSpace.sessionPreferences"

    private func restorePreferences() {
        let all = UserDefaults.standard.dictionary(forKey: Self.preferencesKey)
            as? [String: [String: String]] ?? [:]

        settings = all[sessionID.uuidString] ?? [:]
    }

    private func persistPreferences() {
        var all = UserDefaults.standard.dictionary(forKey: Self.preferencesKey)
            as? [String: [String: String]] ?? [:]
        let mine = settings.compactMapValues { $0.isEmpty ? nil : $0 }
        all[sessionID.uuidString] = mine.isEmpty ? nil : mine
        UserDefaults.standard.set(all, forKey: Self.preferencesKey)
    }

    private func relaunchIfIdle() async {
        guard !isBusy else { return }
        if session != nil { await stop() }
        await start()
    }

    var canSwitchHarness: Bool {
        !isBusy && HarnessRegistry.all.count > 1
    }

    /// Fecha o segmento atual e abre o próximo noutro harness, semeado com a
    /// conversa que já aconteceu. Nenhum CLI aceita receber turnos de
    /// assistente, então o contexto vai como a primeira mensagem de usuário.
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
        catalog = Self.rememberedCatalog(for: workingDirectory, harness: newHarness)

        /// O store recusa um append para segmento que não consta do
        /// `session.json`, então o metadata vai ao disco antes de qualquer coisa.
        await persistMetadata()

        /// A troca não escreve no chat nem gasta um turno: a semente espera o
        /// primeiro pedido e viaja colada a ele. Quem trocou vê só o painel
        /// mudar e segue digitando; a proveniência ficou no `seededBy`.
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
                append(.digest, Self.unwrapped(text), at: moment, title: title)
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
                lines.append(Line(id: UUID(), role: .user, text: text,
                                  images: images, files: files, timestamp: moment))
            }
        case .assistantText(let text):
            resetStreaming()
            /// O Claude devolve o resumo da compactação como mensagem de
            /// usuário; o OpenCode, como prosa do assistente. Os dois viram a
            /// mesma linha recolhida embaixo da fronteira.
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
            append(.compaction, Self.headline(of: compaction), at: moment)
        case .permissionRequest, .unrecognized:

            if entry.raw["type"]?.stringValue == "system",
               let subtype = entry.raw["subtype"]?.stringValue,
               subtype == "hook_started" || subtype == "hook_response" { return }
            append(.unknown, oneLine(entry.raw), at: moment)
        }
    }

    private func append(_ role: Line.Role, _ text: String,
                        at moment: Date = Date(), verb: CanonicalTool? = nil,
                        title: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append(Line(id: UUID(), role: role, text: trimmed,
                          timestamp: moment, verb: verb, title: title))
    }

    // MARK: - Recados de sistema que chegam como mensagem do usuário

    /// O resumo da compactação vem logo depois da fronteira; sessões antigas,
    /// gravadas antes de a fronteira existir, caem no texto de abertura.
    private var awaitingCompactionSummary = false

    enum Digest {
        static let summary = "Resumo da conversa anterior"
        static let command = "Saída de comando local"
    }

    private func digestTitle(for text: String) -> String? {
        if awaitingCompactionSummary
            || text.hasPrefix("This session is being continued") {
            awaitingCompactionSummary = false
            return Digest.summary
        }
        return Self.envelopes.contains(where: { text.contains("<" + $0 + ">") })
            ? Digest.command
            : nil
    }

    private static let envelopes = [
        "local-command-caveat", "command-name", "command-message",
        "command-args", "local-command-stdout", "local-command-stderr",
    ]

    private static func unwrapped(_ text: String) -> String {
        var out = text
        for tag in envelopes {
            out = out.replacingOccurrences(of: "<" + tag + ">", with: "")
            out = out.replacingOccurrences(of: "</" + tag + ">", with: "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func headline(of compaction: ContextCompaction) -> String {
        var parts = ["Conversa compactada"]
        if compaction.tokensBefore > 0, compaction.tokensAfter > 0 {
            parts.append("\(tokens(compaction.tokensBefore)) → "
                         + "\(tokens(compaction.tokensAfter)) tokens")
        }
        if compaction.duration >= 1 { parts.append(elapsed(compaction.duration)) }
        return parts.joined(separator: " · ")
    }

    private static func tokens(_ value: Int) -> String {
        value >= 1_000 ? "\(Int((Double(value) / 1_000).rounded()))k" : String(value)
    }

    private static func elapsed(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)min \(seconds % 60)s"
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
            if line.role.isStep { run.append(line) }
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

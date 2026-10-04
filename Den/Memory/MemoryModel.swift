import Foundation
import Observation
import HarnessCore
import DenStore
import DenMemory

@MainActor
@Observable
final class MemoryModel {
    enum Status: Equatable {
        case idle
        case capturing
        case saved(Int)
        case nothingNew
        case failed(String)
    }

    typealias Run = @Sendable (_ executable: String, _ arguments: [String],
                               _ timeout: Duration) async -> ProcessOutcome?

    static let enabledKey = "Den.memoryEnabled"
    static let turnThreshold = 3
    static let leaveThreshold = 1
    static let timeout: Duration = .seconds(60)

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    private(set) var status: Status = .idle
    private(set) var revision = 0

    @ObservationIgnored private let repository: any MemoryRepository
    @ObservationIgnored private let marks: any SessionDocumentRepository<MemoryCaptureMark>
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let registry: HarnessRegistry
    @ObservationIgnored private let run: Run
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var known: [UUID: MemoryCaptureMark]
    @ObservationIgnored private var capturing: Set<UUID> = []
    @ObservationIgnored private var unbriefed: Set<UUID> = []

    init(repository: any MemoryRepository, marks: any SessionDocumentRepository<MemoryCaptureMark>,
         defaults: UserDefaults, registry: HarnessRegistry = .standard,
         run: @escaping Run = { await TimedProcess.run($0, $1, timeout: $2) },
         now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.marks = marks
        self.defaults = defaults
        self.registry = registry
        self.run = run
        self.now = now
        known = marks.all()
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func project(for directory: URL) -> ProjectIdentity? {
        ProjectLocator.project(containing: directory)
    }

    func pages(in scope: MemoryScope) -> [MemoryPage] {
        repository.pages(in: scope)
    }

    func file(for page: MemoryPage, in scope: MemoryScope) -> URL {
        repository.file(for: page.slug, in: scope)
    }

    func directory(of scope: MemoryScope) -> URL {
        repository.directory(of: scope)
    }

    func delete(_ page: MemoryPage, in scope: MemoryScope) {
        do {
            try repository.delete(page.slug, in: scope)
        } catch {
            status = .failed("não consegui apagar a memória: \(error.localizedDescription)")
        }
        revision += 1
    }

    func reload() {
        revision += 1
    }

    func preamble(for directory: URL) -> String? {
        guard isEnabled else { return nil }
        return MemoryRecall.preamble(shelves(for: directory)) { [repository] page, scope in
            repository.file(for: page.slug, in: scope)
        }
    }

    func sessionStarted(_ session: UUID, fresh: Bool) {
        if fresh {
            unbriefed.insert(session)
        } else {
            unbriefed.remove(session)
        }
    }

    func opening(_ outgoing: String, typed: String, session: UUID, directory: URL) -> String {
        guard unbriefed.contains(session), !typed.hasPrefix("/") else { return outgoing }
        unbriefed.remove(session)
        guard let preamble = preamble(for: directory) else { return outgoing }
        return MemoryRecall.message(preamble: preamble, request: outgoing)
    }

    func capture(session: UUID, entries: [TranscriptEntry], directory: URL, harness: HarnessID,
                 atLeast threshold: Int, announcing: Bool = false) async {
        guard isEnabled, !capturing.contains(session) else { return }
        let fresh = pending(entries, for: session)
        guard let last = entries.last, MemoryExtraction.userTurns(in: fresh) >= threshold,
              let instruction = MemoryExtraction.instruction(entries: fresh, shelves: shelves(for: directory))
        else {
            if announcing { status = .nothingNew }
            return
        }
        capturing.insert(session)
        defer { capturing.remove(session) }
        status = .capturing
        status = await consolidate(instruction, session: session, directory: directory,
                                   harness: harness, upTo: last.id)
    }

    private func consolidate(_ instruction: String, session: UUID, directory: URL,
                             harness: HarnessID, upTo last: UUID) async -> Status {
        let answer: String
        switch await ask(instruction, through: harness) {
        case .unavailable: return .failed("este harness não faz a chamada avulsa que a memória usa")
        case .failed: return .failed("a chamada ao harness falhou")
        case .answered(let output): answer = output
        }
        guard isEnabled else { return .idle }
        guard let candidates = MemoryExtraction.candidates(from: answer) else {
            return .failed("a resposta do harness não veio no formato esperado")
        }
        do {
            let saved = try MemoryConsolidator(repository: repository)
                .apply(candidates, project: project(for: directory), session: session, now: now())
            remember(MemoryCaptureMark(lastEntry: last, capturedAt: now()), for: session)
            guard !saved.isEmpty else { return .nothingNew }
            revision += 1
            return .saved(saved.count)
        } catch {
            return .failed("não consegui gravar a memória: \(error.localizedDescription)")
        }
    }

    private enum Answer {
        case unavailable
        case failed
        case answered(String)
    }

    private func ask(_ instruction: String, through harness: HarnessID) async -> Answer {
        guard let adapter = registry.harness(for: harness),
              let arguments = adapter.quickPromptArguments(for: instruction),
              let installation = try? await adapter.discover() else { return .unavailable }
        guard let outcome = await run(installation.executable, arguments, Self.timeout),
              outcome.succeeded else { return .failed }
        return .answered(outcome.output)
    }

    private func shelves(for directory: URL) -> [MemoryRecall.Shelf] {
        var shelves = [MemoryRecall.Shelf(scope: .user, pages: repository.pages(in: .user))]
        if let project = project(for: directory) {
            let scope = MemoryScope.project(project)
            shelves.append(MemoryRecall.Shelf(scope: scope, pages: repository.pages(in: scope)))
        }
        return shelves
    }

    private func pending(_ entries: [TranscriptEntry], for session: UUID) -> [TranscriptEntry] {
        guard let mark = known[session],
              let index = entries.lastIndex(where: { $0.id == mark.lastEntry }) else { return entries }
        return Array(entries[(index + 1)...])
    }

    private func remember(_ mark: MemoryCaptureMark, for session: UUID) {
        known[session] = mark
        try? marks.save(mark, for: session)
    }
}

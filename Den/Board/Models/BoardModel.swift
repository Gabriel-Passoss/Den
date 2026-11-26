import DenStore
import Foundation
import Observation
import Workflow

@MainActor
@Observable
final class BoardModel {
    enum Content: Equatable {
        case loading
        case noProject
        case failed
        case board(name: String, display: BoardDisplay)
    }

    private(set) var content: Content = .loading
    private(set) var selectedTaskID: UUID?
    private(set) var moveNotice: MoveNotice?

    @ObservationIgnored private let repository: any BoardRepository
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let wait: @Sendable (TimeInterval) async throws -> Void
    @ObservationIgnored private var project: Project?
    @ObservationIgnored private var board = Board()
    @ObservationIgnored private var window = UndoWindow()
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var saveFailed = false

    init(repository: any BoardRepository,
         now: @escaping @MainActor () -> Date = { Date() },
         wait: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.repository = repository
        self.now = now
        self.wait = wait
    }

    func load() {
        do {
            guard let project = try repository.projects().first else {
                content = .noProject
                return
            }
            self.project = project
            saveFailed = false
            board = try repository.board(of: project.id)
            refresh()
        } catch {
            content = .failed
        }
    }

    func select(_ id: UUID) {
        selectedTaskID = selectedTaskID == id ? nil : id
    }

    func move(_ card: UUID, to column: UUID) {
        let displaced: UndoableMove?
        do {
            displaced = try window.open(TaskID(rawValue: card), to: StageID(rawValue: column), on: board, at: now())
        } catch {
            return
        }
        complete(displaced)
        scheduleExpiry()
        refresh()
    }

    func undo() {
        guard (try? window.undo(at: now())) != nil else { return }
        expiry?.cancel()
        refresh()
    }

    func settle() {
        guard let expired = window.close(at: now()) else { return }
        complete(expired)
        refresh()
    }

    func finishMove() {
        guard let move = window.move else { return }
        _ = window.close(at: move.expiresAt)
        expiry?.cancel()
        complete(move)
        refresh()
    }

    func selectNextNeedingMe() -> CardPlace? {
        let waiting = cardsNeedingMe
        guard !waiting.isEmpty else { return nil }
        let next = selectedTaskID.flatMap { id in waiting.firstIndex { $0.card == id } }
            .map { waiting[($0 + 1) % waiting.count] } ?? waiting[0]
        selectedTaskID = next.card
        return next
    }

    private func complete(_ move: UndoableMove?) {
        guard let move, let project else { return }
        do {
            try board.complete(move)
        } catch {
            return
        }
        do {
            try repository.save(board, of: project.id)
        } catch {
            saveFailed = true
        }
    }

    private func scheduleExpiry() {
        expiry?.cancel()
        guard let move = window.move else { return }
        let delay = move.expiresAt.timeIntervalSince(now())
        expiry = Task { [weak self, wait] in
            do {
                try await wait(delay)
            } catch {
                return
            }
            self?.settle()
        }
    }

    private func refresh() {
        guard let project else { return }
        guard !saveFailed else {
            content = .failed
            moveNotice = nil
            return
        }
        content = .board(name: project.name, display: BoardPresentation.display(of: board, showing: window.move))
        moveNotice = window.move.flatMap { move in
            guard let task = board.task(move.task), let stage = board.stage(move.to) else { return nil }
            return MoveNotice(task: task.title, stage: stage.name)
        }
    }

    private var cardsNeedingMe: [CardPlace] {
        guard case .board(_, let display) = content else { return [] }
        return display.columns.flatMap { column in
            column.cards
                .filter { $0.status == .failed || $0.status == .needsMe }
                .map { CardPlace(column: column.id, card: $0.id) }
        }
    }
}

struct CardPlace: Equatable {
    let column: UUID
    let card: UUID
}

nonisolated struct MoveNotice: Equatable {
    let task: String
    let stage: String

    var message: String {
        "“\(task)” movida para \(stage)"
    }
}

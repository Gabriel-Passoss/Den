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

    @ObservationIgnored private let repository: any BoardRepository

    init(repository: any BoardRepository) {
        self.repository = repository
    }

    func load() {
        do {
            guard let project = try repository.projects().first else {
                content = .noProject
                return
            }
            let board = try repository.board(of: project.id)
            content = .board(name: project.name, display: BoardPresentation.display(of: board))
        } catch {
            content = .failed
        }
    }

    func select(_ id: UUID) {
        selectedTaskID = selectedTaskID == id ? nil : id
    }

    func selectNextNeedingMe() -> CardPlace? {
        let waiting = cardsNeedingMe
        guard !waiting.isEmpty else { return nil }
        let next = selectedTaskID.flatMap { id in waiting.firstIndex { $0.card == id } }
            .map { waiting[($0 + 1) % waiting.count] } ?? waiting[0]
        selectedTaskID = next.card
        return next
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

@testable import Den
import Workflow

func card(_ id: TaskID, on board: Board) -> CardDisplay? {
    BoardPresentation.columns(for: board).flatMap(\.cards).first { $0.id == id }
}

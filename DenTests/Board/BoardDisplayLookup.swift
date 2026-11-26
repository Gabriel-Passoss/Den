@testable import Den
import Workflow

func card(_ id: TaskID, on board: Board) -> CardDisplay? {
    BoardPresentation.display(of: board).columns.flatMap(\.cards).first { $0.id == id.rawValue }
}

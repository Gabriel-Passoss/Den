import Workflow

nonisolated extension BoardPresentation {
    static func needsMeCount(on board: Board) -> Int {
        board.tasks.count(where: \.needsMe)
    }

    static func needsMeLabel(_ count: Int) -> String? {
        switch count {
        case ...0: nil
        case 1: "1 precisa de você"
        default: "\(count) precisam de você"
        }
    }
}

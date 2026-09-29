import Foundation

enum ChatBlock: Identifiable {
    case line(ChatLine)
    case collapsed(id: UUID, lines: [ChatLine])
    var id: UUID {
        switch self {
        case .line(let line): return line.id
        case .collapsed(let id, _): return id
        }
    }
}

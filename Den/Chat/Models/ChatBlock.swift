import Foundation

enum ChatBlock: Identifiable {
    case line(ChatLine)
    case collapsed(id: UUID, lines: [ChatLine])
    var id: UUID {
        switch self {
        case .line(let line): line.id
        case .collapsed(let id, _): id
        }
    }
}

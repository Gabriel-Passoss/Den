import Foundation

enum InspectorPane: String {
    case closed = ""
    case changes
    case run

    var shortcut: String {
        switch self {
        case .closed, .changes: "⌥⌘0"
        case .run: "⌥⌘9"
        }
    }

    static let storageKey = "Den.inspector"
}

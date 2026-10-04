import Foundation

enum InspectorPane: String {
    case closed = ""
    case changes
    case run
    case memory

    var shortcut: String {
        switch self {
        case .closed, .changes: "⌥⌘0"
        case .run: "⌥⌘9"
        case .memory: "⌥⌘8"
        }
    }

    static let storageKey = "Den.inspector"
}

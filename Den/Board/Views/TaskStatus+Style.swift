import SwiftUI

extension TaskStatus {
    var color: Color {
        switch self {
        case .failed: Theme.removed
        case .needsMe: Theme.waiting
        case .running: Theme.accent
        case .concluded: Theme.added
        case .stopped: Theme.textTertiary
        case .notStarted: Theme.textMuted
        }
    }

    var symbol: String {
        switch self {
        case .failed: "exclamationmark.triangle.fill"
        case .needsMe: "hand.raised.fill"
        case .running: "circle.dotted"
        case .concluded: "checkmark.circle.fill"
        case .stopped: "pause.circle"
        case .notStarted: "circle"
        }
    }
}

import SwiftUI

extension PullRequestTone {
    var color: Color {
        switch self {
        case .failure: Theme.removed
        case .attention: Theme.modified
        case .open: Theme.added
        case .draft, .closed: Theme.textTertiary
        case .merged: Theme.accent
        }
    }

    var symbol: String {
        self == .merged ? "arrow.triangle.merge" : "arrow.triangle.pull"
    }
}

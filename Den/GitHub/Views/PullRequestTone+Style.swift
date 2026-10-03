import SwiftUI

extension PullRequestTone {
    var color: Color {
        switch self {
        case .failure: .red
        case .attention: .orange
        case .open: .green
        case .draft, .closed: .gray
        case .merged: InlineCode.color
        }
    }

    var symbol: String {
        self == .merged ? "arrow.triangle.merge" : "arrow.triangle.pull"
    }
}

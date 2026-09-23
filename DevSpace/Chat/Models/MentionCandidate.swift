import Foundation

struct MentionCandidate: Identifiable {
    let path: String
    let isDirectory: Bool
    var id: String { path }
}

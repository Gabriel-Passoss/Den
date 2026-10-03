import Foundation

nonisolated struct WorktreePlan: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let name: String
        let main: URL
        let worktree: URL
    }

    struct Link: Equatable, Sendable {
        let source: URL
        let destination: URL
    }

    let branch: String
    let sessionDirectory: URL
    let mirrorRoot: URL?
    let entries: [Entry]
    let links: [Link]
}

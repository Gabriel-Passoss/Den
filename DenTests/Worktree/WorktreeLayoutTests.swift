import Testing
import Foundation
@testable import Den

private func write(_ text: String, to file: URL) throws {
    try text.write(to: file, atomically: true, encoding: .utf8)
}

@Test func aFolderInsideARepoIsASingleRepoLayout() throws {
    let root = try makeTree([".git", "api/src"])
    defer { try? FileManager.default.removeItem(at: root) }

    let layout = WorktreeLayout.detect(root.appending(path: "api/src"))

    #expect(layout == .single(RepoCandidate(toplevel: root, main: root)))
}

@Test func aFolderWithReposBelowIsAMultipleLayout() throws {
    let root = try makeTree(["backend/.git", "apps/frontend/.git", "docs"])
    defer { try? FileManager.default.removeItem(at: root) }

    let layout = try #require(WorktreeLayout.detect(root))

    guard case .multiple(let folder, let repos) = layout else {
        Issue.record("expected several repos, got \(layout)")
        return
    }
    #expect(folder.path == root.path)
    #expect(Set(repos.map(\.name)) == ["backend", "frontend"])
}

@Test func aPlainFolderOffersNoLayout() throws {
    let root = try makeTree(["notes"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(WorktreeLayout.detect(root) == nil)
}

@Test func aLinkedWorktreeLeadsBackToItsMainCheckout() throws {
    let root = try makeTree(["main/.git/worktrees/feature", "elsewhere/feature"])
    defer { try? FileManager.default.removeItem(at: root) }
    let feature = root.appending(path: "elsewhere/feature")
    try write("gitdir: \(root.path)/main/.git/worktrees/feature\n", to: feature.appending(path: ".git"))

    #expect(GitRepository.mainCheckout(of: feature).path == root.appending(path: "main").path)
    #expect(RepoCandidate(toplevel: feature).name == "main")
}

@Test func aRelativeGitdirIsResolved() throws {
    let root = try makeTree(["main/.git/worktrees/feature", "elsewhere/feature"])
    defer { try? FileManager.default.removeItem(at: root) }
    let feature = root.appending(path: "elsewhere/feature")
    try write("gitdir: ../../main/.git/worktrees/feature\n", to: feature.appending(path: ".git"))

    #expect(GitRepository.mainCheckout(of: feature).path == root.appending(path: "main").path)
}

@Test func aSubmoduleIsItsOwnCheckout() throws {
    let root = try makeTree([".git/modules/sub", "sub"])
    defer { try? FileManager.default.removeItem(at: root) }
    let sub = root.appending(path: "sub")
    try write("gitdir: ../.git/modules/sub\n", to: sub.appending(path: ".git"))

    #expect(GitRepository.mainCheckout(of: sub).path == sub.path)
}

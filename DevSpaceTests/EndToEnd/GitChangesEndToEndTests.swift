import Testing
import Foundation
import HarnessCore
@testable import DevSpace

// The git panel against a real repository driven by /usr/bin/git, instead of
// fake `.git` folders and canned porcelain.

private func git(_ arguments: [String], in directory: URL) async throws {
    // The user's own config must not leak in: no signing, no hooks.
    _ = try await SystemCommandRunner().run("/usr/bin/git", [
        "-C", directory.path, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
        "-c", "user.name=DevSpace Tests", "-c", "user.email=tests@devspace.invalid",
    ] + arguments)
}

private func write(_ text: String, to name: String, in directory: URL) throws {
    try text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
}

/// A repository on `main` with one commit, then edited the way a harness
/// would leave it: one file changed, one deleted, one created.
private func withEditedRepository(_ body: (URL) async throws -> Void) async throws {
    let repository = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repository) }

    try await git(["init", "-q", "-b", "main"], in: repository)
    try write("let greeting = \"oi\"\nprint(greeting)\n", to: "App.swift", in: repository)
    try write("old notes\n", to: "NOTES.md", in: repository)
    try await git(["add", "."], in: repository)
    try await git(["commit", "-q", "-m", "initial"], in: repository)

    try write("let greeting = \"olá\"\nprint(greeting)\n", to: "App.swift", in: repository)
    try FileManager.default.removeItem(at: repository.appending(path: "NOTES.md"))
    try write("fresh\n", to: "README.md", in: repository)

    try await body(repository)
}

@Test func thePanelListsWhatChangedInARealRepository() async throws {
    try await withEditedRepository { repository in
        let changes = GitChangesModel()
        await changes.load(directory: repository)

        let repo = try #require(changes.repos.first)
        #expect(changes.hasRepo)
        #expect(repo.branch == "main")
        let states = Dictionary(uniqueKeysWithValues: repo.files.map { ($0.path, $0.state) })
        #expect(states == ["App.swift": .modified, "NOTES.md": .deleted, "README.md": .untracked])
        #expect(changes.changeCount == 3)
    }
}

@Test func aModifiedFileShowsItsRealDiff() async throws {
    try await withEditedRepository { repository in
        let changes = GitChangesModel()
        await changes.load(directory: repository)

        let file = try #require(changes.repos.first?.files.first { $0.path == "App.swift" })
        let removed = file.lines.filter { $0.kind == .removed }.map { String($0.text.characters) }
        let added = file.lines.filter { $0.kind == .added }.map { String($0.text.characters) }
        #expect(removed == ["let greeting = \"oi\""])
        #expect(added == ["let greeting = \"olá\""])
    }
}

@Test func committingEmptiesThePanelOnTheNextLoad() async throws {
    try await withEditedRepository { repository in
        let changes = GitChangesModel()
        await changes.load(directory: repository)
        #expect(changes.changeCount == 3)

        try await git(["add", "-A"], in: repository)
        try await git(["commit", "-q", "-m", "edits"], in: repository)
        await changes.load(directory: repository)

        #expect(changes.changeCount == 0)
        #expect(changes.hasRepo)
    }
}

@Test func theChatHeaderNamesTheBranchOfItsProject() async throws {
    try await withEditedRepository { repository in
        try await git(["switch", "-q", "-c", "feature/e2e"], in: repository)
        let chat = inertChat()
        await chat.choose(directory: repository)

        #expect(chat.branch == "feature/e2e")
        #expect(chat.locationSummary == repository.lastPathComponent + " · branch feature/e2e")
    }
}

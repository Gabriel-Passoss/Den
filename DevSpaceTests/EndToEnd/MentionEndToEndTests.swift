import Testing
import Foundation
import HarnessCore
@testable import DevSpace

// Mentions against real projects on disk the size of a web app and a Java
// service side by side, where an index that runs out of room loses whole
// folders and deep files.

/// More entries than the index held before it skipped build output and
/// duplicate checkouts.
private let bigFolderSize = 4100

private func makeBigProject(in project: URL) throws {
    let files = FileManager.default
    for folder in ["frontend/src", "scalemed-backend/src"] {
        try files.createDirectory(at: project.appending(path: folder),
                                  withIntermediateDirectories: true)
        for number in 0..<bigFolderSize {
            files.createFile(atPath: project.appending(path: "\(folder)/f\(number)").path,
                             contents: nil)
        }
    }
    files.createFile(atPath: project.appending(path: "scalemed-backend/pom.xml").path,
                     contents: nil)
}

private func git(_ arguments: [String], in directory: URL) async throws {
    // The user's own config must not leak in: no signing, no hooks.
    _ = try await SystemCommandRunner().run("/usr/bin/git", [
        "-C", directory.path, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
        "-c", "user.name=DevSpace Tests", "-c", "user.email=tests@devspace.invalid",
    ] + arguments)
}

private let deepSource =
    "scalemed-backend/scalemed-core/src/main/java/br/com/scalemed/indicators/IndicatorsRepository.java"

/// A backend the way it sits in a multi-repo folder: more sources than the old
/// limit, Maven's `target/`, and a worktree checked out for another branch.
private func makeBackendWithWorktree(in project: URL) async throws {
    let files = FileManager.default
    let backend = project.appending(path: "scalemed-backend")
    for folder in ["src", "target/classes"] {
        try files.createDirectory(at: backend.appending(path: folder),
                                  withIntermediateDirectories: true)
    }
    try files.createDirectory(at: project.appending(path: deepSource).deletingLastPathComponent(),
                              withIntermediateDirectories: true)
    files.createFile(atPath: project.appending(path: deepSource).path, contents: nil)
    for number in 0..<bigFolderSize {
        files.createFile(atPath: backend.appending(path: "src/f\(number)").path, contents: nil)
        files.createFile(atPath: backend.appending(path: "target/classes/f\(number).class").path,
                         contents: nil)
    }
    try "target/\n".write(to: backend.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
    try await git(["init", "-q", "-b", "main"], in: backend)
    try await git(["add", "."], in: backend)
    try await git(["commit", "-q", "-m", "initial"], in: backend)
    try await git(["worktree", "add", "-q", "-b", "ns-1",
                   project.appending(path: "worktrees/NS-1/backend").path], in: backend)
}

@Test func aDeepSourceBesideBuildOutputAndAWorktreeCanBeMentioned() async throws {
    try await withEndToEnd { e2e in
        try await makeBackendWithWorktree(in: e2e.project)
        let chat = try await e2e.newChat()
        let mentions = MentionController()
        await mentions.loadIndex(under: chat.workingDirectory)

        chat.prompt = "@IndicatorsRepo"
        #expect(mentions.matches(prompt: chat.prompt).map(\.path) == [deepSource])
        #expect(!mentions.fileIndex.contains { $0.path.contains("/target/") })
    }
}

@Test func everyTopLevelFolderOfABigProjectCanBeMentioned() async throws {
    try await withEndToEnd { e2e in
        try makeBigProject(in: e2e.project)
        let chat = try await e2e.newChat()
        let mentions = MentionController()
        await mentions.loadIndex(under: chat.workingDirectory)

        for folder in ["frontend", "scalemed-backend"] {
            chat.prompt = "@" + folder
            #expect(mentions.matches(prompt: chat.prompt).first?.path == folder)
        }
    }
}

@Test func aMentionInsideTheBackendReachesTheCLI() async throws {
    try await withEndToEnd { e2e in
        try makeBigProject(in: e2e.project)
        try e2e.claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        let chat = try await e2e.newChat()
        let mentions = MentionController()
        await mentions.loadIndex(under: chat.workingDirectory)

        chat.prompt = "leia @scalemed"
        let folder = try #require(mentions.matches(prompt: chat.prompt).first)
        mentions.accept(folder, in: chat)
        chat.prompt += "pom"
        let file = try #require(mentions.matches(prompt: chat.prompt).first)
        mentions.accept(file, in: chat)
        #expect(chat.prompt == "leia @scalemed-backend/pom.xml ")

        await chat.send(text: chat.prompt)
        await settle(within: processPatience) { !chat.isBusy }

        #expect(e2e.claude.received.contains { $0.contains("leia @scalemed-backend/pom.xml") })
    }
}

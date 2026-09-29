import Testing
import Foundation
import HarnessCore
@testable import Den

private let bigFolderSize = 4100

private func makeBigProject(in project: URL) throws {
    let files = FileManager.default
    for folder in ["admin-web/src", "orders-api/src"] {
        try files.createDirectory(at: project.appending(path: folder),
                                  withIntermediateDirectories: true)
        for number in 0..<bigFolderSize {
            files.createFile(atPath: project.appending(path: "\(folder)/f\(number)").path,
                             contents: nil)
        }
    }
    files.createFile(atPath: project.appending(path: "orders-api/pom.xml").path,
                     contents: nil)
}

private func git(_ arguments: [String], in directory: URL) async throws {
    _ = try await SystemCommandRunner().run("/usr/bin/git", [
        "-C", directory.path, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
        "-c", "user.name=Den Tests", "-c", "user.email=tests@den.invalid",
    ] + arguments)
}

private let deepSource =
    "orders-api/orders-domain/src/main/java/com/example/orders/OrderRepository.java"

private func makeBackendWithWorktree(in project: URL) async throws {
    let files = FileManager.default
    let backend = project.appending(path: "orders-api")
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
    try await git(["worktree", "add", "-q", "-b", "feature-1",
                   project.appending(path: "worktrees/feature-1/orders-api").path], in: backend)
}

@Test func aDeepSourceBesideBuildOutputAndAWorktreeCanBeMentioned() async throws {
    try await withEndToEnd { e2e in
        try await makeBackendWithWorktree(in: e2e.project)
        let chat = try await e2e.newChat()
        let mentions = MentionController()
        await mentions.loadIndex(under: chat.workingDirectory)

        chat.prompt = "@OrderRepo"
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

        for folder in ["admin-web", "orders-api"] {
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

        chat.prompt = "leia @orders"
        let folder = try #require(mentions.matches(prompt: chat.prompt).first)
        mentions.accept(folder, in: chat)
        chat.prompt += "pom"
        let file = try #require(mentions.matches(prompt: chat.prompt).first)
        mentions.accept(file, in: chat)
        #expect(chat.prompt == "leia @orders-api/pom.xml ")

        await chat.send(text: chat.prompt)
        await settle(within: processPatience) { !chat.isBusy }

        #expect(e2e.claude.received.contains { $0.contains("leia @orders-api/pom.xml") })
    }
}

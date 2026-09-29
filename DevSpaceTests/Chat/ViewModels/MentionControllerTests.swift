import Testing
import Foundation
@testable import DevSpace

@Test func queryDetectsAnActiveMentionToken() {
    let controller = MentionController()
    #expect(controller.query(in: "see @Sources/App") == "Sources/App")
    #expect(controller.query(in: "@") == "")
    #expect(controller.query(in: "email@example.com") == nil)
    #expect(controller.query(in: "see @one two") == nil)
    #expect(controller.query(in: "no mention") == nil)
}

@Test func matchesRankNameHitsAboveDeepPathHits() {
    let controller = MentionController()
    controller.fileIndex = [
        MentionCandidate(path: "chat/Notes.txt", isDirectory: false),
        MentionCandidate(path: "Docs/my-chat.md", isDirectory: false),
        MentionCandidate(path: "Sources/Chat/ChatView.swift", isDirectory: false),
    ]
    let hits = controller.matches(prompt: "see @chat")
    #expect(hits.map(\.path) == [
        "Sources/Chat/ChatView.swift",
        "Docs/my-chat.md",
        "chat/Notes.txt",
    ])

    controller.dismissed = true
    #expect(controller.matches(prompt: "see @chat").isEmpty)
}

@Test func matchesOfferTheIndexWhileTheQueryIsEmpty() {
    let controller = MentionController()
    controller.fileIndex = (0..<12).map {
        MentionCandidate(path: "file-\($0).txt", isDirectory: false)
    }
    #expect(controller.matches(prompt: "@").count == 8)
}

@Test func matchesKeepTheIndexOrderWithinARank() {
    let controller = MentionController()
    controller.fileIndex = [MentionCandidate(path: "files/notes.md", isDirectory: false)]
        + (0..<12).map { MentionCandidate(path: "src/file-\($0).txt", isDirectory: false) }

    #expect(controller.matches(prompt: "@file").map(\.path)
            == (0..<8).map { "src/file-\($0).txt" })
}

@Test func matchesFindAccentsHoweverTheFileSystemSpellsThem() {
    let controller = MentionController()
    controller.fileIndex = [MentionCandidate(path: "docs/relato\u{301}rio.md", isDirectory: false)]

    #expect(controller.matches(prompt: "@Relató").map(\.path) == ["docs/relato\u{301}rio.md"])
}

@Test func indexFilesSkipsVendoredAndHiddenEntries() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let files = FileManager.default
    try files.createDirectory(at: root.appending(path: "Sub"),
                              withIntermediateDirectories: true)
    try files.createDirectory(at: root.appending(path: "node_modules"),
                              withIntermediateDirectories: true)
    try Data().write(to: root.appending(path: "a.swift"))
    try Data().write(to: root.appending(path: "Sub/b.swift"))
    try Data().write(to: root.appending(path: "node_modules/x.js"))
    try Data().write(to: root.appending(path: ".hidden"))

    let candidates = MentionController.indexFiles(under: root)
    #expect(candidates.map(\.path) == ["Sub", "a.swift", "Sub/b.swift"])
    #expect(candidates.first?.isDirectory == true)
}

@Test func indexFilesSkipBuildOutput() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let files = FileManager.default
    for folder in ["src", "target/classes", "out", "coverage"] {
        try files.createDirectory(at: root.appending(path: folder),
                                  withIntermediateDirectories: true)
    }
    try Data().write(to: root.appending(path: "src/App.java"))
    try Data().write(to: root.appending(path: "target/classes/App.class"))
    try Data().write(to: root.appending(path: "out/App.class"))
    try Data().write(to: root.appending(path: "coverage/lcov.info"))

    #expect(MentionController.indexFiles(under: root).map(\.path) == ["src", "src/App.java"])
}

@Test func indexFilesSkipOtherCheckoutsOfARepoInTheProject() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let files = FileManager.default
    func checkout(_ folder: String, gitdir: String) throws {
        try files.createDirectory(at: root.appending(path: folder),
                                  withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "\(folder)/App.java"))
        try "gitdir: \(gitdir)\n".write(to: root.appending(path: "\(folder)/.git"),
                                        atomically: true, encoding: .utf8)
    }
    try files.createDirectory(at: root.appending(path: "backend/.git"),
                              withIntermediateDirectories: true)
    try Data().write(to: root.appending(path: "backend/App.java"))
    try checkout("worktrees/one", gitdir: root.appending(path: "backend/.git/worktrees/one").path)
    try checkout("worktrees/two", gitdir: "../../backend/.git/worktrees/two")
    try checkout("backend/lib", gitdir: "../.git/modules/lib")

    #expect(MentionController.indexFiles(under: root).map(\.path) == [
        "backend", "worktrees",
        "backend/App.java", "backend/lib",
        "backend/lib/App.java",
    ])
    #expect(MentionController.indexFiles(under: root.appending(path: "worktrees")).map(\.path)
            == ["one", "two", "one/App.java", "two/App.java"])
}

@Test func indexFilesCutTheDeepestEntriesWhenTheLimitIsReached() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let files = FileManager.default
    for folder in ["frontend", "backend"] {
        try files.createDirectory(at: root.appending(path: "\(folder)/src"),
                                  withIntermediateDirectories: true)
        for number in 0..<10 {
            try Data().write(to: root.appending(path: "\(folder)/src/f\(number).ts"))
        }
    }

    let candidates = MentionController.indexFiles(under: root, limit: 6)
    #expect(candidates.map(\.path) == [
        "backend", "frontend",
        "backend/src", "frontend/src",
        "backend/src/f0.ts", "backend/src/f1.ts",
    ])
}

@Test func acceptRewritesThePromptTail() {
    let chat = inertChat()
    let controller = MentionController()

    chat.prompt = "see @Sour"
    controller.accept(MentionCandidate(path: "Sources/App.swift", isDirectory: false), in: chat)
    #expect(chat.prompt == "see @Sources/App.swift ")

    chat.prompt = "open @D"
    controller.accept(MentionCandidate(path: "Docs", isDirectory: true), in: chat)
    #expect(chat.prompt == "open @Docs/")
}

@Test func indexFilesResolveSymlinkedRoots() throws {
    let scratch = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch,
                                            withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }

    let files = FileManager.default
    let target = scratch.appending(path: "target")
    try files.createDirectory(at: target.appending(path: "Sub"),
                              withIntermediateDirectories: true)
    try Data().write(to: target.appending(path: "a.swift"))
    try Data().write(to: target.appending(path: "Sub/b.swift"))

    let link = scratch.appending(path: "link")
    try files.createSymbolicLink(at: link, withDestinationURL: target)

    let candidates = MentionController.indexFiles(under: link)
    #expect(candidates.map(\.path) == ["Sub", "a.swift", "Sub/b.swift"])
}

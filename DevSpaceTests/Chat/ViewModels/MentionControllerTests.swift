import Testing
import Foundation
@testable import DevSpace

@Test func queryDetectsAnActiveMentionToken() {
    let controller = MentionController()
    #expect(controller.query(in: "veja @Sources/App") == "Sources/App")
    #expect(controller.query(in: "@") == "")
    #expect(controller.query(in: "email@exemplo.com") == nil)
    #expect(controller.query(in: "veja @um dois") == nil)
    #expect(controller.query(in: "sem menção") == nil)
}

@Test func matchesRankNameHitsAboveDeepPathHits() {
    let controller = MentionController()
    controller.fileIndex = [
        MentionCandidate(path: "chat/Notas.txt", isDirectory: false),
        MentionCandidate(path: "Docs/meu-chat.md", isDirectory: false),
        MentionCandidate(path: "Sources/Chat/ChatView.swift", isDirectory: false),
    ]
    let hits = controller.matches(prompt: "veja @chat")
    #expect(hits.map(\.path) == [
        "Sources/Chat/ChatView.swift",
        "Docs/meu-chat.md",
        "chat/Notas.txt",
    ])

    controller.dismissed = true
    #expect(controller.matches(prompt: "veja @chat").isEmpty)
}

@Test func matchesOfferTheIndexWhileTheQueryIsEmpty() {
    let controller = MentionController()
    controller.fileIndex = (0..<12).map {
        MentionCandidate(path: "arquivo-\($0).txt", isDirectory: false)
    }
    #expect(controller.matches(prompt: "@").count == 8)
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
    try Data().write(to: root.appending(path: ".escondido"))

    let candidates = MentionController.indexFiles(under: root)
    #expect(candidates.map(\.path) == ["Sub", "a.swift", "Sub/b.swift"])
    #expect(candidates.first?.isDirectory == true)
}

@Test func acceptRewritesThePromptTail() {
    let chat = inertChat()
    let controller = MentionController()

    chat.prompt = "veja @Sour"
    controller.accept(MentionCandidate(path: "Sources/App.swift", isDirectory: false), in: chat)
    #expect(chat.prompt == "veja @Sources/App.swift ")

    chat.prompt = "abra @D"
    controller.accept(MentionCandidate(path: "Docs", isDirectory: true), in: chat)
    #expect(chat.prompt == "abra @Docs/")
}

@Test func indexFilesResolveSymlinkedRoots() throws {
    let scratch = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch,
                                            withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }

    let files = FileManager.default
    let destino = scratch.appending(path: "destino")
    try files.createDirectory(at: destino.appending(path: "Sub"),
                              withIntermediateDirectories: true)
    try Data().write(to: destino.appending(path: "a.swift"))
    try Data().write(to: destino.appending(path: "Sub/b.swift"))

    let atalho = scratch.appending(path: "atalho")
    try files.createSymbolicLink(at: atalho, withDestinationURL: destino)

    let candidates = MentionController.indexFiles(under: atalho)
    #expect(candidates.map(\.path) == ["Sub", "a.swift", "Sub/b.swift"])
}

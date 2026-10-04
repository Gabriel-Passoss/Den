import Testing
import Foundation
import HarnessCore
@testable import Den

private let claude = HarnessID(rawValue: "test-claude")
private let openCode = HarnessID(rawValue: "test-opencode")

private func reply(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: Date(), kind: .assistantText(text), raw: .null)
}

private func question(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: Date(), kind: .userMessage(text: text, attachments: []), raw: .null)
}

@Test func aReopenedSessionRemembersWhichHarnessWroteEachReply() {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    let session = Session(title: "handoff", workingDirectory: root, segments: [
        Segment(harness: claude, harnessSessionID: "", model: "",
                entries: [question("oi"), reply("do Claude")]),
        Segment(harness: openCode, harnessSessionID: "", model: "",
                entries: [question("e agora"), reply("do OpenCode")]),
    ])
    let chat = ChatModel(store: scratchSessions(), restoring: session,
                         cache: scratchCache)

    let replies = chat.lines.filter { $0.role == .assistant }
    #expect(replies.map(\.harness) == [claude, openCode])
}

@Test func switchingHarnessKeepsTheEarlierRepliesWithTheirAuthor() async throws {
    let other = FakeHarness(id: "other", displayName: "Other")
    try await withLiveChat(alongside: [other]) { live in
        await live.chat.start()
        await live.session.emit(.entry(reply("antes da troca")))
        await settle { live.chat.lines.contains { $0.role == .assistant } }

        await live.chat.switchHarness(to: other.id)
        await other.session.emit(.entry(reply("depois da troca")))
        await settle { live.chat.lines.filter { $0.role == .assistant }.count == 2 }

        let replies = live.chat.lines.filter { $0.role == .assistant }
        #expect(replies.map(\.harness) == [live.harness.id, other.id])
    }
}

@Test func aReplyFromAnotherHarnessStartsItsOwnHeader() {
    let first = ChatLine(id: UUID(), role: .assistant, text: "a", timestamp: Date(), harness: claude)
    let second = ChatLine(id: UUID(), role: .assistant, text: "b", timestamp: Date(), harness: claude)
    let third = ChatLine(id: UUID(), role: .assistant, text: "c", timestamp: Date(), harness: openCode)

    let starts = ChatView.turnStarts(in: [.line(first), .line(second), .line(third)])

    #expect(starts == [first.id, third.id])
}

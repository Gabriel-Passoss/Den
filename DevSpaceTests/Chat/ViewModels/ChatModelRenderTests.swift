import Testing
import Foundation
import HarnessCore
@testable import DevSpace

private let moment = Date(timeIntervalSince1970: 1_700_000_000)

private func entry(_ kind: TranscriptEntry.Kind,
                   raw: JSONValue = .object([:])) -> TranscriptEntry {
    TranscriptEntry(timestamp: moment, kind: kind, raw: raw)
}

private func restored(_ entries: [TranscriptEntry]) -> ChatModel {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    let segment = Segment(harness: HarnessID(rawValue: "test-" + UUID().uuidString),
                          harnessSessionID: "", model: "", entries: entries)
    let session = Session(title: "restored", workingDirectory: root, segments: [segment])
    return ChatModel(store: FileTranscriptStore(root: root),
                     restoring: session, cache: scratchCache)
}

private func shape(_ chat: ChatModel) -> [String] {
    chat.lines.map { "\($0.role):\($0.text)" }
}

@Test func renderKeepsTheTranscriptInOrder() {
    let chat = restored([
        entry(.userMessage(text: "question", attachments: [])),
        entry(.assistantThinking("weighing it")),
        entry(.assistantText("answer")),
    ])
    #expect(shape(chat) == ["user:question", "thinking:weighing it", "assistant:answer"])
}

@Test func blankTextNeverBecomesALine() {
    let chat = restored([
        entry(.assistantText("   \n  ")),
        entry(.userMessage(text: "", attachments: [])),
        entry(.assistantThinking("")),
        entry(.assistantText("real")),
    ])
    #expect(shape(chat) == ["assistant:real"])
}

// MARK: - Tools

@Test func questionToolCallsAndTheirResultsStayHidden() {
    let chat = restored([
        entry(.toolCall(ToolCall(id: "q1", rawName: "AskUserQuestion",
                                 canonical: nil, input: .object([:])))),
        entry(.toolResult(ToolResult(callID: "q1", isError: false,
                                     content: .string("chose the first")))),
        entry(.toolCall(ToolCall(id: "t1", rawName: "Bash", canonical: .execute,
                                 input: .object(["command": .string("ls -la")])))),
        entry(.toolResult(ToolResult(callID: "t1", isError: false,
                                     content: .string("a b")))),
    ])
    #expect(shape(chat) == ["tool:ls -la", "toolResult:a b"])
}

@Test func aToolCallKeepsItsVerbAndShowsTheFileName() throws {
    let chat = restored([
        entry(.toolCall(ToolCall(id: "t1", rawName: "Read", canonical: .read,
                                 input: .object(["file_path": .string("/a/b/App.swift")])))),
    ])
    let line = try #require(chat.lines.first)
    #expect(line.text == "App.swift")
    #expect(line.verb == .read)
}

@Test func aFailedToolResultSaysSo() {
    let chat = restored([
        entry(.toolResult(ToolResult(callID: "t1", isError: true,
                                     content: .string("no such file")))),
    ])
    #expect(shape(chat) == ["toolResult:falhou: no such file"])
}

// MARK: - Digests

@Test func theAnswerAfterACompactionBecomesTheSummaryDigest() throws {
    let compaction = ContextCompaction(trigger: .automatic, tokensBefore: 155_000,
                                       tokensAfter: 8_000, duration: 75)
    let chat = restored([
        entry(.contextCompacted(compaction)),
        entry(.assistantText("here is what happened")),
        entry(.assistantText("and now the real answer")),
    ])
    #expect(shape(chat) == [
        "compaction:Conversa compactada · 155k → 8k tokens · 1min 15s",
        "digest:here is what happened",
        "assistant:and now the real answer",
    ])
    let digest = try #require(chat.lines.dropFirst().first)
    #expect(digest.title == Digest.summary)
    #expect(chat.contextTokens == 8_000)
}

@Test func aContinuedSessionMessageBecomesASummaryDigest() throws {
    let chat = restored([
        entry(.userMessage(text: "This session is being continued from an earlier one.",
                           attachments: [])),
    ])
    let line = try #require(chat.lines.first)
    #expect(shape(chat) == ["digest:This session is being continued from an earlier one."])
    #expect(line.title == Digest.summary)
}

@Test func localCommandOutputBecomesACommandDigest() throws {
    let text = "<command-name>/status</command-name>\n"
        + "<local-command-stdout>ok</local-command-stdout>"
    let chat = restored([entry(.userMessage(text: text, attachments: []))])

    let line = try #require(chat.lines.first)
    #expect(line.title == Digest.command)
    #expect(line.text == "/status\nok")
}

@Test func theCompactCommandNeverBecomesALine() {
    let chat = restored([
        entry(.userMessage(text: SlashCatalog.compactCommand, attachments: [])),
        entry(.assistantText("done")),
    ])
    #expect(shape(chat) == ["assistant:done"])
}

// MARK: - Notices

@Test func silentNoticesNeverBecomeLines() {
    let chat = restored([
        entry(.systemNotice(subtype: "init", text: "booting")),
        entry(.systemNotice(subtype: "rate_limit", text: "slow down")),
        entry(.systemNotice(subtype: "harness_switch", text: "swapped")),
        entry(.systemNotice(subtype: "warning", text: "the disk is full")),
    ])
    #expect(shape(chat) == ["notice:the disk is full"])
}

@Test func aRateLimitNoticeFlipsTheFlagWithoutShowing() {
    func chat(_ status: String) -> ChatModel {
        restored([entry(
            .systemNotice(subtype: "rate_limit", text: "slow down"),
            raw: .object(["rate_limit_info": .object(["status": .string(status)])]))])
    }
    #expect(chat("throttled").isRateLimited)
    #expect(chat("allowed").isRateLimited == false)
    #expect(chat("throttled").lines.isEmpty)
}

@Test func hookNoticesAreDroppedAndOtherUnknownsAreNot() {
    func system(_ subtype: String) -> JSONValue {
        .object(["type": .string("system"), "subtype": .string(subtype)])
    }
    let chat = restored([
        entry(.unrecognized(discriminator: "hook", payload: system("hook_started")),
              raw: system("hook_started")),
        entry(.unrecognized(discriminator: "hook", payload: system("hook_response")),
              raw: system("hook_response")),
        entry(.unrecognized(discriminator: "mystery", payload: system("mystery")),
              raw: system("mystery")),
    ])
    #expect(shape(chat) == ["unknown:subtype=mystery type=system"])
}

@Test func onlyADeniedPermissionLeavesAMessage() {
    let chat = restored([
        entry(.permissionDecision(requestID: "p1", .allow(updatedInput: nil))),
        entry(.permissionDecision(requestID: "p2",
                                  .deny(message: "denied by policy", interrupt: false))),
    ])
    #expect(shape(chat) == ["notice:denied by policy"])
}

// MARK: - Turn results

@Test func aFailedTurnAnnouncesItsStopReason() {
    let chat = restored([
        entry(.turnResult(TurnResult(usage: .zero, stopReason: "max_tokens",
                                     isError: true, contextTokens: 4_200))),
    ])
    #expect(shape(chat) == ["notice:o turno falhou no harness (max_tokens)"])
    #expect(chat.contextTokens == 4_200)
}

@Test func aCleanTurnSaysNothing() {
    let chat = restored([
        entry(.turnResult(TurnResult(usage: .zero, stopReason: "end_turn", isError: false))),
    ])
    #expect(chat.lines.isEmpty)
}

// MARK: - Attachments

private func withAttachedImage(_ body: (URL, Data) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let bytes = Data([0x89, 0x50, 0x4E, 0x47])
    let file = root.appending(path: "shot.png")
    try bytes.write(to: file)
    try body(file, bytes)
}

@Test func attachmentsRideAlongTheirUserLine() throws {
    try withAttachedImage { image, bytes in
        let chat = restored([entry(.userMessage(text: "look at this", attachments: [
            Attachment(kind: "image", path: image.path, raw: .object([:])),
            Attachment(kind: "file", path: "/tmp/a1b2.csv",
                       raw: .object(["name": .string("report.csv")])),
            Attachment(kind: "file", path: "/tmp/notes.txt", raw: .object([:])),
        ]))])

        let line = try #require(chat.lines.first)
        #expect(line.text == "look at this")
        #expect(line.images == [bytes])
        #expect(line.files == ["report.csv", "notes.txt"])
    }
}

@Test func anAttachmentOnlyMessageSurvivesTheBlankTextRule() throws {
    try withAttachedImage { image, _ in
        let chat = restored([entry(.userMessage(text: "", attachments: [
            Attachment(kind: "image", path: image.path, raw: .object([:])),
        ]))])

        let line = try #require(chat.lines.first)
        #expect(chat.lines.count == 1)
        #expect(line.text.isEmpty)
        #expect(line.images.count == 1)
    }
}

@Test func anUnreadableAttachmentIsSimplySkipped() throws {
    let chat = restored([entry(.userMessage(text: "look at this", attachments: [
        Attachment(kind: "image", path: "/nowhere/gone.png", raw: .object([:])),
    ]))])
    #expect(shape(chat) == ["user:look at this"])
    #expect(try #require(chat.lines.first).images.isEmpty)
}

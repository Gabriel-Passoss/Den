import Testing
import Foundation
@testable import DevSpace

private func line(_ role: ChatLine.Role, _ text: String) -> ChatLine {
    ChatLine(id: UUID(), role: role, text: text, timestamp: Date())
}

private func shape(_ blocks: [ChatBlock]) -> [String] {
    blocks.map { block in
        switch block {
        case .line(let line): "line:" + line.text
        case .collapsed(_, let lines): "run:" + lines.map(\.text).joined(separator: ",")
        }
    }
}

@Test func blocksGroupConsecutiveSteps() {
    let chat = inertChat()
    chat.lines = [
        line(.user, "question"),
        line(.thinking, "thinking"),
        line(.tool, "tool"),
        line(.toolResult, "output"),
        line(.assistant, "answer"),
    ]
    #expect(shape(chat.blocks) == [
        "line:question",
        "run:thinking,tool,output",
        "line:answer",
    ])
}

@Test func blocksFlushARunThatEndsTheTranscript() {
    let chat = inertChat()
    chat.lines = [line(.assistant, "answer"), line(.tool, "a"), line(.notice, "b")]
    #expect(shape(chat.blocks) == ["line:answer", "run:a,b"])
}

@Test func blocksKeepNonStepRolesApart() {
    let chat = inertChat()
    chat.lines = [
        line(.user, "u"),
        line(.assistant, "a"),
        line(.compaction, "c"),
        line(.digest, "d"),
    ]
    #expect(shape(chat.blocks) == ["line:u", "line:a", "line:c", "line:d"])
}

@Test func aRunBorrowsTheIdentityOfItsFirstLine() throws {
    let chat = inertChat()
    let first = line(.tool, "first")
    chat.lines = [first, line(.tool, "second")]

    let block = try #require(chat.blocks.first)
    #expect(block.id == first.id)
}

@Test func noLinesMeansNoBlocks() {
    let chat = inertChat()
    chat.lines = []
    #expect(chat.blocks.isEmpty)
}

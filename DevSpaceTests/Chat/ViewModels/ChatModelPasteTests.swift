import Testing
import Foundation
import HarnessCore
@testable import DevSpace

private let bigPaste = (1...8).map { "line \($0) " + String(repeating: "x", count: 40) }
    .joined(separator: "\n")

// MARK: - Capturing

@Test func aLongPasteBecomesAChipAndStaysOutOfThePrompt() {
    let chat = inertChat()
    chat.prompt = "explain"

    #expect(chat.capturePaste(bigPaste))

    #expect(chat.pendingPastes.map(\.text) == [bigPaste])
    #expect(chat.prompt == "explain")
}

@Test func aShortPasteIsLeftToTheField() {
    let chat = inertChat()
    #expect(chat.capturePaste("just a line") == false)
    #expect(chat.pendingPastes.isEmpty)
}

@Test func removePasteDropsTheChip() throws {
    let chat = inertChat()
    chat.capturePaste(bigPaste)
    let paste = try #require(chat.pendingPastes.first)

    chat.removePaste(paste.id)

    #expect(chat.pendingPastes.isEmpty)
}

// MARK: - Expanding back into the field

@Test func expandingIntoAnEmptyPromptPutsTheWholeTextThere() throws {
    let chat = inertChat()
    chat.capturePaste(bigPaste)
    let paste = try #require(chat.pendingPastes.first)

    chat.expandPaste(paste.id)

    #expect(chat.prompt == bigPaste)
    #expect(chat.pendingPastes.isEmpty)
}

@Test func expandingAfterTypedTextStartsOnANewLine() throws {
    let chat = inertChat()
    chat.prompt = "explain"
    chat.capturePaste(bigPaste)
    let paste = try #require(chat.pendingPastes.first)

    chat.expandPaste(paste.id)

    #expect(chat.prompt == "explain\n" + bigPaste)
}

// MARK: - Sending

@Test func pastesFollowTheTypedTextInTheTurn() async throws {
    try await withLiveChat { live in
        live.chat.capturePaste(bigPaste)
        await live.chat.send(text: "explain this")

        let expected = "explain this\n\n" + bigPaste
        #expect(await live.session.sent.map(\.text) == [expected])
        #expect(live.chat.lines.map(\.text) == [expected])
        #expect(live.chat.pendingPastes.isEmpty)
    }
}

@Test func aSlashCommandLeavesPastesForTheNextMessage() async throws {
    try await withLiveChat { live in
        live.chat.capturePaste(bigPaste)
        await live.chat.run(command: SlashCatalog.compactCommand)

        #expect(await live.session.sent.map(\.text) == [SlashCatalog.compactCommand])
        #expect(live.chat.compactingSince != nil)
        #expect(live.chat.pendingPastes.map(\.text) == [bigPaste])
    }
}

@Test func aPasteAloneIsEnoughToSend() async throws {
    try await withLiveChat { live in
        live.chat.capturePaste(bigPaste + "\n\n")
        await live.chat.send()

        #expect(await live.session.sent.map(\.text) == [bigPaste])
    }
}

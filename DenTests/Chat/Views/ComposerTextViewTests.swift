import Testing
import AppKit
import SwiftUI
@testable import Den

private let line = ComposerTextView.lineHeight

private func lines(_ height: CGFloat) -> Double {
    Double(height / line)
}

@Test func anEmptyPromptIsOneLineTall() {
    #expect(lines(ComposerTextView.height(of: "", width: 400)) == 1)
}

@Test func eachLineAddsItsHeight() {
    #expect(lines(ComposerTextView.height(of: "a\nb\nc", width: 400)) == 3)
}

@Test func aTrailingNewlineOpensTheNextLine() {
    #expect(lines(ComposerTextView.height(of: "a\n", width: 400)) == 2)
}

@Test func aLongLineWrapsAtTheFieldWidth() {
    let text = String(repeating: "word ", count: 40)
    #expect(lines(ComposerTextView.height(of: text, width: 120)) > 1)
}

@Test func pastTheLastVisibleLineTheFieldStopsGrowing() {
    let text = (1...20).map(String.init).joined(separator: "\n")
    #expect(lines(ComposerTextView.height(of: text, width: 400))
            == Double(ComposerTextView.maxLines))
}

@Test func aHugeTextIsCappedToo() {
    let text = String(repeating: "x", count: 200_000)
    #expect(lines(ComposerTextView.height(of: text, width: 400))
            == Double(ComposerTextView.maxLines))
}

@MainActor
@Test func pastingHandsTheTextToTheChatFirst() {
    let board = NSPasteboard(name: .init("DenTests-" + UUID().uuidString))
    defer { board.releaseGlobally() }
    board.clearContents()
    board.setString("pasted", forType: .string)

    let view = PromptTextView(usingTextLayoutManager: false)
    var offered: [String] = []
    view.onPaste = { offered.append($0); return true }

    #expect(view.capture(from: board))
    #expect(offered == ["pasted"])
}

@MainActor
@Test func aPasteTheChatDeclinesFallsThroughToTheField() {
    let board = NSPasteboard(name: .init("DenTests-" + UUID().uuidString))
    defer { board.releaseGlobally() }
    board.clearContents()
    board.setString("short", forType: .string)

    let view = PromptTextView(usingTextLayoutManager: false)
    view.onPaste = { _ in false }

    #expect(view.capture(from: board) == false)
}

@MainActor
@Test func aPasteboardWithoutTextIsNotCaptured() {
    let board = NSPasteboard(name: .init("DenTests-" + UUID().uuidString))
    defer { board.releaseGlobally() }
    board.clearContents()

    let view = PromptTextView(usingTextLayoutManager: false)
    view.onPaste = { _ in true }

    #expect(view.capture(from: board) == false)
}

@MainActor
private final class GhostLog {
    var accepted = 0
    var dismissed = 0
}

@MainActor
private func composer(ghost: String, log: GhostLog) -> ComposerTextView.Coordinator {
    ComposerTextView.Coordinator(ComposerTextView(
        text: .constant(""), focusRequested: .constant(false), accessibilityPlaceholder: "",
        ghost: ghost, onSubmit: {}, onPaste: { _ in false },
        onAcceptGhost: { log.accepted += 1 }, onDismissGhost: { log.dismissed += 1 }))
}

@MainActor
@Test func theRightArrowInAnEmptyFieldAcceptsTheGhost() {
    let log = GhostLog()
    let handled = composer(ghost: "Sim", log: log)
        .textView(PromptTextView(usingTextLayoutManager: false),
                  doCommandBy: #selector(NSResponder.moveRight(_:)))
    #expect(handled)
    #expect(log.accepted == 1)
}

@MainActor
@Test func theRightArrowMovesTheCursorOnceTheFieldHasText() {
    let log = GhostLog()
    let field = PromptTextView(usingTextLayoutManager: false)
    field.string = "n"
    let handled = composer(ghost: "Sim", log: log)
        .textView(field, doCommandBy: #selector(NSResponder.moveRight(_:)))
    #expect(!handled)
    #expect(log.accepted == 0)
}

@MainActor
@Test func theRightArrowWithoutAGhostMovesTheCursor() {
    let log = GhostLog()
    let handled = composer(ghost: "", log: log)
        .textView(PromptTextView(usingTextLayoutManager: false),
                  doCommandBy: #selector(NSResponder.moveRight(_:)))
    #expect(!handled)
    #expect(log.accepted == 0)
}

@MainActor
@Test func escapeDismissesTheGhost() {
    let log = GhostLog()
    let handled = composer(ghost: "Sim", log: log)
        .textView(PromptTextView(usingTextLayoutManager: false),
                  doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    #expect(handled)
    #expect(log.dismissed == 1)
}

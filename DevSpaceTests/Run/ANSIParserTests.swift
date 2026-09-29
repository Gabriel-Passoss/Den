import Testing
import Foundation
@testable import DevSpace

private let red = LogStyle(foreground: .palette(1))
private let green = LogStyle(foreground: .palette(2))

private func parse(_ chunks: [String]) -> [ANSIParser.Event] {
    parse(bytes: chunks.map { Array($0.utf8) })
}

private func parse(bytes chunks: [[UInt8]]) -> [ANSIParser.Event] {
    var parser = ANSIParser()
    return chunks.flatMap { parser.feed(Data($0)) } + parser.finish()
}

@Test func plainTextAndNewlinesBecomeEvents() {
    #expect(parse(["hello\nworld"]) == [.text("hello", plainStyle), .newline, .text("world", plainStyle)])
}

@Test func carriageReturnIsItsOwnEvent() {
    #expect(parse(["a\r\n"]) == [.text("a", plainStyle), .carriageReturn, .newline])
}

@Test func sgrColorsTheFollowingText() {
    #expect(parse(["\u{1B}[31mred\u{1B}[0m plainStyle"]) == [.text("red", red), .text(" plainStyle", plainStyle)])
}

@Test func anEmptySGRResets() {
    #expect(parse(["\u{1B}[31mA\u{1B}[mB"]) == [.text("A", red), .text("B", plainStyle)])
}

@Test func brightAndBackgroundColorsMapToThePalette() {
    let style = LogStyle(foreground: .palette(10), background: .palette(4))
    #expect(parse(["\u{1B}[92;44mx"]) == [.text("x", style)])
}

@Test func extendedColorsCover256AndTruecolor() {
    #expect(parse(["\u{1B}[38;5;208ma\u{1B}[48;2;1;2;3mb"]) == [
        .text("a", LogStyle(foreground: .palette(208))),
        .text("b", LogStyle(foreground: .palette(208), background: .rgb(1, 2, 3))),
    ])
}

@Test func defaultColorCodesClearOnlyTheirChannel() {
    #expect(parse(["\u{1B}[31;42mA\u{1B}[39mB"]) == [
        .text("A", LogStyle(foreground: .palette(1), background: .palette(2))),
        .text("B", LogStyle(background: .palette(2))),
    ])
}

@Test func attributesToggleOnAndOff() {
    #expect(parse(["\u{1B}[1;2;3;4;7mA\u{1B}[22;23;24;27mB"]) == [
        .text("A", LogStyle(bold: true, dim: true, italic: true, underline: true, inverse: true)),
        .text("B", plainStyle),
    ])
}

@Test func stylePersistsAcrossChunks() {
    #expect(parse(["\u{1B}[32m", "go"]) == [.text("go", green)])
}

@Test func anEscapeSplitAcrossChunksStillApplies() {
    #expect(parse(["\u{1B}[3", "1mred"]) == [.text("red", red)])
}

@Test func aMultibyteCharacterSplitAcrossChunksSurvives() {
    let bytes = Array("➜ ok".utf8)
    #expect(parse(bytes: [Array(bytes[0..<1]), Array(bytes[1...])]) == [.text("➜ ok", plainStyle)])
    #expect(parse(bytes: [Array(bytes[0..<2]), Array(bytes[2...])]) == [.text("➜ ok", plainStyle)])
}

@Test func eraseSequencesBecomeEvents() {
    #expect(parse(["a\u{1B}[Kb\u{1B}[0Kc\u{1B}[2Kd"]) == [
        .text("a", plainStyle), .eraseToEnd, .text("b", plainStyle), .eraseToEnd,
        .text("c", plainStyle), .eraseLine, .text("d", plainStyle),
    ])
}

@Test func cursorToColumnOneActsLikeACarriageReturn() {
    #expect(parse(["a\u{1B}[1Gb\u{1B}[Gc"]) == [
        .text("a", plainStyle), .carriageReturn, .text("b", plainStyle), .carriageReturn, .text("c", plainStyle),
    ])
}

@Test func otherControlSequencesAreDropped() {
    let noisy = "\u{1B}[?25l\u{1B}[2J\u{1B}[3Ahi\u{1B}]0;title\u{07}!"
        + "\u{1B}]8;;http://x\u{1B}\\link\u{1B}]8;;\u{1B}\\\u{1B}(B."
    #expect(parse([noisy]) == [.text("hi!link.", plainStyle)])
}

@Test func strayControlBytesAreDroppedButTabsStay() {
    #expect(parse(["a\u{07}\tb\u{08}"]) == [.text("a\tb", plainStyle)])
}

@Test func finishFlushesATruncatedCharacterAsAReplacement() {
    #expect(parse(bytes: [[0x61, 0xE2]]) == [.text("a", plainStyle), .text("\u{FFFD}", plainStyle)])
}

import Testing
import Foundation
@testable import DevSpace

private func lines(_ count: Int, width: Int) -> String {
    (0..<count).map { _ in String(repeating: "x", count: width) }.joined(separator: "\n")
}

// MARK: - Deciding what is long

@Test func fiveLinesWithTwoHundredCharactersIsLong() {
    let text = lines(5, width: 40)
    #expect(text.count >= 200)
    #expect(LongText.isLong(text))
}

@Test func fourLinesIsShortWhateverTheirWidth() {
    #expect(LongText.isLong(lines(4, width: 200)) == false)
}

@Test func manyShortLinesUnderTwoHundredCharactersIsShort() {
    let text = lines(10, width: 5)
    #expect(text.count < 200)
    #expect(LongText.isLong(text) == false)
}

@Test func aHugeSingleLineIsLongAnyway() {
    #expect(LongText.isLong(String(repeating: "x", count: 1_500)))
}

@Test func trailingBlankLinesDoNotCount() {
    let text = lines(4, width: 60) + "\n\n\n\n"
    #expect(LongText.lineCount(text) == 4)
    #expect(LongText.isLong(text) == false)
}

@Test func windowsLineEndingsCountAsLines() {
    let text = (0..<5).map { _ in String(repeating: "x", count: 50) }
        .joined(separator: "\r\n")
    #expect(LongText.lineCount(text) == 5)
    #expect(LongText.isLong(text))
}

@Test func emptyTextHasNoLines() {
    #expect(LongText.lineCount("") == 0)
    #expect(LongText.lineCount("\n\n") == 0)
}

// MARK: - Collapsed preview

@Test func previewKeepsOnlyTheFirstLines() {
    let text = "one\ntwo\nthree\nfour\nfive\nsix"
    #expect(LongText.preview(text, lines: 4) == "one\ntwo\nthree\nfour")
}

@Test func previewCutsAHugeLineAtTheLimit() {
    let text = String(repeating: "x", count: 5_000) + "\nsecond"
    #expect(LongText.preview(text, lines: 4, limit: 300) == String(repeating: "x", count: 300))
}

// MARK: - Labels

@Test func lineLabelAgreesInNumber() {
    #expect(LongText.lineLabel(1) == "1 linha")
    #expect(LongText.lineLabel(243) == "243 linhas")
}

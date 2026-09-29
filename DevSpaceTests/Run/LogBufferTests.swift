import Testing
import Foundation
@testable import DevSpace

private let red = LogStyle(foreground: .palette(1))

@Test func textThenNewlineOpensAFreshLine() {
    var buffer = LogBuffer(capacity: 100)
    let changes = buffer.apply([.text("a", plainStyle), .newline, .text("b", plainStyle)])
    #expect(buffer.lines == [plainLine("a"), plainLine("b")])
    #expect(changes == [.append([plainLine("a"), plainLine("b")])])
}

@Test func laterTextReplacesTheOpenLine() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("a", plainStyle)])
    #expect(buffer.apply([.text("b", plainStyle)]) == [.replaceLast(plainLine("ab"))])
}

@Test func carriageReturnMakesTheNextTextOverwrite() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("10%", plainStyle)])
    #expect(buffer.apply([.carriageReturn, .text("20%", plainStyle)]) == [.replaceLast(plainLine("20%"))])
    #expect(buffer.plainText == "20%")
}

@Test func crlfDoesNotEraseTheLine() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("a", plainStyle), .carriageReturn, .newline, .text("b", plainStyle)])
    #expect(buffer.plainText == "a\nb")
}

@Test func eraseToEndOnlyClearsAfterACarriageReturn() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("keep", plainStyle), .eraseToEnd])
    #expect(buffer.plainText == "keep")
    _ = buffer.apply([.carriageReturn, .eraseToEnd])
    #expect(buffer.plainText == "")
}

@Test func eraseLineClearsTheOpenLine() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("x", plainStyle), .eraseLine, .text("y", plainStyle)])
    #expect(buffer.plainText == "y")
}

@Test func adjacentTextWithTheSameStyleSharesASpan() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("a", plainStyle), .text("b", plainStyle), .text("c", red)])
    #expect(buffer.lines == [LogLine(spans: [LogSpan(text: "ab", style: plainStyle),
                                             LogSpan(text: "c", style: red)])])
}

@Test func newlineOnAnEmptyBufferKeepsTheBlankLine() {
    var buffer = LogBuffer(capacity: 100)
    #expect(buffer.apply([.newline]) == [.append([plainLine(""), plainLine("")])])
    #expect(buffer.plainText == "\n")
}

@Test func overflowDropsTheOldestLines() {
    var buffer = LogBuffer(capacity: 3)
    _ = buffer.apply([.text("1", plainStyle), .newline, .text("2", plainStyle), .newline])
    let changes = buffer.apply([.text("3", plainStyle), .newline, .text("4", plainStyle)])
    #expect(buffer.lines == [plainLine("2"), plainLine("3"), plainLine("4")])
    #expect(changes == [.dropFirst(1), .replaceLast(plainLine("3")), .append([plainLine("4")])])
}

@Test func aFloodLargerThanTheCapacityResetsTheView() {
    var buffer = LogBuffer(capacity: 2)
    _ = buffer.apply([.text("old", plainStyle)])
    let changes = buffer.apply([.newline, .text("a", plainStyle), .newline, .text("b", plainStyle),
                                .newline, .text("c", plainStyle)])
    #expect(buffer.lines == [plainLine("b"), plainLine("c")])
    #expect(changes == [.clear, .append([plainLine("b"), plainLine("c")])])
}

@Test func clearEmptiesTheBuffer() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("a", plainStyle), .carriageReturn])
    #expect(buffer.clear() == [.clear])
    #expect(buffer.lines.isEmpty)
    _ = buffer.apply([.text("b", plainStyle)])
    #expect(buffer.plainText == "b")
}

@Test func aDoubledCarriageReturnFromTheTerminalKeepsTheLine() {
    var parser = ANSIParser()
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply(parser.feed(Data("791\r\r\n792\r\n".utf8)))
    #expect(buffer.plainText == "791\n792\n")
}

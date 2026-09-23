import Testing
import Foundation
@testable import HarnessCore

@Test func deliversOneCompleteLine() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data(#"{"a":1}"# .utf8) + Data("\n".utf8))
    #expect(lines.count == 1)
    #expect(String(decoding: lines[0], as: UTF8.self) == #"{"a":1}"#)
}

@Test func holdsALineSplitAcrossChunks() throws {
    var framer = NDJSONFramer()
    #expect(try framer.push(Data(#"{"a":"# .utf8)).isEmpty)
    let lines = try framer.push(Data("1}\n".utf8))
    #expect(lines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#])
}

@Test func deliversSeveralLinesFromASingleChunk() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data("{\"a\":1}\n{\"b\":2}\n".utf8))
    #expect(lines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#, #"{"b":2}"#])
}

@Test func deliversManyLinesFromASingleChunk() throws {
    var framer = NDJSONFramer()
    let expected = (0..<300).map { #"{"n":\#($0)}"# }
    let chunk = expected.map { $0 + "\n" }.joined()
    let lines = try framer.push(Data(chunk.utf8))
    #expect(lines.map { String(decoding: $0, as: UTF8.self) } == expected)
}

@Test func combinesPreviousResidueWithSeveralLinesInTheSamePush() throws {
    var framer = NDJSONFramer()
    let firstLines = try framer.push(Data("{\"a\":1}\n{\"b\":2}\n{\"c\":".utf8))
    #expect(firstLines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#, #"{"b":2}"#])
    let secondLines = try framer.push(Data("3}\n".utf8))
    #expect(secondLines.map { String(decoding: $0, as: UTF8.self) } == [#"{"c":3}"#])
}

@Test func ignoresEmptyLines() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data("\n\n{\"a\":1}\n\n".utf8))
    #expect(lines.count == 1)
}

@Test func stripsTrailingCarriageReturn() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data("{\"a\":1}\r\n".utf8))
    #expect(String(decoding: lines[0], as: UTF8.self) == #"{"a":1}"#)
}

@Test func throwsWhenAnUnterminatedLineExceedsTheCeiling() {
    var framer = NDJSONFramer(limit: 16)
    #expect(throws: NDJSONFramer.FramingError.lineTooLong(limit: 16)) {
        _ = try framer.push(Data(String(repeating: "x", count: 32).utf8))
    }
}

@Test func throwsWhenATerminatedLineExceedsTheCeiling() {
    var framer = NDJSONFramer(limit: 16)
    #expect(throws: NDJSONFramer.FramingError.lineTooLong(limit: 16)) {
        _ = try framer.push(Data((String(repeating: "x", count: 20) + "\n").utf8))
    }
}

@Test func doesNotThrowWhenTheTotalExceedsButEachLineFits() throws {
    var framer = NDJSONFramer(limit: 16)
    let lines = try framer.push(Data("{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n".utf8))
    #expect(lines.count == 3)
}

@Test func aFramingThrowIsTerminal() throws {
    var porLinhaCompleta = NDJSONFramer(limit: 8)
    #expect(throws: NDJSONFramer.FramingError.self) {
        _ = try porLinhaCompleta.push(Data("ok\nxxxxxxxxxxxxxxxxxxxx\n".utf8))
    }

    #expect(throws: NDJSONFramer.FramingError.self) {
        _ = try porLinhaCompleta.push(Data("valida\n".utf8))
    }

    var porResidual = NDJSONFramer(limit: 8)
    #expect(throws: NDJSONFramer.FramingError.self) {
        _ = try porResidual.push(Data("ok\nxxxxxxxxxxxxxxxxxxxx".utf8))
    }
    #expect(throws: NDJSONFramer.FramingError.self) {
        _ = try porResidual.push(Data("valida\n".utf8))
    }
}

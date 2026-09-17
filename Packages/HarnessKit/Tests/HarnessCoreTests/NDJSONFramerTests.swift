import Testing
import Foundation
@testable import HarnessCore

@Test func entregaUmaLinhaCompleta() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data(#"{"a":1}"# .utf8) + Data("\n".utf8))
    #expect(lines.count == 1)
    #expect(String(decoding: lines[0], as: UTF8.self) == #"{"a":1}"#)
}

@Test func seguraLinhaPartidaEntreChunks() throws {
    var framer = NDJSONFramer()
    #expect(try framer.push(Data(#"{"a":"# .utf8)).isEmpty)
    let lines = try framer.push(Data("1}\n".utf8))
    #expect(lines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#])
}

@Test func entregaVariasLinhasDeUmChunkSo() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data("{\"a\":1}\n{\"b\":2}\n".utf8))
    #expect(lines.count == 2)
}

@Test func ignoraLinhasVazias() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data("\n\n{\"a\":1}\n\n".utf8))
    #expect(lines.count == 1)
}

@Test func removeCarriageReturnFinal() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data("{\"a\":1}\r\n".utf8))
    #expect(String(decoding: lines[0], as: UTF8.self) == #"{"a":1}"#)
}

@Test func estouraQuandoALinhaPassaDoTeto() {
    var framer = NDJSONFramer(limit: 16)
    #expect(throws: NDJSONFramer.FramingError.lineTooLong(limit: 16)) {
        _ = try framer.push(Data(String(repeating: "x", count: 32).utf8))
    }
}

@Test func naoEstouraQuandoOTotalPassaMasCadaLinhaCabe() throws {
    var framer = NDJSONFramer(limit: 16)
    let lines = try framer.push(Data("{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n".utf8))
    #expect(lines.count == 3)
}

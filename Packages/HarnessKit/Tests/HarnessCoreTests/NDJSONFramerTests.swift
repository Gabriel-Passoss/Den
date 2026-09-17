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
    #expect(lines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#, #"{"b":2}"#])
}

/// Alvo direto da otimização: um chunk com centenas de linhas precisa
/// preservar conteúdo e ordem exatos. Um erro de rebase de índice na
/// reescrita corromperia isso silenciosamente, sem crashar.
@Test func entregaMuitasLinhasDeUmChunkSo() throws {
    var framer = NDJSONFramer()
    let expected = (0..<300).map { #"{"n":\#($0)}"# }
    let chunk = expected.map { $0 + "\n" }.joined()
    let lines = try framer.push(Data(chunk.utf8))
    #expect(lines.map { String(decoding: $0, as: UTF8.self) } == expected)
}

/// Intercala uma linha parcial entre chunks com múltiplas linhas completas
/// no mesmo push, para cobrir o caso em que o resíduo de um push anterior
/// precisa se combinar corretamente com várias linhas extraídas de uma vez.
@Test func combinaResiduoDeChunkAnteriorComVariasLinhasNoMesmoPush() throws {
    var framer = NDJSONFramer()
    let firstLines = try framer.push(Data("{\"a\":1}\n{\"b\":2}\n{\"c\":".utf8))
    #expect(firstLines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#, #"{"b":2}"#])
    let secondLines = try framer.push(Data("3}\n".utf8))
    #expect(secondLines.map { String(decoding: $0, as: UTF8.self) } == [#"{"c":3}"#])
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

@Test func estouraQuandoLinhaTerminadaPassaDoTeto() {
    var framer = NDJSONFramer(limit: 16)
    #expect(throws: NDJSONFramer.FramingError.lineTooLong(limit: 16)) {
        _ = try framer.push(Data((String(repeating: "x", count: 20) + "\n").utf8))
    }
}

@Test func naoEstouraQuandoOTotalPassaMasCadaLinhaCabe() throws {
    var framer = NDJSONFramer(limit: 16)
    let lines = try framer.push(Data("{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n".utf8))
    #expect(lines.count == 3)
}

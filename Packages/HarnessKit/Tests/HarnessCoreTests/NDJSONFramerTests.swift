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

/// Alvo direto da otimização: um chunk com centenas de linhas precisa
/// preservar conteúdo e ordem exatos. Um erro de rebase de índice na
/// reescrita corromperia isso silenciosamente, sem crashar.
@Test func deliversManyLinesFromASingleChunk() throws {
    var framer = NDJSONFramer()
    let expected = (0..<300).map { #"{"n":\#($0)}"# }
    let chunk = expected.map { $0 + "\n" }.joined()
    let lines = try framer.push(Data(chunk.utf8))
    #expect(lines.map { String(decoding: $0, as: UTF8.self) } == expected)
}

/// Intercala uma linha parcial entre chunks com múltiplas linhas completas
/// no mesmo push, para cobrir o caso em que o resíduo de um push anterior
/// precisa se combinar corretamente com várias linhas extraídas de uma vez.
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

/// Fixa o contrato pós-throw que o doc comment de `push` declara. É um teste de
/// caracterização, não a prova de uma correção: ele passa igual contra o código
/// de antes desta mudança, porque o comportamento sempre foi este — o que
/// faltava era estar escrito. O valor dele é impedir que a doc apodreça: quem um
/// dia fizer o enquadrador se recuperar de um throw quebra este teste e é
/// obrigado a atualizar o contrato junto.
///
/// Cobre os dois pontos de throw, que se comportam de formas sutilmente
/// diferentes e mesmo assim são igualmente terminais: o de dentro do laço
/// (linha completa acima do teto, `removeSubrange` pulado) e o de depois dele
/// (residual parcial acima do teto, com o prefixo já consumido).
@Test func aFramingThrowIsTerminal() throws {
    var porLinhaCompleta = NDJSONFramer(limit: 8)
    #expect(throws: NDJSONFramer.FramingError.self) {
        _ = try porLinhaCompleta.push(Data("ok\nxxxxxxxxxxxxxxxxxxxx\n".utf8))
    }
    // "ok" tinha ficado pronta antes do throw e não chegou ao chamador; e um
    // chunk perfeitamente válido depois disso lança do mesmo jeito.
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

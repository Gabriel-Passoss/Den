import Testing
import Foundation
@testable import HarnessCore

private func roundTrip(_ json: String) throws -> String {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    let encoder = JSONEncoder()
    // .withoutEscapingSlashes: sem isso, Foundation's JSONEncoder escapa "/"
    // como "\/" por padrão, e roundTripsTheRealPermissionRequestInput (cujo
    // fixture tem um file_path de verdade, com barras) falharia comparando a
    // string bruta mesmo com a implementação correta — efeito colateral do
    // encoder, não do JSONValue. Não remova sem checar esse teste.
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

@Test func decodesEachScalarKind() throws {
    let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
    {"n":null,"b":true,"i":42,"d":1.5,"s":"oi"}
    """#.utf8))
    #expect(v == .object([
        "n": .null, "b": .bool(true), "i": .int(42),
        "d": .double(1.5), "s": .string("oi"),
    ]))
}

@Test func preservesIntegersAcrossARoundTrip() throws {
    // O caso que motiva o tipo: um inteiro não pode virar ponto flutuante,
    // porque o input da ferramenta é devolvido ao CLI ao permitir a chamada.
    #expect(try roundTrip(#"{"count":1}"#) == #"{"count":1}"#)
    #expect(try roundTrip(#"{"count":0}"#) == #"{"count":0}"#)
    #expect(try roundTrip(#"{"count":-7}"#) == #"{"count":-7}"#)
}

@Test func preservesIntegersBeyondDoublePrecision() throws {
    // Double representa inteiros exatamente só até 2^53. 9007199254740993
    // (2^53 + 1) é o menor inteiro que um Double não consegue representar —
    // se o decoder tentasse Double antes de Int, este valor arredondaria
    // silenciosamente para 9007199254740992 no round-trip.
    #expect(try roundTrip(#"{"id":9007199254740993}"#) == #"{"id":9007199254740993}"#)
}

@Test func preservesFractionalNumbers() throws {
    #expect(try roundTrip(#"{"ratio":1.5}"#) == #"{"ratio":1.5}"#)
}

@Test func handlesNestingAndArrays() throws {
    let json = #"{"a":[1,{"b":["x",null,false]}]}"#
    #expect(try roundTrip(json) == json)
}

@Test func roundTripsTheRealPermissionRequestInput() throws {
    // O input exato que o CLI mandou no fixture gravado.
    let json = #"{"content":"ok","file_path":"/private/tmp/probe-scratch/prova.txt"}"#
    #expect(try roundTrip(json) == json)
}

@Test func subscriptReadsObjectMembers() throws {
    let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":{"b":"c"}}"#.utf8))
    #expect(v["a"]?["b"] == .string("c"))
    #expect(v["ausente"] == nil)
}

@Test func stringAccessorReturnsNilForOtherKinds() throws {
    #expect(JSONValue.string("oi").stringValue == "oi")
    #expect(JSONValue.int(1).stringValue == nil)
}

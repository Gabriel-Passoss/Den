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
    // Round-trip de inteiros pequenos. ISTO PASSA COM QUALQUER ORDEM entre
    // Int e Double no decoder — este JSONEncoder imprime Double(1.0) como
    // "1", igual a Int(1), então este teste não prova a distinção dos casos.
    // Quem prova é preservesIntegersBeyondDoublePrecision, com um valor que
    // só Int representa exatamente.
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

@Test func wholeNumberDoublesDecodeAsInt() throws {
    // Comportamento real do tipo, documentado em vez de escondido: um número
    // JSON sem resto fracionário sempre decodifica como .int, não importa
    // como foi escrito no fixture — decode(Int.self) aceita o token "1.0"
    // porque ele não tem parte fracionária. {"opacity":1.0} vira .int(1) e
    // reencoda como {"opacity":1}: o ponto decimal se perde. O mesmo vale
    // para -2.0 e 0.0. Isso é aceitável porque o consumidor real (Claude
    // Code, um processo Node) trata 1 e 1.0 como o mesmo Number em
    // JavaScript — a diferença é inobservável do outro lado do pipe.
    let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"opacity":1.0}"#.utf8))
    #expect(v == .object(["opacity": .int(1)]))
    #expect(try roundTrip(#"{"opacity":1.0}"#) == #"{"opacity":1}"#)
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

@Test func theNumericAccessorsBridgeTheIntDoubleAmbiguity() {
    // Um consumidor JSON cuja representação numérica não distingue inteiro de
    // ponto flutuante escreve `0` onde o esquema diz "número". Ler um custo
    // como `.int(0)` e devolver `nil` de `doubleValue` perderia o valor.
    #expect(JSONValue.int(7).intValue == 7)
    #expect(JSONValue.int(7).doubleValue == 7.0)
    #expect(JSONValue.double(7.0).intValue == 7)
    #expect(JSONValue.double(7.5).intValue == nil)
    #expect(JSONValue.double(0.0227).doubleValue == 0.0227)
    #expect(JSONValue.bool(true).boolValue == true)
    #expect(JSONValue.string("7").intValue == nil)
    #expect(JSONValue.string("true").boolValue == nil)
    #expect(JSONValue.null.doubleValue == nil)
}

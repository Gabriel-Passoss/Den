import Testing
import Foundation
@testable import HarnessCore

private func roundTrip(_ json: String) throws -> String {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    let encoder = JSONEncoder()

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

    #expect(try roundTrip(#"{"count":1}"#) == #"{"count":1}"#)
    #expect(try roundTrip(#"{"count":0}"#) == #"{"count":0}"#)
    #expect(try roundTrip(#"{"count":-7}"#) == #"{"count":-7}"#)
}

@Test func preservesIntegersBeyondDoublePrecision() throws {

    #expect(try roundTrip(#"{"id":9007199254740993}"#) == #"{"id":9007199254740993}"#)
}

@Test func preservesFractionalNumbers() throws {
    #expect(try roundTrip(#"{"ratio":1.5}"#) == #"{"ratio":1.5}"#)
}

@Test func wholeNumberDoublesDecodeAsInt() throws {

    let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"opacity":1.0}"#.utf8))
    #expect(v == .object(["opacity": .int(1)]))
    #expect(try roundTrip(#"{"opacity":1.0}"#) == #"{"opacity":1}"#)
}

@Test func handlesNestingAndArrays() throws {
    let json = #"{"a":[1,{"b":["x",null,false]}]}"#
    #expect(try roundTrip(json) == json)
}

@Test func roundTripsTheRealPermissionRequestInput() throws {

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

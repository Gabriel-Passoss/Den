import Testing
import Foundation
@testable import HarnessCore

@Test func theCanonicalVocabularyIsExactlySixVerbs() {
    #expect(Set(CanonicalTool.allCases.map(\.rawValue))
            == ["read", "write", "edit", "execute", "search", "fetch"])
}

@Test func aHarnessIDIsAnOpenSetSoANewAdapterNeedsNoChangeHere() {

    let a = HarnessID(rawValue: "harness-a")
    let b = HarnessID(rawValue: "harness-b")
    #expect(a.rawValue == "harness-a")
    #expect(a != b)
    #expect(a == HarnessID(rawValue: "harness-a"))
}

@Test func aToolCallCarriesTheHarnessOwnNameEvenWhenItMapsCleanly() {
    let call = ToolCall(id: "toolu_1", rawName: "Edit", canonical: .edit,
                        input: .object(["file_path": .string("/tmp/a")]))
    #expect(call.canonical == .edit)
    #expect(call.rawName == "Edit")
    #expect(call.input["file_path"] == .string("/tmp/a"))
}

@Test func anUnmappableToolIsCarriedWithoutACanonicalVerb() {

    let call = ToolCall(id: "toolu_2", rawName: "AlgoQueNaoConhecemos",
                        canonical: nil, input: .object([:]))
    #expect(call.canonical == nil)
    #expect(call.rawName == "AlgoQueNaoConhecemos")
}

@Test func aToolResultPointsBackAtItsCall() {
    let result = ToolResult(callID: "toolu_1", isError: false, content: .string("ok"))
    #expect(result.callID == "toolu_1")
    #expect(!result.isError)
}

@Test func toolTypesSurviveACodableRoundTrip() throws {
    let call = ToolCall(id: "t", rawName: "Bash", canonical: .execute,
                        input: .object(["command": .string("ls"), "n": .int(1)]))
    let data = try JSONEncoder().encode(call)
    #expect(try JSONDecoder().decode(ToolCall.self, from: data) == call)

    let unmapped = ToolCall(id: "u", rawName: "X", canonical: nil, input: .null)
    let unmappedData = try JSONEncoder().encode(unmapped)
    #expect(try JSONDecoder().decode(ToolCall.self, from: unmappedData) == unmapped)
}

@Test func anUnknownCanonicalVerbDegradesToNilInsteadOfFailingTheWholeDecode() throws {

    let json = #"{"id":"x","rawName":"Delete","canonical":"delete","input":{}}"#
    let call = try JSONDecoder().decode(ToolCall.self, from: Data(json.utf8))
    #expect(call.id == "x")
    #expect(call.rawName == "Delete")
    #expect(call.canonical == nil)
}

@Test func aKnownCanonicalVerbStillDecodesToItselfThroughTheCustomDecoder() throws {

    let json = #"{"id":"t","rawName":"Edit","canonical":"edit","input":{}}"#
    let call = try JSONDecoder().decode(ToolCall.self, from: Data(json.utf8))
    #expect(call.canonical == .edit)
}

@Test func aNilCanonicalRoundTripsCoherentlyThroughJSON() throws {
    let call = ToolCall(id: "u", rawName: "X", canonical: nil, input: .null)
    let data = try JSONEncoder().encode(call)

    let jsonString = String(decoding: data, as: UTF8.self)
    #expect(!jsonString.contains("canonical"))

    let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
    #expect(decoded.canonical == nil)
    #expect(decoded == call)
}

import Testing
import Foundation
@testable import HarnessCore

@Test func theCanonicalVocabularyIsExactlySixVerbs() {
    #expect(Set(CanonicalTool.allCases.map(\.rawValue))
            == ["read", "write", "edit", "execute", "search", "fetch"])
}

@Test func aHarnessIDIsAnOpenSetSoANewAdapterNeedsNoChangeHere() {
    // Um enum fechado obrigaria a editar HarnessCore para cada harness novo.
    let codex = HarnessID(rawValue: "codex")
    #expect(codex.rawValue == "codex")
    #expect(codex != HarnessID.claudeCode)
    #expect(HarnessID.claudeCode.rawValue == "claude-code")
}

@Test func aToolCallCarriesTheHarnessOwnNameEvenWhenItMapsCleanly() throws {
    let call = ToolCall(id: "toolu_1", rawName: "Edit", canonical: .edit,
                        input: .object(["file_path": .string("/tmp/a")]))
    #expect(call.canonical == .edit)
    #expect(call.rawName == "Edit")
    #expect(call.input["file_path"] == .string("/tmp/a"))
}

@Test func anUnmappableToolIsCarriedWithoutACanonicalVerb() throws {
    // nil é honesto. Inventar um verbo seria degradar para uma mentira.
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

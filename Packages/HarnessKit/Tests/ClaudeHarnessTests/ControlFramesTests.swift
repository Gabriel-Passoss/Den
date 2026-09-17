import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private func fixtureLines(_ name: String) throws -> [Data] {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "ndjson"))
    return try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n").filter { !$0.isEmpty }.map { Data($0.utf8) }
}

@Test func classifiesAConversationLineAsConversation() throws {
    let line = Data(#"{"type":"assistant","message":{"role":"assistant"}}"#.utf8)
    #expect(ControlFrame.classify(line) == .conversation)
}

@Test func classifiesAControlResponseByItsRequestID() throws {
    let line = Data(#"""
    {"type":"control_response","response":{"subtype":"success","request_id":"init-1","response":{"commands":[]}}}
    """#.utf8)
    guard case .response(let id, let result) = ControlFrame.classify(line) else {
        Issue.record("esperava .response"); return
    }
    #expect(id == "init-1")
    #expect(result.isSuccess)
}

@Test func classifiesAnErrorResponse() throws {
    let line = Data(#"""
    {"type":"control_response","response":{"subtype":"error","request_id":"x","error":"deu ruim"}}
    """#.utf8)
    guard case .response(_, let result) = ControlFrame.classify(line) else {
        Issue.record("esperava .response"); return
    }
    #expect(!result.isSuccess)
    #expect(result.errorMessage == "deu ruim")
}

@Test func parsesTheRealPermissionRequestFromTheFixture() throws {
    let frames = try fixtureLines("permission-request").map(ControlFrame.classify)
    let requests = frames.compactMap { frame -> PermissionRequest? in
        if case .permissionRequest(let r) = frame { return r }
        return nil
    }
    #expect(requests.count == 1)
    let r = try #require(requests.first)
    #expect(r.toolName == "Write")
    #expect(r.displayName == "Write")
    #expect(r.description == "prova.txt")
    #expect(r.toolUseID == "toolu_01MnTatUeYfz3cMti4VXq4z8")
    #expect(r.input["content"] == .string("ok"))
    #expect(r.suggestions.count == 1)
    #expect(r.suggestions.first?.type == "setMode")
    #expect(r.suggestions.first?.mode == "acceptEdits")
    #expect(r.suggestions.first?.destination == "session")
    #expect(!r.id.isEmpty)
}

@Test func anUnknownControlSubtypeIsPreservedNotRejected() throws {
    // Spec §5.4: um subtipo desconhecido nunca é erro — degrada, não quebra.
    let line = Data(#"""
    {"type":"control_request","request_id":"z","request":{"subtype":"coisa_nova","x":1}}
    """#.utf8)
    guard case .unknownControl(let id, let raw) = ControlFrame.classify(line) else {
        Issue.record("esperava .unknownControl"); return
    }
    #expect(id == "z")
    #expect(raw["request"]?["subtype"] == .string("coisa_nova"))
}

@Test func malformedJSONIsTreatedAsConversationNotAsAFailure() throws {
    // O mapper da Etapa 4 decide o que fazer; o canal de controle não julga.
    #expect(ControlFrame.classify(Data("nao sou json".utf8)) == .conversation)
}

@Test func encodesAnAllowDecisionInTheShapeTheCLIAccepts() throws {
    let decision = PermissionDecision.allow(updatedInput: .object(["a": .int(1)]))
    let data = try decision.responseData(requestID: "req-9")
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["type"] == .string("control_response"))
    #expect(decoded["response"]?["subtype"] == .string("success"))
    #expect(decoded["response"]?["request_id"] == .string("req-9"))
    #expect(decoded["response"]?["response"]?["behavior"] == .string("allow"))
    #expect(decoded["response"]?["response"]?["updatedInput"]?["a"] == .int(1))
}

@Test func encodesADenyDecision() throws {
    let decision = PermissionDecision.deny(message: "não", interrupt: false)
    let data = try decision.responseData(requestID: "req-9")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["response"]?["response"]?["behavior"] == .string("deny"))
    #expect(decoded["response"]?["response"]?["message"] == .string("não"))
    #expect(decoded["response"]?["response"]?["interrupt"] == .bool(false))
}

@Test func encodesAnOutboundRequestWithItsID() throws {
    let request = OutboundControlRequest.interrupt
    let data = try request.requestData(requestID: "out-1")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["type"] == .string("control_request"))
    #expect(decoded["request_id"] == .string("out-1"))
    #expect(decoded["request"]?["subtype"] == .string("interrupt"))
}

@Test func encodesSetPermissionModeWithItsMode() throws {
    let data = try OutboundControlRequest.setPermissionMode("acceptEdits")
        .requestData(requestID: "out-2")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["request"]?["subtype"] == .string("set_permission_mode"))
    #expect(decoded["request"]?["mode"] == .string("acceptEdits"))
}

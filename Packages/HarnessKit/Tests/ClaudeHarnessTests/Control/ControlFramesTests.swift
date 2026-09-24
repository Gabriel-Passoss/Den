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

@Test func classifiesAResponseWithAnUnrecognizedSubtypeAsFailure() throws {

    let line = Data(#"""
    {"type":"control_response","response":{"subtype":"cancelled","request_id":"r1"}}
    """#.utf8)
    guard case .response(let id, let result) = ControlFrame.classify(line) else {
        Issue.record("esperava .response"); return
    }
    #expect(id == "r1")
    #expect(!result.isSuccess)
    #expect(result.errorMessage == "resposta com subtipo desconhecido: cancelled")
}

@Test func classifiesAResponseWithAMissingSubtypeAsFailure() throws {
    let line = Data(#"""
    {"type":"control_response","response":{"request_id":"r2"}}
    """#.utf8)
    guard case .response(let id, let result) = ControlFrame.classify(line) else {
        Issue.record("esperava .response"); return
    }
    #expect(id == "r2")
    #expect(!result.isSuccess)
    #expect(result.errorMessage == "resposta com subtipo desconhecido: ausente")
}

@Test func aControlResponseMissingItsResponseBodyIsPreservedNotDiscarded() throws {

    let line = Data(#"""
    {"type":"control_response","oops":true}
    """#.utf8)
    guard case .unknownControl(let raw) = ControlFrame.classify(line) else {
        Issue.record("esperava .unknownControl"); return
    }
    #expect(raw["oops"] == .bool(true))
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

@Test func aPermissionSuggestionMissingItsTypeIsPreservedNotDropped() throws {

    let line = Data(#"""
    {"type":"control_request","request_id":"a1","request":{"subtype":"can_use_tool","tool_name":"Bash","permission_suggestions":[{"mode":"acceptEdits"}]}}
    """#.utf8)
    guard case .permissionRequest(let r) = ControlFrame.classify(line) else {
        Issue.record("esperava .permissionRequest"); return
    }
    #expect(r.suggestions.count == 1)
    #expect(r.suggestions.first?.type == nil)
    #expect(r.suggestions.first?.mode == "acceptEdits")
    #expect(r.suggestions.first?.raw["mode"] == .string("acceptEdits"))
}

@Test func anUnknownControlSubtypeIsPreservedNotRejected() throws {

    let line = Data(#"""
    {"type":"control_request","request_id":"z","request":{"subtype":"coisa_nova","x":1}}
    """#.utf8)
    guard case .unansweredControlRequest(let id, let raw) = ControlFrame.classify(line) else {
        Issue.record("esperava .unansweredControlRequest"); return
    }
    #expect(id == "z")
    #expect(raw["request"]?["subtype"] == .string("coisa_nova"))
}

@Test func aPermissionRequestWithoutARequestIDIsNotOfferedToTheUI() throws {
    let line = Data(#"""
    {"type":"control_request","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{}}}
    """#.utf8)
    guard case .unknownControl(let raw) = ControlFrame.classify(line) else {
        Issue.record("esperava .unknownControl"); return
    }
    #expect(raw["request"]?["tool_name"] == .string("Bash"))
}

@Test func anEmptyRequestIDIsTreatedAsNoRequestIDAtAll() throws {
    let line = Data(#"""
    {"type":"control_request","request_id":"","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{}}}
    """#.utf8)
    guard case .unknownControl = ControlFrame.classify(line) else {
        Issue.record("esperava .unknownControl"); return
    }
}

@Test func theAutomaticRefusalUsesTheProtocolsOwnErrorEnvelope() throws {
    let data = try ControlErrorResponse(requestID: "r-7", message: "did not understand").data()
    guard case .response(let id, let result) = ControlFrame.classify(data) else {
        Issue.record("esperava .response"); return
    }
    #expect(id == "r-7")
    #expect(result.errorMessage == "did not understand")
}

@Test func malformedJSONIsTreatedAsConversationNotAsAFailure() throws {

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
    let decision = PermissionDecision.deny(message: "no", interrupt: false)
    let data = try decision.responseData(requestID: "req-9")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["response"]?["response"]?["behavior"] == .string("deny"))
    #expect(decoded["response"]?["response"]?["message"] == .string("no"))
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
    let data = try OutboundControlRequest.setPermissionMode(.acceptEdits)
        .requestData(requestID: "out-2")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["request"]?["subtype"] == .string("set_permission_mode"))
    #expect(decoded["request"]?["mode"] == .string("acceptEdits"))
}

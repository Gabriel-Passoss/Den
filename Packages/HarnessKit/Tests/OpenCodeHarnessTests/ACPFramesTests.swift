import Testing
import Foundation
import HarnessCore
@testable import OpenCodeHarness

private func classify(_ text: String) -> ACPFrame {
    ACPFrame.classify(Data(text.utf8))
}

@Test func aFrameWithMethodAndIDIsARequestFromTheAgent() {
    let frame = classify(#"{"jsonrpc":"2.0","id":0,"method":"session/request_permission","params":{"a":1}}"#)
    guard case .request(let id, let method, let params) = frame else {
        Issue.record("esperava request, veio \(frame)"); return
    }
    #expect(id == .int(0))
    #expect(method == "session/request_permission")
    #expect(params["a"]?.intValue == 1)
}

@Test func aFrameWithMethodAndNoIDIsANotification() {
    let frame = classify(#"{"jsonrpc":"2.0","method":"session/update","params":{"b":2}}"#)
    guard case .notification(let method, let params) = frame else {
        Issue.record("esperava notificação, veio \(frame)"); return
    }
    #expect(method == "session/update")
    #expect(params["b"]?.intValue == 2)
}

@Test func aResultFrameCarriesItsPayload() {
    let frame = classify(#"{"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}"#)
    #expect(frame == .response(id: 3, .success(.object(["stopReason": .string("end_turn")]))))
}

@Test func anErrorFrameCarriesCodeAndMessage() {
    let frame = classify(#"{"jsonrpc":"2.0","id":6,"error":{"code":-32601,"message":"Method not found"}}"#)
    #expect(frame == .response(id: 6, .failure(code: -32601, message: "Method not found")))
}

@Test func aLineThatIsNotJSONDegradesInsteadOfThrowing() {
    guard case .malformed = classify("isto não é json") else {
        Issue.record("uma linha ilegível precisa degradar, nunca derrubar a sessão"); return
    }
}

@Test func aNotificationOnTheWireCarriesNoID() throws {

    let data = try ACPWire.notification(method: "session/cancel",
                                        params: .object(["sessionId": .string("ses_1")]))
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

    #expect(decoded["id"] == nil)
    #expect(decoded["jsonrpc"]?.stringValue == "2.0")
    #expect(decoded["method"]?.stringValue == "session/cancel")
}

@Test func aRequestOnTheWireCarriesItsID() throws {
    let data = try ACPWire.request(id: 7, method: "session/prompt", params: .object([:]))
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["id"]?.intValue == 7)
}

@Test func aResponseEchoesTheIDShapeItWasGiven() throws {

    let data = try ACPWire.response(id: .int(0), result: .object(["ok": .bool(true)]))
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["id"] == .int(0))
    #expect(decoded["result"]?["ok"]?.boolValue == true)
}

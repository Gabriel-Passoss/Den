import Testing
import Foundation
import HarnessCore
@testable import OpenCodeHarness

private func recordedPermissionParams() throws -> JSONValue {
    let url = try #require(Bundle.module.url(
        forResource: "Fixtures/turn-with-permission", withExtension: "ndjson"))
    for line in try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n") where !line.isEmpty {
        if case .request(_, let method, let params) = ACPFrame.classify(Data(line.utf8)),
           method == "session/request_permission" {
            return params
        }
    }
    Issue.record("the fixture lost the permission request")
    return .null
}

@Test func theRecordedPermissionBecomesARequestTheCockpitCanDraw() throws {
    let request = OpenCodePermission.request(id: "opencode-1", params: try recordedPermissionParams())

    #expect(request.id == "opencode-1")
    #expect(request.toolName == "echo oi")
    #expect(request.input["command"]?.stringValue == "echo oi")
    #expect(request.toolUseID == "f79e8282-34ad-472f-8306-ad14480a0ad4")
}

@Test func theThreeOfferedOptionsSurviveWithTheirKinds() throws {
    let request = OpenCodePermission.request(id: "r", params: try recordedPermissionParams())

    #expect(request.options.map(\.id) == ["once", "always", "reject"])
    #expect(request.options.map(\.kind) == [.allowOnce, .allowAlways, .rejectOnce])

    #expect(request.options.map(\.label) == ["Permitir", "Sempre permitir", "Negar"])
}

@Test func choosingAnOptionSendsThatOptionBack() throws {
    let offered = OpenCodePermission.request(id: "r", params: try recordedPermissionParams()).options

    let outcome = OpenCodePermission.outcome(for: .option(id: "always"), offered: offered)
    #expect(outcome["outcome"]?.stringValue == "selected")
    #expect(outcome["optionId"]?.stringValue == "always")
}

@Test func abinaryDecisionPicksTheMatchingOfferedOption() throws {
    let offered = OpenCodePermission.request(id: "r", params: try recordedPermissionParams()).options

    #expect(OpenCodePermission.outcome(for: .allow(updatedInput: nil), offered: offered)["optionId"]?
        .stringValue == "once")
    #expect(OpenCodePermission.outcome(
        for: .deny(message: "no", interrupt: false), offered: offered)["optionId"]?
        .stringValue == "reject")
}

@Test func aDecisionWithNothingToPickIsReportedAsCancelled() {
    let outcome = OpenCodePermission.outcome(for: .allow(updatedInput: nil), offered: [])
    #expect(outcome["outcome"]?.stringValue == "cancelled")
    #expect(outcome["optionId"] == nil)
}

@Test func anOptionKindThisVersionDoesNotKnowKeepsItsOwnName() {
    let params = JSONValue.object([
        "toolCall": .object(["title": .string("bash")]),
        "options": .array([.object([
            "optionId": .string("hour"),
            "kind": .string("allow_for_an_hour"),
            "name": .string("por uma hora"),
        ])]),
    ])
    let request = OpenCodePermission.request(id: "r", params: params)

    #expect(request.options.first?.kind == .other)

    #expect(request.options.first?.label == "Por uma hora")
}

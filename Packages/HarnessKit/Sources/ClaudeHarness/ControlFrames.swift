import Foundation
import HarnessCore

public enum ControlFrame: Equatable, Sendable {

    case conversation

    case permissionRequest(PermissionRequest)

    case response(requestID: String, ControlResponseResult)

    case unansweredControlRequest(requestID: String, raw: JSONValue)

    case unknownControl(raw: JSONValue)

    public static func classify(_ line: Data) -> ControlFrame {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line),
              let type = value["type"]?.stringValue
        else { return .conversation }

        switch type {
        case "control_request":

            guard let id = value["request_id"]?.stringValue, !id.isEmpty else {
                return .unknownControl(raw: value)
            }
            guard let request = value["request"],
                  request["subtype"]?.stringValue == "can_use_tool",
                  let parsed = PermissionRequest(id: id, request: request)
            else { return .unansweredControlRequest(requestID: id, raw: value) }
            return .permissionRequest(parsed)

        case "control_response":

            guard let response = value["response"] else {
                return .unknownControl(raw: value)
            }
            let id = response["request_id"]?.stringValue ?? ""
            let subtype = response["subtype"]?.stringValue
            switch subtype {
            case "success":
                return .response(requestID: id, .success(response["response"] ?? .null))
            case "error":
                return .response(requestID: id,
                                 .failure(response["error"]?.stringValue ?? "erro sem mensagem"))
            default:

                return .response(requestID: id,
                                 .failure("resposta com subtipo desconhecido: \(subtype ?? "ausente")"))
            }

        default:
            return .conversation
        }
    }
}

struct ControlErrorResponse: Equatable {
    let requestID: String
    let message: String

    func data() throws -> Data {
        try JSONEncoder().encode(JSONValue.object([
            "type": .string("control_response"),
            "response": .object([
                "subtype": .string("error"),
                "request_id": .string(requestID),
                "error": .string(message),
            ]),
        ]))
    }
}

public enum ControlResponseResult: Equatable, Sendable {
    case success(JSONValue)
    case failure(String)

    public var isSuccess: Bool { if case .success = self { return true }; return false }
    public var errorMessage: String? { if case .failure(let m) = self { return m }; return nil }
    public var payload: JSONValue? { if case .success(let p) = self { return p }; return nil }
}

// MARK: - Formato de fio dos tipos neutros de permissão

extension PermissionRequest {

    init?(id: String, request: JSONValue) {
        guard let toolName = request["tool_name"]?.stringValue else { return nil }
        self.init(
            id: id,
            toolName: toolName,
            displayName: request["display_name"]?.stringValue,
            description: request["description"]?.stringValue,
            input: request["input"] ?? .null,
            toolUseID: request["tool_use_id"]?.stringValue,
            suggestions: (request["permission_suggestions"]?.arrayValue ?? [])
                .map(PermissionSuggestion.init(raw:)),
            options: ClaudeOption.all
        )
    }
}

extension PermissionSuggestion {

    init(raw: JSONValue) {
        self.init(
            type: raw["type"]?.stringValue,
            mode: raw["mode"]?.stringValue,
            destination: raw["destination"]?.stringValue,
            behavior: raw["behavior"]?.stringValue,
            raw: raw
        )
    }
}

public extension PermissionDecision {

    func responseData(requestID: String) throws -> Data {
        let body: JSONValue
        switch self {
        case .option(let id):

            return try ClaudeOption.decision(for: id).responseData(requestID: requestID)
        case .allow(let updatedInput):
            var members: [String: JSONValue] = ["behavior": .string("allow")]
            if let updatedInput { members["updatedInput"] = updatedInput }
            body = .object(members)
        case .deny(let message, let interrupt):
            body = .object([
                "behavior": .string("deny"),
                "message": .string(message),
                "interrupt": .bool(interrupt),
            ])
        }
        let envelope = JSONValue.object([
            "type": .string("control_response"),
            "response": .object([
                "subtype": .string("success"),
                "request_id": .string(requestID),
                "response": body,
            ]),
        ])
        return try JSONEncoder().encode(envelope)
    }
}

public enum OutboundControlRequest: Equatable, Sendable {
    case initialize
    case interrupt
    case setPermissionMode(PermissionMode)
    case setModel(String?)

    var subtype: String {
        switch self {
        case .initialize: return "initialize"
        case .interrupt: return "interrupt"
        case .setPermissionMode: return "set_permission_mode"
        case .setModel: return "set_model"
        }
    }

    public func requestData(requestID: String) throws -> Data {
        var request: [String: JSONValue] = ["subtype": .string(subtype)]
        switch self {
        case .initialize, .interrupt:
            break
        case .setPermissionMode(let mode):

            request["mode"] = .string(mode.rawValue)
        case .setModel(let model):
            request["model"] = model.map(JSONValue.string) ?? .null
        }
        let envelope = JSONValue.object([
            "type": .string("control_request"),
            "request_id": .string(requestID),
            "request": .object(request),
        ])
        return try JSONEncoder().encode(envelope)
    }
}

enum ClaudeOption {
    static let allowID = "allow"
    static let denyID = "deny"

    static let all: [PermissionOption] = [
        PermissionOption(id: denyID, kind: .rejectOnce, label: "Negar"),
        PermissionOption(id: allowID, kind: .allowOnce, label: "Permitir"),
    ]

    static func decision(for id: String) -> PermissionDecision {
        id == allowID
            ? .allow(updatedInput: nil)
            : .deny(message: "o usuário negou", interrupt: false)
    }
}

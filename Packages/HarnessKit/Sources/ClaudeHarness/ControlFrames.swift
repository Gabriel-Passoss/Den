import Foundation
import HarnessCore

/// O que uma linha do stdout do harness é, do ponto de vista do canal de controle.
public enum ControlFrame: Equatable, Sendable {
    /// Mensagem de conversa — o canal não a interpreta; a Etapa 4 mapeia.
    case conversation
    /// O harness está pedindo permissão para usar uma ferramenta.
    case permissionRequest(PermissionRequest)
    /// Resposta a um request que nós enviamos.
    case response(requestID: String, ControlResponseResult)
    /// Quadro de controle de subtipo que não conhecemos. Spec §5.4: preservar,
    /// não falhar.
    case unknownControl(requestID: String, raw: JSONValue)

    public static func classify(_ line: Data) -> ControlFrame {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line),
              let type = value["type"]?.stringValue
        else { return .conversation }

        switch type {
        case "control_request":
            let id = value["request_id"]?.stringValue ?? ""
            guard let request = value["request"],
                  request["subtype"]?.stringValue == "can_use_tool",
                  let parsed = PermissionRequest(id: id, request: request)
            else { return .unknownControl(requestID: id, raw: value) }
            return .permissionRequest(parsed)

        case "control_response":
            // Spec §5.4, mesma regra que control_request: um quadro que não
            // conseguimos interpretar é preservado, não descartado.
            guard let response = value["response"] else {
                return .unknownControl(requestID: "", raw: value)
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
                // Controller ruling (Finding 1): falhar alto em vez de suceder
                // quieto. Um subtipo que não é "success" nem "error" — ausente
                // ou um futuro "cancelled"/"timeout" — não pode virar sucesso
                // silencioso: quem espera essa resposta seguiria em frente com
                // dados ruins em vez de investigar.
                return .response(requestID: id,
                                 .failure("resposta com subtipo desconhecido: \(subtype ?? "ausente")"))
            }

        default:
            return .conversation
        }
    }
}

public enum ControlResponseResult: Equatable, Sendable {
    case success(JSONValue)
    case failure(String)

    public var isSuccess: Bool { if case .success = self { return true }; return false }
    public var errorMessage: String? { if case .failure(let m) = self { return m }; return nil }
    public var payload: JSONValue? { if case .success(let p) = self { return p }; return nil }
}

/// Um pedido de permissão vindo do harness.
public struct PermissionRequest: Equatable, Sendable {
    public let id: String
    public let toolName: String
    public let displayName: String?
    public let description: String?
    public let input: JSONValue
    public let toolUseID: String?
    /// Regras que o próprio harness sugere — material direto para os botões do
    /// diálogo ("permitir sempre nesta sessão") em vez de inventarmos os nossos.
    public let suggestions: [PermissionSuggestion]

    init?(id: String, request: JSONValue) {
        guard let toolName = request["tool_name"]?.stringValue else { return nil }
        self.id = id
        self.toolName = toolName
        self.displayName = request["display_name"]?.stringValue
        self.description = request["description"]?.stringValue
        self.input = request["input"] ?? .null
        self.toolUseID = request["tool_use_id"]?.stringValue
        self.suggestions = (request["permission_suggestions"]?.arrayValue ?? [])
            .map(PermissionSuggestion.init(raw:))
    }
}

public struct PermissionSuggestion: Equatable, Sendable {
    public let type: String?
    public let mode: String?
    public let destination: String?
    public let behavior: String?
    /// Payload original preservado — nem todo campo de sugestão é conhecido.
    /// Controller ruling (Finding 3): uma sugestão sem "type" ainda é
    /// preservada aqui, não descartada — um diálogo que ignora o que não
    /// entende é melhor que um `suggestions.count` que mente sobre o que o
    /// harness realmente ofereceu.
    public let raw: JSONValue

    init(raw: JSONValue) {
        self.type = raw["type"]?.stringValue
        self.mode = raw["mode"]?.stringValue
        self.destination = raw["destination"]?.stringValue
        self.behavior = raw["behavior"]?.stringValue
        self.raw = raw
    }
}

public enum PermissionDecision: Equatable, Sendable {
    case allow(updatedInput: JSONValue?)
    case deny(message: String, interrupt: Bool)

    /// A linha NDJSON a escrever no stdin do harness.
    public func responseData(requestID: String) throws -> Data {
        let body: JSONValue
        switch self {
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

/// Requests que nós enviamos ao harness.
public enum OutboundControlRequest: Equatable, Sendable {
    case initialize
    case interrupt
    case setPermissionMode(String)
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
            request["mode"] = .string(mode)
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

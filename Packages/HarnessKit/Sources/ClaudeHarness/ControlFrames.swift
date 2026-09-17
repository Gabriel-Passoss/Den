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
    /// Um `control_request` que não sabemos atender **e que trouxe um
    /// `request_id` respondível**. Spec §5.4: preservar, não falhar — e, por
    /// cima disso, destravar: do outro lado do fio há um harness parado
    /// esperando resposta para este id. É `ControlChannel.consume` quem paga
    /// essa dívida, respondendo `subtype: "error"`.
    ///
    /// O id é `String` não-vazia por construção (ver `classify`): é essa
    /// garantia que torna a resposta automática possível sem checagem em
    /// tempo de execução.
    case unansweredControlRequest(requestID: String, raw: JSONValue)
    /// Quadro de controle que não sabemos atender e ao qual **não há como**
    /// responder: ou não é um request (um `control_response` que não conseguimos
    /// ler), ou é um request que chegou sem `request_id`.
    ///
    /// Caso distinto de `.unansweredControlRequest` de propósito, e não um
    /// `requestID: ""` como antes: uma string vazia é exatamente o sentinela
    /// que fazia uma resposta sair com `request_id: ""` — que o CLI nunca casa
    /// — em vez de o chamador descobrir que não havia id nenhum.
    case unknownControl(raw: JSONValue)

    public static func classify(_ line: Data) -> ControlFrame {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line),
              let type = value["type"]?.stringValue
        else { return .conversation }

        switch type {
        case "control_request":
            // Um `request_id` ausente ou vazio não é respondível: qualquer
            // resposta nossa sairia com `request_id: ""` e a tabela de
            // pendentes do CLI nunca a casaria. Entregar isso como
            // `.permissionRequest` abriria um diálogo na UI cuja resposta é
            // garantidamente descartada — o harness bloqueia para sempre e o
            // usuário acha que aprovou. Sem id, o quadro só pode ser
            // registrado.
            guard let id = value["request_id"]?.stringValue, !id.isEmpty else {
                return .unknownControl(raw: value)
            }
            guard let request = value["request"],
                  request["subtype"]?.stringValue == "can_use_tool",
                  let parsed = PermissionRequest(id: id, request: request)
            else { return .unansweredControlRequest(requestID: id, raw: value) }
            return .permissionRequest(parsed)

        case "control_response":
            // Spec §5.4, mesma regra que control_request: um quadro que não
            // conseguimos interpretar é preservado, não descartado. Mas não é
            // respondível: uma resposta a uma resposta não existe no
            // protocolo, e o `request_id` mora justamente dentro do corpo que
            // está faltando.
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

/// A recusa que mandamos de volta quando não sabemos atender um
/// `control_request`.
///
/// É o mesmo envelope que o CLI usa para recusar um request *nosso* — ver o
/// ramo `control_response`/`error` de `ControlFrame.classify` —, aqui na
/// direção oposta. O protocolo já tem esta forma; não estamos inventando
/// mensagem nova, só usando a que existe no sentido que ainda não usávamos.
///
/// Existe porque o silêncio não é uma opção: o CLI mantém uma tabela de
/// pendentes e **espera**. Um request que descartamos é uma sessão congelada
/// sem uma linha de log — exatamente o sintoma que a spec §4.4 nomeia.
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

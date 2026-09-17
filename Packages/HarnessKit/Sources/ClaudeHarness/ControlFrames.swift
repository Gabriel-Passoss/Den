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

// MARK: - Formato de fio dos tipos neutros de permissão
//
// `PermissionRequest`, `PermissionSuggestion` e `PermissionDecision` são de
// `HarnessCore` (spec §7.1). O que mora aqui é a leitura e a escrita **deste**
// CLI, e mora neste arquivo de propósito: o decodificador fica ao lado do
// `switch` de `ControlFrame.classify`, que é o seu único chamador, e o
// codificador ao lado do envelope que ele preenche. Separá-los num arquivo
// próprio poria uma função a um arquivo de distância da única linha que a usa.

extension PermissionRequest {
    /// Lê um `can_use_tool` do Claude Code. Falha quando o quadro não traz
    /// `tool_name`.
    ///
    /// **Continua falível, e isso é a metade do item 1 que faz o resto
    /// funcionar.** O `nil` daqui é o que roteia o quadro para
    /// `.unansweredControlRequest`, que responde erro e destrava o harness. Se
    /// este inicializador virasse infalível — com um `toolName` default, por
    /// exemplo —, a UI abriria um diálogo pedindo aprovação para uma ferramenta
    /// que não sabemos nomear: a §5.4 do avesso, degradando para uma mentira em
    /// vez de para uma recusa. A falha aqui não é um caso de erro; é a
    /// fronteira entre "entendemos o pedido" e "temos que recusá-lo".
    ///
    /// O `id` chega por parâmetro, já validado como não-vazio por `classify` —
    /// é lá que a pergunta "isto é respondível?" pertence, porque é lá que a
    /// resposta escolhe o caso do `ControlFrame`.
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
                .map(PermissionSuggestion.init(raw:))
        )
    }
}

extension PermissionSuggestion {
    /// Lê uma entrada de `permission_suggestions` do Claude Code.
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
    /// A linha NDJSON a escrever no stdin do harness.
    func responseData(requestID: String) throws -> Data {
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
            // A grafia que o CLI espera no fio é a mesma do `rawValue`; a
            // tradução acontece aqui, no adaptador, e não em `HarnessCore`.
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

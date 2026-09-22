import Foundation
import HarnessCore

enum OpenCodePermission {

    static func kind(for raw: String) -> PermissionOption.Kind {
        switch raw {
        case "allow_once": .allowOnce
        case "allow_always": .allowAlways
        case "reject_once": .rejectOnce
        case "reject_always": .rejectAlways
        default: .other
        }
    }

    static func label(for raw: String, name: String) -> String {
        switch kind(for: raw) {
        case .allowOnce: "Permitir"
        case .allowAlways: "Sempre permitir"
        case .rejectOnce: "Negar"
        case .rejectAlways: "Sempre negar"
        case .other: OpenCodeKnobs.capitalized(name)
        }
    }

    static func request(id: String, params: JSONValue) -> PermissionRequest {
        let call = params["toolCall"] ?? .null
        let options = (params["options"]?.arrayValue ?? []).compactMap {
            option -> PermissionOption? in
            guard let optionID = option["optionId"]?.stringValue else { return nil }
            let raw = option["kind"]?.stringValue ?? ""
            return PermissionOption(
                id: optionID,
                kind: kind(for: raw),
                label: label(for: raw, name: option["name"]?.stringValue ?? optionID))
        }
        return PermissionRequest(
            id: id,
            toolName: call["title"]?.stringValue ?? call["kind"]?.stringValue ?? "ferramenta",
            input: call["rawInput"] ?? .null,
            toolUseID: call["toolCallId"]?.stringValue,
            options: options
        )
    }

    /// O CLI espera uma opção nomeada. Uma decisão binária vinda de outro
    /// caminho escolhe a primeira opção compatível que ele ofereceu.
    static func outcome(for decision: PermissionDecision,
                        offered: [PermissionOption]) -> JSONValue {
        let chosen: String?
        switch decision {
        case .option(let id):
            chosen = id
        case .allow:
            chosen = offered.first { $0.kind == .allowOnce }?.id
                ?? offered.first { $0.isAllow }?.id
        case .deny:
            chosen = offered.first { $0.kind == .rejectOnce }?.id
                ?? offered.first { !$0.isAllow }?.id
        }
        guard let chosen else { return .object(["outcome": .string("cancelled")]) }
        return .object([
            "outcome": .string("selected"),
            "optionId": .string(chosen),
        ])
    }
}

import Foundation
import HarnessCore

public enum OpenCodeKnobs {
    public static let model = "model"
    public static let mode = "mode"
    public static let effort = "effort"

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static let names: [String: String] = [
        model: "Modelo",
        mode: "Modo",
        effort: "Esforço",
    ]

    static let labels: [String: [String: String]] = [
        mode: [
            "build": "Construir",
            "plan": "Plano",
        ],
        effort: [
            "none": "Nenhum",
            "low": "Baixo",
            "medium": "Médio",
            "high": "Alto",
            "xhigh": "Muito alto",
            "default": "Padrão",
        ],
    ]

    static func name(for id: String, fallback: String) -> String {
        names[id] ?? capitalized(fallback)
    }

    static func category(for raw: String, id: String) -> HarnessKnob.Category {
        switch raw {
        case "model": .model
        case "mode": .mode
        case "thought_level", "effort": .effort
        default: id == model ? .model : (id == mode ? .mode : .effort)
        }
    }

    static func split(modelName: String) -> (label: String, group: String?) {
        guard let slash = modelName.firstIndex(of: "/") else { return (modelName, nil) }
        let provider = String(modelName[modelName.startIndex..<slash])
            .trimmingCharacters(in: .whitespaces)
        let name = String(modelName[modelName.index(after: slash)...])
            .trimmingCharacters(in: .whitespaces)
        guard !provider.isEmpty, !name.isEmpty else { return (modelName, nil) }
        return (name, provider)
    }

    static func option(_ raw: JSONValue, in knobID: String) -> HarnessKnob.Option? {
        guard let value = raw["value"]?.stringValue else { return nil }
        let given = raw["name"]?.stringValue ?? value

        if knobID == model {
            let parts = split(modelName: given)
            return HarnessKnob.Option(value: value, label: parts.label, group: parts.group)
        }
        return HarnessKnob.Option(
            value: value,
            label: labels[knobID]?[value] ?? capitalized(given))
    }

    public static func parse(_ configOptions: JSONValue?) -> [HarnessKnob] {
        guard let items = configOptions?.arrayValue else { return [] }
        return items.compactMap { item in
            guard let id = item["id"]?.stringValue else { return nil }
            return HarnessKnob(
                id: id,
                category: category(for: item["category"]?.stringValue ?? "", id: id),
                name: name(for: id, fallback: item["name"]?.stringValue ?? id),
                currentValue: item["currentValue"]?.stringValue,
                options: (item["options"]?.arrayValue ?? []).compactMap { option($0, in: id) })
        }
    }

    public static func model(in knobs: [HarnessKnob]) -> String {
        knobs.first { $0.id == model }?.currentValue ?? ""
    }
}

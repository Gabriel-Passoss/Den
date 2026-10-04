import Foundation

public enum HandoffSeed: Sendable {

    public static let defaultBudget = 60_000

    public struct Result: Sendable, Equatable {
        public let text: String
        public let handoff: Handoff

        public var isComplete: Bool {
            if case .replay = handoff { return true }
            return false
        }
    }

    public static let preamble = """
        Estou retomando uma conversa que começou com outro assistente. \
        Abaixo está o que já aconteceu — leia como contexto, sem responder \
        a ela. O que eu preciso agora vem no fim.
        """

    public static let requestHeading = "---\n\n**Agora, o pedido:**"

    static let emptyRequest = "Siga de onde paramos."

    public static let omissionMarker = "_(turnos anteriores omitidos por tamanho)_"

    public static func make(_ entries: [TranscriptEntry],
                            budget: Int = defaultBudget) -> Result? {
        let rendered = entries.compactMap(line(of:))
        guard !rendered.isEmpty else { return nil }

        let whole = assemble(rendered)
        if whole.count <= budget, let last = entries.last {
            return Result(text: whole, handoff: .replay(throughEntry: last.id))
        }

        var kept: [String] = []
        var size = preamble.count + omissionMarker.count
        for entry in rendered.reversed() {
            let cost = entry.count + 2
            if size + cost > budget { break }
            kept.insert(entry, at: 0)
            size += cost
        }
        guard !kept.isEmpty else { return nil }
        return Result(text: assemble([omissionMarker] + kept), handoff: .briefing(assemble(kept)))
    }

    public static func message(seed: String, request: String) -> String {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        return [seed, requestHeading, trimmed.isEmpty ? emptyRequest : trimmed]
            .joined(separator: "\n\n")
    }

    static func assemble(_ lines: [String]) -> String {
        ([preamble, ""] + lines).joined(separator: "\n\n")
    }

    public static func line(of entry: TranscriptEntry) -> String? {
        switch entry.kind {
        case .userMessage(let text, _):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "**Você:** \(trimmed)"

        case .assistantText(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "**Assistente:** \(trimmed)"

        case .toolCall(let call):
            let detail = summary(of: call)
            return detail.isEmpty
                ? "_(usou \(call.rawName))_"
                : "_(usou \(call.rawName): \(detail))_"

        case .assistantThinking, .toolResult, .permissionRequest,
             .permissionDecision, .systemNotice, .turnResult,
             .contextCompacted, .unrecognized:
            return nil
        }
    }

    static func summary(of call: ToolCall) -> String {
        for key in ["command", "file_path", "path", "pattern", "url", "query"] {
            if let value = call.input[key]?.stringValue, !value.isEmpty {
                return value.count > 120 ? String(value.prefix(120)) + "…" : value
            }
        }
        return ""
    }
}

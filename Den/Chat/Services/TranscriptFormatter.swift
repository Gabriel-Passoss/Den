import Foundation
import HarnessCore

nonisolated enum TranscriptFormatter {
    static let envelopes = [
        "local-command-caveat", "command-name", "command-message",
        "command-args", "local-command-stdout", "local-command-stderr",
    ]

    static func unwrapped(_ text: String) -> String {
        var out = text
        for tag in envelopes {
            out = out.replacingOccurrences(of: "<" + tag + ">", with: "")
            out = out.replacingOccurrences(of: "</" + tag + ">", with: "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func headline(of compaction: ContextCompaction) -> String {
        var parts = ["Conversa compactada"]
        if compaction.tokensBefore > 0, compaction.tokensAfter > 0 {
            parts.append("\(tokens(compaction.tokensBefore)) → "
                         + "\(tokens(compaction.tokensAfter)) tokens")
        }
        if compaction.duration >= 1 { parts.append(elapsed(compaction.duration)) }
        return parts.joined(separator: " · ")
    }

    static func tokens(_ value: Int) -> String {
        value >= 1_000 ? "\(Int((Double(value) / 1_000).rounded()))k" : String(value)
    }

    static func elapsed(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)min \(seconds % 60)s"
    }

    static func summary(of call: ToolCall) -> String {
        let input = call.input
        if let command = input["command"]?.stringValue { return command }
        if let path = input["file_path"]?.stringValue {
            return (path as NSString).lastPathComponent
        }
        if let pattern = input["pattern"]?.stringValue { return pattern }
        if let url = input["url"]?.stringValue { return url }
        return oneLine(input)
    }

    static func oneLine(_ value: JSONValue) -> String {
        let text: String
        switch value {
        case .string(let s): text = s
        case .object(let members):
            text = members.map { "\($0.key)=\(oneLine($0.value))" }.sorted().joined(separator: " ")
        case .array(let items): text = items.map(oneLine).joined(separator: ", ")
        case .int(let i): text = String(i)
        case .double(let d): text = String(d)
        case .bool(let b): text = String(b)
        case .null: text = "—"
        }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 200 ? String(flat.prefix(200)) + "…" : flat
    }
}

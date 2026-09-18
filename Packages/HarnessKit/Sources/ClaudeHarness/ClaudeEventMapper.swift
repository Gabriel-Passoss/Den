import Foundation
import HarnessCore

public struct ClaudeEventMapper: Sendable {

    static let discriminatorPrefix = "claude:"

    let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func map(_ line: JSONValue) -> MappedOutput {
        guard let type = line["type"]?.stringValue else {
            return MappedOutput(entries: [unrecognized("line", line)])
        }
        switch type {
        case "stream_event":
            return ephemeral(line)
        case "assistant":
            return assistant(line)
        case "user":
            return user(line)
        case "result":
            return result(line)
        case "system":
            return system(line)
        case "rate_limit_event":
            return rateLimit(line)
        case "control_request", "control_response":

            return .empty
        default:
            return MappedOutput(entries: [unrecognized(type, line)])
        }
    }

    public func map(line data: Data) -> MappedOutput {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            let text = JSONValue.string(String(decoding: data, as: UTF8.self))
            return MappedOutput(entries: [unrecognized("nonJSON", text)])
        }
        return map(value)
    }

    // MARK: - Efêmero

    private func ephemeral(_ line: JSONValue) -> MappedOutput {
        guard let event = line["event"], let kind = event["type"]?.stringValue else {
            return .empty
        }
        switch kind {
        case "message_start":
            return MappedOutput(events: [.turnStarted])
        case "content_block_delta":
            return MappedOutput(events: delta(event).map { [$0] } ?? [])
        default:

            return .empty
        }
    }

    private func delta(_ event: JSONValue) -> SessionEvent? {
        guard let index = event["index"]?.intValue,
              let delta = event["delta"],
              let kind = delta["type"]?.stringValue
        else { return nil }

        switch kind {
        case "text_delta":
            guard let text = delta["text"]?.stringValue else { return nil }
            return .textDelta(blockIndex: index, text: text)
        case "thinking_delta":
            guard let text = delta["thinking"]?.stringValue else { return nil }
            return .thinkingDelta(blockIndex: index, text: text)
        case "input_json_delta":
            guard let partial = delta["partial_json"]?.stringValue else { return nil }
            return .toolInputDelta(blockIndex: index, partialJSON: partial)
        default:

            return nil
        }
    }

    // MARK: - Degradação

    func unrecognized(_ discriminator: String, _ payload: JSONValue,
                      at moment: Date? = nil) -> TranscriptEntry {
        TranscriptEntry(
            timestamp: moment ?? now(),
            kind: .unrecognized(discriminator: Self.discriminatorPrefix + discriminator,
                                payload: payload),
            raw: payload
        )
    }
}

// MARK: - Durável

private extension ClaudeEventMapper {

    func assistant(_ line: JSONValue) -> MappedOutput {
        let moment = timestamp(of: line)
        guard let blocks = line["message"]?["content"]?.arrayValue else {
            return MappedOutput(entries: [unrecognized("assistant", line, at: moment)])
        }
        return MappedOutput(entries: blocks.map { assistantBlock($0, at: moment) })
    }

    func assistantBlock(_ block: JSONValue, at moment: Date) -> TranscriptEntry {
        switch block["type"]?.stringValue {
        case "text":
            guard let text = block["text"]?.stringValue else { break }
            return TranscriptEntry(timestamp: moment, kind: .assistantText(text), raw: block)
        case "thinking":

            guard let text = block["thinking"]?.stringValue else { break }
            return TranscriptEntry(timestamp: moment, kind: .assistantThinking(text), raw: block)
        case "tool_use":
            guard let id = block["id"]?.stringValue,
                  let name = block["name"]?.stringValue else { break }
            let call = ToolCall(
                id: id,
                rawName: name,
                canonical: ClaudeToolVocabulary.canonical(for: name),
                input: block["input"] ?? .null
            )
            return TranscriptEntry(timestamp: moment, kind: .toolCall(call), raw: block)
        default:
            break
        }
        return unrecognizedBlock(block, at: moment)
    }

    func user(_ line: JSONValue) -> MappedOutput {
        let moment = timestamp(of: line)
        guard let content = line["message"]?["content"] else {
            return MappedOutput(entries: [unrecognized("user", line, at: moment)])
        }

        if let text = content.stringValue {
            return MappedOutput(entries: [
                TranscriptEntry(timestamp: moment,
                                kind: .userMessage(text: text, attachments: []),
                                raw: line)
            ])
        }
        guard let blocks = content.arrayValue else {
            return MappedOutput(entries: [unrecognized("user", line, at: moment)])
        }
        return MappedOutput(entries: blocks.map { userBlock($0, at: moment) })
    }

    func userBlock(_ block: JSONValue, at moment: Date) -> TranscriptEntry {
        guard block["type"]?.stringValue == "tool_result",
              let callID = block["tool_use_id"]?.stringValue
        else { return unrecognizedBlock(block, at: moment) }

        let result = ToolResult(
            callID: callID,

            isError: block["is_error"]?.boolValue ?? false,
            content: block["content"] ?? .null
        )
        return TranscriptEntry(timestamp: moment, kind: .toolResult(result), raw: block)
    }

    func result(_ line: JSONValue) -> MappedOutput {
        let usage = line["usage"]
        let totals = UsageTotals(
            inputTokens: usage?["input_tokens"]?.intValue ?? 0,
            outputTokens: usage?["output_tokens"]?.intValue ?? 0,
            cacheReadTokens: usage?["cache_read_input_tokens"]?.intValue ?? 0,
            cacheCreationTokens: usage?["cache_creation_input_tokens"]?.intValue ?? 0,
            costUSD: line["total_cost_usd"]?.doubleValue ?? 0
        )
        let turn = TurnResult(
            usage: totals,
            stopReason: line["stop_reason"]?.stringValue,
            isError: line["is_error"]?.boolValue ?? false
        )
        return MappedOutput(entries: [
            TranscriptEntry(timestamp: timestamp(of: line), kind: .turnResult(turn), raw: line)
        ])
    }

    func unrecognizedBlock(_ block: JSONValue, at moment: Date) -> TranscriptEntry {
        unrecognized("content/" + (block["type"]?.stringValue ?? "?"), block, at: moment)
    }

    func timestamp(of line: JSONValue) -> Date {
        guard let text = line["timestamp"]?.stringValue else { return now() }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) {
            return date
        }
        return now()
    }

    func system(_ line: JSONValue) -> MappedOutput {
        guard let subtype = line["subtype"]?.stringValue else {
            return MappedOutput(entries: [unrecognized("system", line)])
        }
        let moment = timestamp(of: line)
        switch subtype {
        case "init":
            let model = line["model"]?.stringValue ?? ""
            return MappedOutput(
                events: [.sessionInitialized(
                    model: model,
                    harnessSessionID: line["session_id"]?.stringValue ?? ""
                )],
                entries: [TranscriptEntry(
                    timestamp: moment,
                    kind: .systemNotice(subtype: "init", text: model),
                    raw: line
                )]
            )

        case "status":
            return MappedOutput(events: [
                .notice(subtype: subtype, text: line["status"]?.stringValue ?? "")
            ])

        case "thinking_tokens":
            return MappedOutput(events: [
                .notice(subtype: subtype,
                        text: line["estimated_tokens"]?.intValue.map { String($0) } ?? "")
            ])

        case "hook_started", "hook_response":

            return MappedOutput(events: [
                .notice(subtype: subtype, text: line["hook_name"]?.stringValue ?? "")
            ])

        case "permission_denied":

            guard let toolUseID = line["tool_use_id"]?.stringValue else {
                return MappedOutput(entries: [unrecognized("system/" + subtype, line)])
            }
            return MappedOutput(entries: [TranscriptEntry(
                timestamp: moment,
                kind: .permissionDecision(
                    requestID: toolUseID,
                    .deny(message: line["message"]?.stringValue ?? "", interrupt: false)
                ),
                raw: line
            )])

        default:
            return MappedOutput(entries: [unrecognized("system/" + subtype, line)])
        }
    }

    func rateLimit(_ line: JSONValue) -> MappedOutput {
        MappedOutput(entries: [TranscriptEntry(
            timestamp: timestamp(of: line),
            kind: .systemNotice(
                subtype: "rate_limit",
                text: line["rate_limit_info"]?["status"]?.stringValue ?? ""
            ),
            raw: line
        )])
    }
}

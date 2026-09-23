import Foundation
import HarnessCore

public struct OpenCodeEventMapper: Sendable {

    static let discriminatorPrefix = "opencode:"

    let now: @Sendable () -> Date

    private var pending: (id: String, text: String, isThought: Bool)?
    private var heldToolCalls: [String: HeldTool] = [:]
    private var announcedToolCalls: Set<String> = []
    private var settledToolCalls: Set<String> = []
    private var blockIndex = 0
    private var latestCost: Double = 0
    private var contextTokens = 0
    private var compactingSince: Date?
    private var contextBeforeCompaction = 0
    private var compactionProse: [String] = []

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public mutating func beginCompaction() {
        compactingSince = now()
        contextBeforeCompaction = contextTokens
        compactionProse = []
    }

    // MARK: - Notificações de sessão

    public mutating func map(update: JSONValue) -> MappedOutput {
        guard let kind = update["sessionUpdate"]?.stringValue else {
            return MappedOutput(entries: [unrecognized("update", update)])
        }

        switch kind {
        case "agent_message_chunk":
            return chunk(update, isThought: false)
        case "agent_thought_chunk":
            return chunk(update, isThought: true)
        case "user_message_chunk":
            return userMessage(update)
        case "tool_call":
            return toolCall(update)
        case "tool_call_update":
            return toolCallUpdate(update)
        case "usage_update":
            latestCost = update["cost"]?["amount"]?.doubleValue ?? latestCost
            guard let used = update["used"]?.intValue, used > 0 else { return .empty }
            contextTokens = used
            return MappedOutput(events: [.contextUsage(tokens: used)])

        case "available_commands_update":
            let names = update["availableCommands"]?.arrayValue?
                .compactMap { $0["name"]?.stringValue } ?? []
            guard !names.isEmpty else { return .empty }
            return MappedOutput(events: [.catalogUpdated(
                CommandCatalog(skills: names.sorted(), supportsCompact: true))])
        default:

            return MappedOutput(entries: [unrecognized(kind, update)])
        }
    }

    private mutating func chunk(_ update: JSONValue, isThought: Bool) -> MappedOutput {
        guard let text = update["content"]?["text"]?.stringValue else { return .empty }
        let id = update["messageId"]?.stringValue ?? ""

        var output = MappedOutput()

        if let open = pending, open.id != id || open.isThought != isThought {
            output.entries += flushPending()
        }
        if pending == nil {
            pending = (id: id, text: "", isThought: isThought)
        }
        pending?.text += text

        guard compactingSince == nil else { return output }

        output.events.append(isThought
            ? .thinkingDelta(blockIndex: blockIndex, text: text)
            : .textDelta(blockIndex: blockIndex, text: text))
        return output
    }

    private mutating func flushPending() -> [TranscriptEntry] {
        guard let open = pending else { return [] }
        pending = nil
        blockIndex += 1

        let trimmed = open.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if compactingSince != nil {
            if !open.isThought { compactionProse.append(trimmed) }
            return []
        }

        let entry = TranscriptEntry(
            timestamp: now(),
            kind: open.isThought ? .assistantThinking(open.text) : .assistantText(open.text),
            raw: .object([
                "sessionUpdate": .string(open.isThought
                    ? "agent_thought_chunk" : "agent_message_chunk"),
                "messageId": .string(open.id),
                "text": .string(open.text),
            ])
        )

        return [entry]
    }

    private mutating func closeCompaction() -> [TranscriptEntry] {
        guard let started = compactingSince else { return [] }
        compactingSince = nil

        let prose = compactionProse.joined(separator: "\n\n")
        compactionProse = []
        guard !prose.isEmpty else { return [] }

        let moved = contextTokens != contextBeforeCompaction
        return [
            TranscriptEntry(
                timestamp: now(),
                kind: .contextCompacted(ContextCompaction(
                    trigger: .manual,
                    tokensBefore: moved ? contextBeforeCompaction : 0,
                    tokensAfter: moved ? contextTokens : 0,
                    duration: now().timeIntervalSince(started))),
                raw: .object(["inferredFrom": .string(CommandCatalog.compactCommand)])
            ),
            TranscriptEntry(
                timestamp: now(),
                kind: .assistantText(prose),
                raw: .object([
                    "sessionUpdate": .string("agent_message_chunk"),
                    "text": .string(prose),
                ])
            ),
        ]
    }

    public mutating func flush() -> MappedOutput {
        var entries = flushPending()

        for id in heldToolCalls.keys.sorted() where !announcedToolCalls.contains(id) {
            entries += announce(id)
        }
        entries += closeCompaction()
        return MappedOutput(entries: entries)
    }

    private mutating func userMessage(_ update: JSONValue) -> MappedOutput {
        guard let text = update["content"]?["text"]?.stringValue else { return .empty }
        return MappedOutput(entries: [TranscriptEntry(
            timestamp: now(),
            kind: .userMessage(text: text, attachments: []),
            raw: update
        )])
    }

    // MARK: - Ferramentas

    struct HeldTool {
        var title: String
        var kind: String

        var input: JSONValue
    }

    private mutating func hold(_ update: JSONValue, id: String) {
        let input = update["rawInput"] ?? .null
        guard var held = heldToolCalls[id] else {
            heldToolCalls[id] = HeldTool(
                title: update["title"]?.stringValue ?? "",
                kind: update["kind"]?.stringValue ?? "",
                input: input)
            return
        }
        if let title = update["title"]?.stringValue, held.title.isEmpty { held.title = title }
        if let kind = update["kind"]?.stringValue, !kind.isEmpty { held.kind = kind }
        if input != .null, input != .object([:]) { held.input = input }
        heldToolCalls[id] = held
    }

    private mutating func announce(_ id: String) -> [TranscriptEntry] {
        guard !announcedToolCalls.contains(id), let held = heldToolCalls[id] else { return [] }
        announcedToolCalls.insert(id)

        return [TranscriptEntry(
            timestamp: now(),
            kind: .toolCall(ToolCall(
                id: id,
                rawName: held.title.isEmpty ? held.kind : held.title,
                canonical: OpenCodeToolVocabulary.canonical(for: held.kind),
                input: held.input
            )),
            raw: .object([
                "toolCallId": .string(id),
                "title": .string(held.title),
                "kind": .string(held.kind),
                "rawInput": held.input,
            ])
        )]
    }

    private mutating func toolCall(_ update: JSONValue) -> MappedOutput {
        guard let id = update["toolCallId"]?.stringValue else {
            return MappedOutput(entries: [unrecognized("tool_call", update)])
        }

        var output = MappedOutput(entries: flushPending())
        hold(update, id: id)

        if update["status"]?.stringValue != "pending" {
            output.entries += announce(id)
        }
        return output
    }

    private mutating func toolCallUpdate(_ update: JSONValue) -> MappedOutput {
        guard let id = update["toolCallId"]?.stringValue else {
            return MappedOutput(entries: [unrecognized("tool_call_update", update)])
        }
        let status = update["status"]?.stringValue ?? ""

        var output = MappedOutput(entries: flushPending())
        hold(update, id: id)

        if status != "pending" { output.entries += announce(id) }

        guard Self.isTerminal(status), !settledToolCalls.contains(id) else { return output }
        settledToolCalls.insert(id)

        output.entries.append(TranscriptEntry(
            timestamp: now(),
            kind: .toolResult(ToolResult(
                callID: id,
                isError: status != "completed",
                content: Self.resultContent(update)
            )),
            raw: update
        ))
        return output
    }

    static func isTerminal(_ status: String) -> Bool {
        status == "completed" || status == "failed" || status == "cancelled"
    }

    static func resultContent(_ update: JSONValue) -> JSONValue {
        if let output = update["rawOutput"]?["output"], output != .null { return output }

        if let blocks = update["content"]?.arrayValue {
            let texts = blocks.compactMap { $0["content"]?["text"]?.stringValue }
            if !texts.isEmpty { return .string(texts.joined(separator: "\n")) }
        }
        return update["rawOutput"] ?? .null
    }

    // MARK: - Fim de turno

    public mutating func turnResult(_ result: JSONValue) -> MappedOutput {
        var output = flush()

        let usage = result["usage"]
        let stopReason = result["stopReason"]?.stringValue

        let read = (usage?["inputTokens"]?.intValue ?? 0)
            + (usage?["cachedReadTokens"]?.intValue ?? 0)
        if contextTokens == 0, read > 0 {
            contextTokens = read
            output.events.append(.contextUsage(tokens: read))
        }
        let context = contextTokens > 0 ? contextTokens : nil

        output.entries.append(TranscriptEntry(
            timestamp: now(),
            kind: .turnResult(TurnResult(
                usage: UsageTotals(
                    inputTokens: usage?["inputTokens"]?.intValue ?? 0,
                    outputTokens: usage?["outputTokens"]?.intValue ?? 0,
                    cacheReadTokens: usage?["cachedReadTokens"]?.intValue ?? 0,
                    cacheCreationTokens: 0,
                    costUSD: latestCost
                ),
                stopReason: stopReason,

                isError: stopReason == "refusal" || stopReason == "error",
                contextTokens: context
            )),
            raw: result
        ))
        blockIndex = 0
        return output
    }

    // MARK: - Degradação

    func unrecognized(_ discriminator: String, _ payload: JSONValue) -> TranscriptEntry {
        TranscriptEntry(
            timestamp: now(),
            kind: .unrecognized(
                discriminator: Self.discriminatorPrefix + discriminator,
                payload: payload
            ),
            raw: payload
        )
    }
}

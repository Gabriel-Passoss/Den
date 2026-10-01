import Foundation

public enum ContextCategory: Sendable, Hashable {
    case systemPrompt
    case systemTools
    case mcpTools
    case customAgents
    case memoryFiles
    case skills
    case messages

    case toolActivity

    case systemAndTools
    case autocompactBuffer
    case freeSpace
    case other(String)
}

extension ContextCategory: Codable {
    private static let named: [String: ContextCategory] = [
        "systemPrompt": .systemPrompt,
        "systemTools": .systemTools,
        "mcpTools": .mcpTools,
        "customAgents": .customAgents,
        "memoryFiles": .memoryFiles,
        "skills": .skills,
        "messages": .messages,
        "toolActivity": .toolActivity,
        "systemAndTools": .systemAndTools,
        "autocompactBuffer": .autocompactBuffer,
        "freeSpace": .freeSpace,
    ]

    private static let otherPrefix = "other:"

    private var name: String {
        if case .other(let name) = self { return Self.otherPrefix + name }
        return Self.named.first { $0.value == self }?.key ?? ""
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let known = Self.named[raw] {
            self = known
        } else if raw.hasPrefix(Self.otherPrefix) {
            self = .other(String(raw.dropFirst(Self.otherPrefix.count)))
        } else {
            self = .other(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

public struct ContextSlice: Sendable, Equatable, Codable {
    public let category: ContextCategory
    public let tokens: Int

    public let isDeferred: Bool

    public init(category: ContextCategory, tokens: Int, isDeferred: Bool = false) {
        self.category = category
        self.tokens = tokens
        self.isDeferred = isDeferred
    }
}

public struct ContextItem: Sendable, Equatable, Codable {
    public let name: String

    public let group: String?
    public let tokens: Int
    public let isDeferred: Bool

    public init(name: String, group: String? = nil, tokens: Int, isDeferred: Bool = false) {
        self.name = name
        self.group = group
        self.tokens = tokens
        self.isDeferred = isDeferred
    }
}

public struct ContextDetail: Sendable, Equatable, Codable {
    public let category: ContextCategory
    public let items: [ContextItem]

    public init(category: ContextCategory, items: [ContextItem]) {
        self.category = category
        self.items = items
    }

    public var tokens: Int { items.reduce(0) { $0 + $1.tokens } }
}

public struct ContextUsage: Sendable, Equatable, Codable {
    public let usedTokens: Int
    public let windowTokens: Int
    public let slices: [ContextSlice]
    public let details: [ContextDetail]

    public let isEstimate: Bool

    public init(usedTokens: Int, windowTokens: Int, slices: [ContextSlice],
                details: [ContextDetail] = [], isEstimate: Bool = false) {
        self.usedTokens = usedTokens
        self.windowTokens = windowTokens
        self.slices = slices
        self.details = details
        self.isEstimate = isEstimate
    }

    public var fraction: Double {
        Self.fraction(used: usedTokens, window: windowTokens)
    }

    public static func fraction(used: Int, window: Int) -> Double {
        guard window > 0 else { return 0 }
        return min(1, Double(used) / Double(window))
    }
}

extension ContextUsage {

    public static func estimate(from entries: [TranscriptEntry],
                                used: Int, window: Int) -> ContextUsage {
        let live = entries.lastIndex { entry in
            if case .contextCompacted = entry.kind { return true }
            return false
        }.map { entries[($0 + 1)...] } ?? entries[...]

        var messages = 0
        var tools = 0
        for entry in live {
            switch entry.kind {
            case .userMessage(let text, _), .assistantText(let text):
                messages += approximateTokens(text)
            case .toolCall(let call):
                tools += approximateTokens(call.input)
            case .toolResult(let result):
                tools += approximateTokens(result.content)
            default:
                break
            }
        }

        let explained = messages + tools
        if explained > used, explained > 0 {
            let scale = Double(used) / Double(explained)
            messages = Int((Double(messages) * scale).rounded())
            tools = Int((Double(tools) * scale).rounded())
        }
        let system = max(0, used - messages - tools)

        let filled = [
            ContextSlice(category: .systemAndTools, tokens: system),
            ContextSlice(category: .messages, tokens: messages),
            ContextSlice(category: .toolActivity, tokens: tools),
        ].filter { $0.tokens > 0 }
        let free = window > 0
            ? [ContextSlice(category: .freeSpace, tokens: max(0, window - used))]
            : []

        return ContextUsage(usedTokens: used, windowTokens: window,
                            slices: filled + free, isEstimate: true)
    }

    static func approximateTokens(_ text: String) -> Int {
        (text.count + 3) / 4
    }

    static func approximateTokens(_ value: JSONValue) -> Int {
        if let text = value.stringValue { return approximateTokens(text) }
        guard let data = try? JSONEncoder().encode(value) else { return 0 }
        return (data.count + 3) / 4
    }
}

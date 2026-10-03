import Foundation
import HarnessCore

enum ClaudeContextUsage {

    static func parse(_ response: JSONValue) -> ContextUsage? {
        guard let used = response["totalTokens"]?.intValue,
              let window = response["maxTokens"]?.intValue
        else { return nil }

        let slices = response["categories"]?.arrayValue?.compactMap(slice) ?? []
        let details = [
            detail(.mcpTools, response["mcpTools"]) { tool in
                guard let name = tool["name"]?.stringValue else { return nil }
                return ContextItem(name: toolName(name),
                                   group: tool["serverName"]?.stringValue,
                                   tokens: tool["tokens"]?.intValue ?? 0,
                                   isDeferred: !(tool["isLoaded"]?.boolValue ?? true))
            },
            detail(.memoryFiles, response["memoryFiles"]) { file in
                guard let path = file["path"]?.stringValue else { return nil }
                return ContextItem(name: path, group: file["type"]?.stringValue,
                                   tokens: file["tokens"]?.intValue ?? 0)
            },
            detail(.customAgents, response["agents"]) { agent in
                guard let name = agent["agentType"]?.stringValue else { return nil }
                return ContextItem(name: name, group: agent["source"]?.stringValue,
                                   tokens: agent["tokens"]?.intValue ?? 0)
            },
            detail(.skills, response["skills"]?["skillFrontmatter"]) { skill in
                guard let name = skill["name"]?.stringValue else { return nil }
                return ContextItem(name: name,
                                   group: skill["pluginName"]?.stringValue
                                       ?? skill["source"]?.stringValue,
                                   tokens: skill["tokens"]?.intValue ?? 0)
            },
        ].compactMap { $0 }

        return ContextUsage(usedTokens: used, windowTokens: window,
                            slices: slices, details: details)
    }

    private static let deferredSuffix = " (deferred)"

    private static let categories: [String: ContextCategory] = [
        "System prompt": .systemPrompt,
        "System tools": .systemTools,
        "MCP tools": .mcpTools,
        "Custom agents": .customAgents,
        "Memory files": .memoryFiles,
        "Skills": .skills,
        "Messages": .messages,
        "Autocompact buffer": .autocompactBuffer,
        "Free space": .freeSpace,
    ]

    private static func slice(_ category: JSONValue) -> ContextSlice? {
        guard var name = category["name"]?.stringValue else { return nil }
        let kind = category["kind"]?.stringValue
        let isDeferred = category["isDeferred"]?.boolValue == true || kind == "deferred"
        if name.hasSuffix(deferredSuffix) { name.removeLast(deferredSuffix.count) }

        let resolved: ContextCategory = kind == "free"
            ? .freeSpace
            : categories[name] ?? .other(name)
        return ContextSlice(category: resolved, tokens: category["tokens"]?.intValue ?? 0,
                            isDeferred: isDeferred)
    }

    private static func detail(_ category: ContextCategory, _ list: JSONValue?,
                               item: (JSONValue) -> ContextItem?) -> ContextDetail? {
        let items = list?.arrayValue?.compactMap(item) ?? []
        return items.isEmpty ? nil : ContextDetail(category: category, items: items)
    }

    private static func toolName(_ raw: String) -> String {
        guard raw.hasPrefix("mcp__") else { return raw }
        let rest = raw.dropFirst("mcp__".count)
        guard let separator = rest.range(of: "__") else { return raw }
        return String(rest[separator.upperBound...])
    }
}

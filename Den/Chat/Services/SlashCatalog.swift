import SwiftUI
import HarnessCore

enum SlashCatalog {
    static let compactCommand = CommandCatalog.compactCommand

    static func compact() -> SlashCommand {
        SlashCommand(id: "compact",
                     title: "Compactar conversa",
                     detail: "Resume o histórico para liberar contexto",
                     kind: .compact)
    }

    static func skills(from catalog: CommandCatalog) -> [SlashCommand] {
        catalog.skills.map {
            SlashCommand(id: $0, title: $0, detail: "Skill", kind: .skill)
        }
    }

    static func mcp(from catalog: CommandCatalog) -> [SlashCommand] {
        catalog.servers.flatMap { server -> [SlashCommand] in
            guard server.prompts.isEmpty else {
                return server.prompts.map { prompt in
                    SlashCommand(
                        id: prompt,
                        title: prompt.replacingOccurrences(of: "mcp__", with: "")
                            .replacingOccurrences(of: "__", with: " · "),
                        detail: server.name,
                        kind: .mcpPrompt(server: server.name))
                }
            }
            return [SlashCommand(id: "mcp:" + server.name,
                                 title: server.name,
                                 detail: label(for: server.status),
                                 kind: .mcpServer(status: server.status))]
        }
    }

    static func root(from catalog: CommandCatalog) -> [SlashCommand] {
        var items: [SlashCommand] = []
        if catalog.supportsCompact { items.append(compact()) }

        let skillCount = catalog.skills.count
        if skillCount > 0 {
            items.append(SlashCommand(
                id: "group:skills",
                title: SlashGroup.skills.title,
                detail: skillCount == 1 ? "1 habilidade" : "\(skillCount) habilidades",
                kind: .group(.skills, count: skillCount)))
        }

        let mcpCount = mcp(from: catalog).count
        if mcpCount > 0 {
            items.append(SlashCommand(
                id: "group:mcp",
                title: SlashGroup.mcp.title,
                detail: mcpCount == 1 ? "1 servidor" : "\(mcpCount) itens",
                kind: .group(.mcp, count: mcpCount)))
        }
        return items
    }

    static func label(for status: CommandCatalog.ServerStatus) -> String {
        switch status {
        case .connected: "conectado"
        case .needsAuth: "precisa autenticar"
        case .failed: "falhou ao conectar"
        case .pending: "conectando…"
        }
    }

    static func query(in prompt: String) -> String? {
        guard prompt.hasPrefix("/") else { return nil }
        let token = prompt.dropFirst()
        guard !token.contains(where: { $0.isNewline }) else { return nil }
        return String(token)
    }

    static func matches(_ query: String, in catalog: CommandCatalog,
                        group: SlashGroup?) -> [SlashCommand] {
        let pool: [SlashCommand] = switch group {
        case .skills: skills(from: catalog)
        case .mcp: mcp(from: catalog)
        case nil: query.isEmpty
            ? root(from: catalog)
            : (catalog.supportsCompact ? [compact()] : []) + skills(from: catalog)
                + mcp(from: catalog)
        }

        guard !query.isEmpty else { return pool }
        let needle = query.lowercased()
        let ranked = pool.compactMap { command -> (SlashCommand, Int)? in
            let title = command.title.lowercased()
            let id = command.id.lowercased()
            if title.hasPrefix(needle) || id.hasPrefix(needle) { return (command, 0) }
            if title.contains(needle) || id.contains(needle) { return (command, 1) }
            return nil
        }
        return ranked.sorted { $0.1 < $1.1 }.map(\.0)
    }
}

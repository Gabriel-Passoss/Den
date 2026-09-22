import SwiftUI
import HarnessCore

enum SlashGroup: String, Identifiable {
    case skills, mcp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skills: "Habilidades"
        case .mcp: "MCP"
        }
    }

    var icon: String {
        switch self {
        case .skills: "sparkles"
        case .mcp: "powerplug"
        }
    }

    var tint: Color {
        switch self {
        case .skills: .purple
        case .mcp: .teal
        }
    }
}

struct SlashCommand: Identifiable {
    enum Kind {
        case compact
        case group(SlashGroup, count: Int)
        case skill
        case mcpPrompt(server: String)
        case mcpServer(status: CommandCatalog.ServerStatus)
    }

    let id: String
    let title: String
    let detail: String
    let kind: Kind

    var command: String? {
        switch kind {
        case .compact: SlashCatalog.compactCommand
        case .skill, .mcpPrompt: "/" + id
        case .group, .mcpServer: nil
        }
    }

    var group: SlashGroup? {
        if case .group(let group, _) = kind { return group }
        return nil
    }

    var icon: String {
        switch kind {
        case .compact: "arrow.down.right.and.arrow.up.left"
        case .group(let group, _): group.icon
        case .skill: "sparkles"
        case .mcpPrompt: "bolt.horizontal"
        case .mcpServer(let status): status == .connected ? "powerplug" : "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch kind {
        case .compact: .blue
        case .group(let group, _): group.tint
        case .skill: .purple
        case .mcpPrompt: .teal
        case .mcpServer(let status): status == .connected ? .green : .orange
        }
    }
}

enum SlashCatalog {
    /// Compactar é ação de interface: o que fica na conversa é a fronteira
    /// devolvida pelo harness, não o eco do comando.
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

    /// Raiz: compactar e as duas gavetas. O conteúdo delas só aparece ao entrar.
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

    /// Sem grupo aberto e sem busca, mostra a raiz; com busca, procura em tudo.
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

struct SlashCommandList: View {
    let commands: [SlashCommand]
    let selection: Int
    let group: SlashGroup?
    var choose: (SlashCommand) -> Void
    var back: () -> Void

    /// A lista tem altura fixa por linha para caber num número exato de itens:
    /// o resto rola, em vez de ser cortado sem aviso.
    private static let rowHeight: CGFloat = 22
    private static let rowSpacing: CGFloat = 1
    private static let visibleRows = 8

    private var listHeight: CGFloat {
        let rows = CGFloat(min(commands.count, Self.visibleRows))
        return rows * Self.rowHeight + max(rows - 1, 0) * Self.rowSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let group {
                Button(action: back) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text(group.title)
                            .font(.system(size: 10, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Voltar (Esc)")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
                        rows
                    }
                }
                .frame(height: listHeight)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: selection) { _, index in
                    guard commands.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(commands[index].id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
            let isSelected = index == selection
            HStack(spacing: 7) {
                Image(systemName: command.icon)
                    .font(.system(size: 10))
                    .frame(width: 14)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white)
                                                : AnyShapeStyle(command.tint))
                Text(command.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(command.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8))
                                                : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if command.group != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8))
                                                    : AnyShapeStyle(.tertiary))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(isSelected ? AnyShapeStyle(Color.accentColor)
                                   : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
            .onTapGesture { choose(command) }
            .id(command.id)
        }
    }
}

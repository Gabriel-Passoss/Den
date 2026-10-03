import SwiftUI
import HarnessCore

struct ContextPanel: View {
    let chat: ChatModel

    private static let maxListHeight: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let usage = chat.contextUsage {
                ContextBar(usage: usage)
                FittedScroll(maxHeight: Self.maxListHeight) {
                    VStack(alignment: .leading, spacing: 12) {
                        categories(of: usage)
                        if !usage.details.isEmpty {
                            Rectangle().fill(Theme.border).frame(height: 1)
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(usage.details, id: \.category) { detail in
                                    DetailGroup(detail: detail)
                                }
                            }
                        }
                    }
                }
                if usage.isEstimate {
                    footnote("A divisão é estimada a partir da conversa; o total vem do \(chat.harnessName).")
                }
                if !chat.isLive {
                    footnote("Última medição desta sessão. Atualiza na próxima mensagem.")
                }
            } else {
                Text(chat.isLive
                     ? "O \(chat.harnessName) ainda não informou o uso do contexto."
                     : "O detalhamento aparece depois da próxima mensagem desta sessão.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(16)
        .frame(width: 340)
        .foregroundStyle(Theme.text)
        .background(Theme.raised)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Janela de contexto")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let window = chat.contextUsage?.windowTokens ?? chat.contextWindow {
                Text(ContextFormat.summary(used: chat.contextUsage?.usedTokens ?? chat.contextTokens,
                                           window: window))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func categories(of usage: ContextUsage) -> some View {
        let ordered = Self.ordered(usage.slices)
        let deferred = ordered.filter(\.isDeferred)
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(ordered.filter { !$0.isDeferred }.enumerated()), id: \.offset) { _, slice in
                CategoryRow(slice: slice, window: usage.windowTokens)
            }
            if !deferred.isEmpty {
                Text("Carregadas sob demanda, fora da janela até serem usadas")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
                ForEach(Array(deferred.enumerated()), id: \.offset) { _, slice in
                    CategoryRow(slice: slice, window: usage.windowTokens)
                }
            }
        }
    }

    static func ordered(_ slices: [ContextSlice]) -> [ContextSlice] {
        let filled = slices.filter {
            !$0.isDeferred && $0.category != .freeSpace && $0.category != .autocompactBuffer
        }
        return filled.sorted { $0.tokens > $1.tokens }
            + slices.filter { !$0.isDeferred && $0.category == .autocompactBuffer }
            + slices.filter { !$0.isDeferred && $0.category == .freeSpace }
            + slices.filter(\.isDeferred)
    }
}

private struct ContextBar: View {
    let usage: ContextUsage

    var body: some View {
        let filled = ContextPanel.ordered(usage.slices)
            .filter { !$0.isDeferred && $0.category != .freeSpace && $0.tokens > 0 }
        let total = max(usage.windowTokens, filled.reduce(0) { $0 + $1.tokens }, 1)

        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(filled.enumerated()), id: \.offset) { _, slice in
                    Rectangle()
                        .fill(slice.category.color)
                        .frame(width: max(2, proxy.size.width * CGFloat(slice.tokens) / CGFloat(total)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(Theme.borderStrong)
        .clipShape(Capsule())
    }
}

private struct CategoryRow: View {
    let slice: ContextSlice
    let window: Int

    var body: some View {
        HStack(spacing: 8) {
            Swatch(category: slice.category, isDeferred: slice.isDeferred)
            Text(slice.category.label)
                .foregroundStyle(slice.isDeferred ? Theme.textTertiary : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(ContextFormat.tokens(slice.tokens))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Text(slice.isDeferred || window == 0
                 ? "—"
                 : ContextFormat.percent(Double(slice.tokens) / Double(window)))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 12.5))
    }
}

private struct Swatch: View {
    let category: ContextCategory
    let isDeferred: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(isDeferred ? Theme.borderControl
                  : category == .freeSpace ? .clear
                  : category.color)
            .overlay {
                if category == .freeSpace {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Theme.textFaint, lineWidth: 1)
                }
            }
            .frame(width: 10, height: 10)
    }
}

private struct Disclosure<Label: View, Content: View>: View {
    @ViewBuilder var label: () -> Label
    @ViewBuilder var content: () -> Content

    @State private var isOpen = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 10)
                    label()
                }
                .padding(.horizontal, 6)
                .frame(height: 26)
                .hoverFill(hovering, radius: 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            if isOpen {
                content()
                    .padding(.leading, 22)
                    .padding(.trailing, 6)
                    .padding(.bottom, 4)
            }
        }
    }
}

private struct DetailGroup: View {
    let detail: ContextDetail

    var body: some View {
        Disclosure {
            ItemRow(name: detail.category.label, tokens: detail.tokens,
                    count: detail.items.count)
                .font(.system(size: 12.5, weight: .medium))
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                if detail.category == .mcpTools {
                    ForEach(servers, id: \.name) { server in
                        Disclosure {
                            ItemRow(name: server.name, tokens: server.tokens,
                                    count: server.items.count)
                        } content: {
                            items(server.items)
                        }
                    }
                } else {
                    items(detail.items)
                }
            }
        }
        .font(.system(size: 12))
    }

    private func items(_ list: [ContextItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.sorted { $0.tokens > $1.tokens }.enumerated()), id: \.offset) { _, item in
                ItemRow(name: displayName(of: item), tokens: item.tokens,
                        isDeferred: item.isDeferred)
                    .help(item.isDeferred ? "\(item.name) · carregada sob demanda" : item.name)
            }
        }
    }

    private func displayName(of item: ContextItem) -> String {
        detail.category == .memoryFiles
            ? (item.name as NSString).abbreviatingWithTildeInPath
            : item.name
    }

    private var servers: [(name: String, items: [ContextItem], tokens: Int)] {
        Dictionary(grouping: detail.items) { $0.group ?? "?" }
            .map { (name: $0.key, items: $0.value, tokens: $0.value.reduce(0) { $0 + $1.tokens }) }
            .sorted { $0.tokens > $1.tokens }
    }
}

private struct ItemRow: View {
    let name: String
    let tokens: Int
    var count: Int?
    var isDeferred = false

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .foregroundStyle(isDeferred ? Theme.textTertiary : Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(ContextFormat.tokens(tokens))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            if let count {
                Text(String(count))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }
}

extension ContextCategory {
    var label: String {
        switch self {
        case .systemPrompt: "Prompt de sistema"
        case .systemTools: "Ferramentas do sistema"
        case .mcpTools: "Ferramentas MCP"
        case .customAgents: "Agentes"
        case .memoryFiles: "Arquivos de memória"
        case .skills: "Skills"
        case .messages: "Mensagens"
        case .toolActivity: "Ferramentas e resultados"
        case .systemAndTools: "Sistema e ferramentas"
        case .autocompactBuffer: "Reserva da autocompactação"
        case .freeSpace: "Espaço livre"
        case .other(let name): name
        }
    }

    var color: Color {
        switch self {
        case .messages: Color(hex: 0x93AEE8)
        case .mcpTools, .toolActivity: Color(hex: 0xE8906F)
        case .systemTools, .systemAndTools: Color(hex: 0x7FCB92)
        case .skills: Color(hex: 0xE0B45F)
        case .customAgents: Color(hex: 0xC3AEF0)
        case .memoryFiles: Color(hex: 0x8FC7C0)
        case .autocompactBuffer: Color(hex: 0x5E5A52)
        case .freeSpace: .clear
        case .systemPrompt, .other: Color(hex: 0xA8A398)
        }
    }
}

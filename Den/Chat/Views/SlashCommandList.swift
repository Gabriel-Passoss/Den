import SwiftUI

struct SlashCommandList: View {
    let commands: [SlashCommand]
    let selection: Int
    let group: SlashGroup?
    var choose: (SlashCommand) -> Void
    var back: () -> Void

    private static let rowHeight: CGFloat = 28
    private static let rowSpacing: CGFloat = 1
    private static let visibleRows = 8

    private var listHeight: CGFloat {
        let rows = CGFloat(min(commands.count, Self.visibleRows))
        return rows * Self.rowHeight + max(rows - 1, 0) * Self.rowSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let group {
                BackButton(title: group.title, back: back)
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

    private var rows: some View {
        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
            let isSelected = index == selection
            HStack(spacing: 7) {
                Image(systemName: command.icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent)
                                                : AnyShapeStyle(command.tint))
                Text(command.title)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Text(command.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.textSecondary : Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if command.group != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background(isSelected ? Theme.hoverRaised : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)
            .contentShape(Rectangle())
            .onTapGesture { choose(command) }
            .id(command.id)
        }
    }
}

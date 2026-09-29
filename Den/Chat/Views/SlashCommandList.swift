import SwiftUI
import HarnessCore

struct SlashCommandList: View {
    let commands: [SlashCommand]
    let selection: Int
    let group: SlashGroup?
    var choose: (SlashCommand) -> Void
    var back: () -> Void

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

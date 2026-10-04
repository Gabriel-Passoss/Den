import SwiftUI

enum DenMenuIcon {
    case symbol(String, Color)
    case image(Image)
}

struct DenMenuItem: Identifiable {
    let id: String
    var title: String
    var icon: DenMenuIcon?
    var isSelected: Bool
    var isEnabled: Bool
    var isDestructive: Bool
    var children: [DenMenuSection]
    var action: () -> Void

    init(id: String,
         title: String,
         icon: DenMenuIcon? = nil,
         isSelected: Bool = false,
         isEnabled: Bool = true,
         isDestructive: Bool = false,
         children: [DenMenuSection] = [],
         action: @escaping () -> Void = {}) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.children = children
        self.action = action
    }
}

struct DenMenuSection: Identifiable {
    let id: String
    var header: String?
    var items: [DenMenuItem]

    init(id: String = "main", header: String? = nil, items: [DenMenuItem]) {
        self.id = id
        self.header = header
        self.items = items
    }

    static func showsIcons(in sections: [DenMenuSection]) -> Bool {
        sections.contains { $0.items.contains { $0.icon != nil } }
    }
}

struct DenMenuChip<Label: View>: View {
    var sections: [DenMenuSection]
    var bordered = false
    var radius: CGFloat = 8
    @ViewBuilder var label: () -> Label

    @State private var isOpen = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOpen.toggle() } label: { label() }
            .buttonStyle(.plain)
            .fixedSize()
            .chipSurface(bordered: bordered, radius: radius, hovering: hovering, open: isOpen)
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovering = isEnabled && $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .popover(isPresented: $isOpen, arrowEdge: .top) {
                DenMenuList(sections: sections) { isOpen = false }
                    .presentationBackground(Theme.raised)
                    .environment(\.colorScheme, .dark)
            }
    }
}

struct DenMenuList: View {
    let sections: [DenMenuSection]
    var dismiss: () -> Void = {}

    @State private var path: [DenMenuItem] = []

    private static let maxHeight: CGFloat = 360

    private var shown: [DenMenuSection] { path.last?.children ?? sections }

    private var showsIcons: Bool { DenMenuSection.showsIcons(in: shown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let parent = path.last {
                back(to: parent)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, section in
                        if index > 0, section.header == nil {
                            Rectangle()
                                .fill(Theme.border)
                                .frame(height: 1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        if let header = section.header {
                            Text(header)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.top, index == 0 ? 2 : 7)
                                .padding(.bottom, 2)
                        }
                        ForEach(section.items) { item in
                            DenMenuRow(item: item, showsIcon: showsIcons) { choose(item) }
                        }
                    }
                }
            }
            .frame(maxHeight: Self.maxHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(6)
        .frame(minWidth: 190, alignment: .leading)
        .accessibilityIdentifier("den-menu")
        .onDisappear { path = [] }
    }

    private func back(to parent: DenMenuItem) -> some View {
        BackButton(title: parent.title) {
            withAnimation(.easeOut(duration: 0.12)) { _ = path.popLast() }
        }
        .help("Voltar")
    }

    private func choose(_ item: DenMenuItem) {
        guard item.children.isEmpty else {
            withAnimation(.easeOut(duration: 0.12)) { path.append(item) }
            return
        }
        item.action()
        dismiss()
    }
}

private struct DenMenuRow: View {
    let item: DenMenuItem
    var showsIcon: Bool
    var choose: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 7) {
                if showsIcon {
                    icon.frame(width: 16, height: 16)
                }
                Text(item.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(hovering ? Theme.hoverRaised : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(item.isDestructive ? Theme.removed
                             : item.isSelected ? Theme.text : Theme.textSecondary)
            .opacity(item.isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .onHover { hovering = item.isEnabled && $0 }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.icon {
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        case .image(let image):
            image.resizable().frame(width: 16, height: 16)
        case nil:
            Color.clear
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if !item.children.isEmpty {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        } else if item.isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
    }
}

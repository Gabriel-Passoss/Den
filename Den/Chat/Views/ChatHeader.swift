import SwiftUI

struct ChatHeader: View {
    let chat: ChatModel
    var runActive: Bool

    @AppStorage(InspectorPane.storageKey) private var pane: InspectorPane = .closed
    @State private var lastOpenPane: InspectorPane = .changes
    @Environment(\.chrome) private var chrome

    var body: some View {
        TopBar(leadingInset: chrome.leadingInset + (chrome.sidebarHidden ? 8 : 20)) {
            SidebarToggle()
            ViewThatFits(in: .horizontal) {
                breadcrumb(folder: true, branch: true)
                breadcrumb(folder: false, branch: true)
                breadcrumb(folder: false, branch: false)
            }
            Spacer(minLength: 12)
            HarnessSwitcher(chat: chat)
            panelToggle
        }
        .onKeyboardShortcut("0", modifiers: [.option, .command]) { toggle(.changes) }
        .onKeyboardShortcut("9", modifiers: [.option, .command]) { toggle(.run) }
        .onKeyboardShortcut("8", modifiers: [.option, .command]) { toggle(.memory) }
        .onChange(of: pane) {
            if pane != .closed { lastOpenPane = pane }
        }
    }

    private func breadcrumb(folder: Bool, branch: Bool) -> some View {
        HStack(spacing: 8) {
            if folder {
                Text(chat.workingDirectory.lastPathComponent)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .help(chat.workingDirectory.path)
                Text("/")
                    .foregroundStyle(Theme.textFaint)
            }
            Text(chat.title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
            if branch, let name = chat.branch {
                BranchPill(branch: name)
            }
        }
        .font(.system(size: 14))
    }

    private var panelToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                pane = pane == .closed ? lastOpenPane : .closed
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14))
                .foregroundStyle(pane == .closed ? Theme.textSecondary : Theme.text)
                .iconLabel(size: 32)
                .overlay(alignment: .topTrailing) {
                    if runActive {
                        Circle()
                            .fill(Theme.added)
                            .frame(width: 7, height: 7)
                            .offset(x: -5, y: 5)
                    }
                }
        }
        .buttonStyle(DenButtonStyle(kind: .secondary))
        .help(pane == .closed ? "Mostrar alterações, execução e memória (⌥⌘0 / ⌥⌘9 / ⌥⌘8)"
                              : "Ocultar painel")
        .accessibilityLabel(pane == .closed ? "Mostrar painel" : "Ocultar painel")
    }

    private func toggle(_ target: InspectorPane) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if pane == target {
                pane = .closed
            } else {
                pane = target
                lastOpenPane = target
            }
        }
    }
}

struct BranchPill: View {
    let branch: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .semibold))
            Text(branch)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .frame(maxWidth: 220)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
        .help(branch)
    }
}

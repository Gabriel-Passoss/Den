import SwiftUI

struct InspectorView: View {
    @Binding var pane: InspectorPane
    let gitChanges: GitChangesModel
    let directory: URL
    let runRoot: URL
    let runActive: Bool
    let chat: ChatModel

    @State private var shown: InspectorPane = .changes

    var body: some View {
        VStack(spacing: 0) {
            TopBar(leadingInset: 12) {
                tab(.changes, title: "Alterações", icon: "plus.forwardslash.minus") {
                    if gitChanges.changeCount > 0 {
                        Text("\(gitChanges.changeCount)")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.hoverRaised, in: Capsule())
                    }
                }
                tab(.run, title: "Execução", icon: "terminal") {
                    if runActive {
                        Circle().fill(Theme.added).frame(width: 7, height: 7)
                            .accessibilityLabel("Em execução")
                    }
                }
                if chat.memory != nil {
                    tab(.memory, title: "Memória", icon: "brain") { EmptyView() }
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { pane = .closed }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .iconLabel()
                }
                .buttonStyle(.denGhost)
                .help("Recolher painel (\(shown.shortcut))")
                .accessibilityLabel("Fechar painel")
            }

            Group {
                switch shown {
                case .run:
                    RunPanel(root: runRoot)
                case .memory:
                    if let memory = chat.memory { MemoryPanel(memory: memory, chat: chat) }
                case .changes, .closed:
                    GitChangesPanel(model: gitChanges, directory: directory)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.panel)
        .onChange(of: pane, initial: true) {
            if pane != .closed { shown = pane }
        }
    }

    private func tab(_ target: InspectorPane, title: String, icon: String,
                     @ViewBuilder badge: () -> some View) -> some View {
        let selected = shown == target
        return Button {
            pane = target
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                badge()
            }
            .foregroundStyle(selected ? Theme.text : Theme.textTertiary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .hoverFill(selected: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

import SwiftUI

struct InspectorView: View {
    @Binding var pane: InspectorPane
    let gitChanges: GitChangesModel
    let directory: URL
    let runRoot: URL
    let runActive: Bool

    @State private var shown: InspectorPane

    init(pane: Binding<InspectorPane>, gitChanges: GitChangesModel, directory: URL,
         runRoot: URL, runActive: Bool) {
        _pane = pane
        self.gitChanges = gitChanges
        self.directory = directory
        self.runRoot = runRoot
        self.runActive = runActive
        _shown = State(initialValue: pane.wrappedValue.shown(after: .changes))
    }

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
                case .changes, .closed:
                    GitChangesPanel(model: gitChanges, directory: directory)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.panel)
        .onChange(of: pane) {
            shown = pane.shown(after: shown)
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

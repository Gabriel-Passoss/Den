import AppKit
import SwiftUI

struct RunPanel: View {
    let root: URL

    @Environment(RunManager.self) private var runs
    @Environment(RunConfigurationsModel.self) private var configurations

    @State private var selectedID: UUID?
    @State private var editor: RunConfigurationSheet.Target?
    @State private var followRequest = 0

    private var items: [RunConfiguration] { configurations.configurations(in: root) }

    private var shownID: UUID? {
        if let selectedID, items.contains(where: { $0.id == selectedID }) { return selectedID }
        return items.first { runs.isActive($0.id) }?.id ?? items.first?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if items.isEmpty {
                emptyState
            } else {
                list
                terminal
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $editor) { target in
            RunConfigurationSheet(root: root, target: target) { selectedID = $0 }
                .environment(configurations)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            Text(root.lastPathComponent)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(root.path)
            Spacer()
            Button { editor = .new } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .iconLabel(size: 26)
            }
            .buttonStyle(.denGhost(radius: 7))
            .help("Nova configuração")
            .accessibilityLabel("Nova configuração")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    // MARK: - Content

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 24))
                .foregroundStyle(Theme.textFaint)
            Text("Nenhuma configuração neste projeto")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
            Button { editor = .new } label: {
                Text("Configurar…").pillLabel()
            }
            .buttonStyle(.denSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(items) { item in
                    RunConfigurationRow(
                        configuration: item,
                        instance: runs.instance(for: item.id),
                        isSelected: item.id == shownID,
                        start: { run(item) },
                        stop: { Task { await runs.stop(item.id) } })
                    .onTapGesture { selectedID = item.id }
                    .denContextMenu([DenMenuSection(items: [
                        DenMenuItem(id: "edit", title: "Editar…") { editor = .edit(item) },
                        DenMenuItem(id: "remove", title: "Remover",
                                    isDestructive: true) { remove(item) },
                    ])])
                }
            }
            .padding(6)
        }
        .frame(height: min(CGFloat(items.count) * 34 + 12, 220))
    }

    @ViewBuilder
    private var terminal: some View {
        if let id = shownID, let item = items.first(where: { $0.id == id }) {
            let instance = runs.instance(for: id)
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(RunConfigurationRow.color(for: instance?.state.indicator ?? .idle))
                            .frame(width: 7, height: 7)
                        Text(item.name)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.terminalBar, in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    if let instance {
                        terminalButton("doc.on.doc", label: "Copiar o log inteiro") { copy(instance) }
                        terminalButton("eraser", label: "Limpar o log") { instance.clearLog() }
                        terminalButton("arrow.down.to.line", label: "Ir para o fim do log") {
                            followRequest += 1
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 40)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.terminalBar).frame(height: 1)
                }
                if let instance {
                    LogView(instance: instance, followRequest: followRequest)
                        .padding(.horizontal, 6)
                } else {
                    VStack(spacing: 6) {
                        Text(item.command?.command ?? item.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text("Clique em \(Image(systemName: "play.fill")) para executar")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.terminal)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }

    private func terminalButton(_ symbol: String, label: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
                .iconLabel(size: 28)
        }
        .buttonStyle(.denGhost(radius: 6))
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func run(_ item: RunConfiguration) {
        selectedID = item.id
        followRequest += 1
        Task { await runs.start(item, in: root) }
    }

    private func remove(_ item: RunConfiguration) {
        Task {
            await runs.stop(item.id)
            runs.forget(item.id)
            configurations.remove(item.id, from: root)
        }
    }

    private func copy(_ instance: RunInstance) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(instance.log.plainText, forType: .string)
    }
}

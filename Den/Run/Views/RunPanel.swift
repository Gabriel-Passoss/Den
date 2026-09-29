import AppKit
import SwiftUI

struct RunPanel: View {
    let root: URL
    var close: (() -> Void)?

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
            Divider()
            if items.isEmpty {
                emptyState
            } else {
                list
                Divider()
                logSection
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
        HStack(spacing: 7) {
            Text("Execução")
                .font(.system(size: 12, weight: .semibold))
            Text(root.lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(root.path)
            Spacer()
            Button { editor = .new } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Nova configuração")
            .accessibilityLabel("Nova configuração")
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Recolher painel (⌥⌘9)")
                .accessibilityLabel("Recolher painel de execução")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Content

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("Nenhuma configuração neste projeto")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Configurar…") { editor = .new }
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
                    .contextMenu {
                        Button("Editar…") { editor = .edit(item) }
                        Button("Remover", role: .destructive) { remove(item) }
                    }
                }
            }
            .padding(6)
        }
        .frame(height: min(CGFloat(items.count) * 32 + 12, 220))
    }

    @ViewBuilder
    private var logSection: some View {
        if let id = shownID, let item = items.first(where: { $0.id == id }) {
            let instance = runs.instance(for: id)
            HStack(spacing: 10) {
                Text(item.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let instance {
                    Button("Copiar") { copy(instance) }
                        .help("Copiar o log inteiro")
                    Button("Limpar") { instance.clearLog() }
                        .help("Limpar o log")
                    Button { followRequest += 1 } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .help("Ir para o fim")
                    .accessibilityLabel("Ir para o fim do log")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            if let instance {
                LogView(instance: instance, followRequest: followRequest)
            } else {
                Text("Clique em \(Image(systemName: "play.fill")) para executar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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

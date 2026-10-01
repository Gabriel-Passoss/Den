import SwiftUI

struct RunConfigurationSheet: View {
    enum Target: Identifiable {
        case new
        case edit(RunConfiguration)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let configuration): configuration.id.uuidString
            }
        }
    }

    let root: URL
    let target: Target
    var onSave: (UUID) -> Void

    @Environment(RunConfigurationsModel.self) private var configurations
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var command = ""
    @State private var directory = ""
    @State private var attempted = false

    private var editingID: UUID? {
        if case .edit(let configuration) = target { return configuration.id }
        return nil
    }

    private var nameProblem: RunConfigurationsModel.NameProblem? {
        configurations.nameProblem(for: name, excluding: editingID, in: root)
    }

    private var commandMissing: Bool {
        command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editingID == nil ? "Nova configuração" : "Editar configuração")
                .font(.system(size: 17, weight: .semibold))

            field("Nome") {
                TextField("Nome", text: $name, prompt: Text("API"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .modifier(FieldChrome())
                if attempted, let nameProblem {
                    message(nameProblem == .empty ? "Dê um nome à configuração"
                                                  : "Já existe uma configuração com esse nome")
                }
            }

            field("Comando") {
                TextField("Comando", text: $command, prompt: Text("npm run dev"), axis: .vertical)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(.system(size: 13, design: .monospaced))
                    .modifier(FieldChrome())
                if attempted, commandMissing {
                    message("Informe o comando")
                }
            }

            field("Pasta") {
                RunFolderPicker(root: root, selection: $directory)
                Text("O comando roda no seu shell, a partir da pasta escolhida.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 8) {
                Spacer()
                Button(role: .cancel) { dismiss() } label: {
                    Text("Cancelar").pillLabel()
                }
                .buttonStyle(.denSecondary)
                .keyboardShortcut(.cancelAction)
                Button { save() } label: {
                    Text(editingID == nil ? "Criar" : "Salvar").pillLabel()
                }
                .buttonStyle(.denPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.panel)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .onAppear(perform: load)
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            content()
        }
    }

    private struct FieldChrome: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.borderStrong, lineWidth: 1))
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.removed)
    }

    private func load() {
        guard case .edit(let configuration) = target else { return }
        name = configuration.name
        command = configuration.command?.command ?? ""
        directory = configuration.command?.workingDirectory ?? ""
    }

    private func save() {
        attempted = true
        guard nameProblem == nil, !commandMissing else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = directory.trimmingCharacters(in: .whitespaces)
        switch target {
        case .new:
            let created = RunConfiguration(name: trimmedName, kind: .command(CommandSpec(
                command: trimmedCommand, workingDirectory: trimmedDirectory, environment: [])))
            configurations.add(created, to: root)
            onSave(created.id)
        case .edit(let original):
            var updated = original
            updated.name = trimmedName
            updated.kind = .command(CommandSpec(
                command: trimmedCommand, workingDirectory: trimmedDirectory,
                environment: original.command?.environment ?? []))
            configurations.update(updated, in: root)
            onSave(updated.id)
        }
        dismiss()
    }
}

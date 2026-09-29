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
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Nome", text: $name, prompt: Text("API"))
                    if attempted, let nameProblem {
                        message(nameProblem == .empty ? "Dê um nome à configuração"
                                                      : "Já existe uma configuração com esse nome",
                                color: .red)
                    }
                    TextField("Comando", text: $command, prompt: Text("npm run dev"), axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 12, design: .monospaced))
                    if attempted, commandMissing {
                        message("Informe o comando", color: .red)
                    }
                } header: {
                    Text(editingID == nil ? "Nova configuração" : "Editar configuração")
                }
                Section {
                    RunFolderPicker(root: root, selection: $directory)
                } header: {
                    Text("Pasta")
                } footer: {
                    Text("O comando roda no seu shell, a partir da pasta escolhida.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editingID == nil ? "Criar" : "Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
        .onAppear(perform: load)
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
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

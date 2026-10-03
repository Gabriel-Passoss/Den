import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GitHubSettings()
                .tabItem { Label("GitHub", systemImage: "arrow.triangle.pull") }
        }
        .frame(width: 520)
    }
}

private struct GitHubSettings: View {
    @Environment(PullRequestMonitor.self) private var monitor
    @AppStorage(GitHubCLI.pathKey) private var path = ""

    var body: some View {
        Form {
            Section("GitHub CLI") {
                LabeledContent("Caminho") {
                    HStack {
                        TextField("Caminho", text: $path, prompt: Text("Detectar automaticamente"))
                            .labelsHidden()
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit(apply)
                        Button("Escolher…", action: choose)
                    }
                }
                LabeledContent("Estado") {
                    HStack {
                        stateLabel
                        Spacer()
                        Button("Detectar de novo") {
                            path = ""
                            apply()
                        }
                    }
                }
                Text("Vazio, o Den procura o gh no PATH do seu shell e em /opt/homebrew/bin e /usr/local/bin.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await monitor.checkGh() }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch monitor.cli {
        case .ready(_, let version):
            Label("gh \(version) · logado em github.com", systemImage: "checkmark")
                .foregroundStyle(.green)
        case .missing:
            Label("Não encontrado", systemImage: "xmark").foregroundStyle(.red)
        case .notLoggedIn(let host):
            Label("Sem login em \(host)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .unknown:
            Text("Verificando…").foregroundStyle(.secondary)
        }
    }

    private func apply() {
        Task { await monitor.reconfigure(path: path.isEmpty ? nil : path) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Usar"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard await GitHubCLI.version(at: url.path) != nil else { return }
            path = url.path
            await monitor.reconfigure(path: url.path)
        }
    }
}

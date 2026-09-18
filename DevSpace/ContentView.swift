import SwiftUI
import HarnessCore

struct ContentView: View {
    @State private var model = CockpitModel()
    /// Quais blocos recolhidos o usuário abriu.
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            if let pending = model.pending {
                Divider()
                permissionBanner(pending)
            }
            Divider()
            composer
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.status)
                    .font(.system(size: 12, weight: .medium))
                Text(model.workingDirectory.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Button("Pasta…") { chooseDirectory() }
                .disabled(model.isRunning)

            if model.isRunning {
                Button("Parar") { Task { await model.stop() } }
            } else {
                Button("Iniciar") { Task { await model.start() } }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.blocks) { block in
                        switch block {
                        case .line(let line):
                            row(line).id(line.id)
                        case .collapsed(let id, let lines):
                            unrecognizedBlock(id: id, lines: lines).id(id)
                        }
                    }
                    if !model.streaming.isEmpty {
                        // O efêmero, pintado enquanto chega. Some quando o
                        // turno consolida e vira uma linha de verdade.
                        bubble(label: "claude", color: .primary, text: model.streaming)
                            .id("streaming")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.lines.count) { scrollToEnd(proxy) }
            .animation(.easeInOut(duration: 0.15), value: expanded)
            .onChange(of: model.streaming) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if !model.streaming.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = model.lines.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func row(_ line: CockpitModel.Line) -> some View {
        switch line.role {
        case .user:
            bubble(label: "você", color: .blue, text: line.text)
        case .assistant:
            bubble(label: "claude", color: .primary, text: line.text)
        case .thinking:
            bubble(label: "raciocínio", color: .purple, text: line.text, dimmed: true)
        case .tool:
            monoline(symbol: "terminal", color: .orange, text: line.text)
        case .toolResult:
            monoline(symbol: "arrow.turn.down.right", color: .secondary, text: line.text)
        case .notice:
            monoline(symbol: "info.circle", color: .secondary, text: line.text)
        case .turn:
            monoline(symbol: "checkmark.circle", color: .green, text: line.text)
        case .unknown:
            monoline(symbol: "questionmark.diamond", color: .pink, text: line.text)
        }
    }

    /// Eventos que este binário não sabe ler, preservados e quietos.
    ///
    /// Spec §5.4: nada é perdido e nada vira erro — o conteúdo está aqui,
    /// a um clique. O que ele não faz é competir com a conversa.
    @ViewBuilder
    private func unrecognizedBlock(id: UUID, lines: [CockpitModel.Line]) -> some View {
        let isOpen = expanded.contains(id)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if isOpen { expanded.remove(id) } else { expanded.insert(id) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(lines.count == 1
                         ? "1 evento não reconhecido"
                         : "\(lines.count) eventos não reconhecidos")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 13)
            }
        }
    }

    private func bubble(label: String, color: Color, text: String,
                        dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(dimmed ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func monoline(symbol: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Permissão

    private func permissionBanner(_ request: PermissionRequest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Permitir \(request.displayName ?? request.toolName)?")
                    .font(.system(size: 12, weight: .semibold))
                if let description = request.description {
                    Text(description).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Negar") { Task { await model.resolve(allow: false) } }
            Button("Permitir") { Task { await model.resolve(allow: true) } }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Peça alguma coisa…", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(size: 13))
                .onSubmit { Task { await model.send() } }
                .disabled(!model.isRunning)

            if model.isBusy { ProgressView().controlSize(.small) }

            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .disabled(!model.isRunning || model.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = model.workingDirectory
        if panel.runModal() == .OK, let url = panel.url {
            model.workingDirectory = url
        }
    }
}

#Preview {
    ContentView()
}

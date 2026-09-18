import SwiftUI
import HarnessCore

/// A conversa: o que já aconteceu, o que está chegando, e o que se digita.
struct ChatView: View {
    @Bindable var cockpit: CockpitModel
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            if let pending = cockpit.pending {
                permissionCard(pending)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }
            composer
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cockpit.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(cockpit.workingDirectory.lastPathComponent
                     + (cockpit.status.isEmpty ? "" : " · \(cockpit.status)"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if cockpit.isLive {
                Button("Parar") { Task { await cockpit.stop() } }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(cockpit.blocks) { block in
                        switch block {
                        case .line(let line):
                            row(line).id(line.id)
                        case .collapsed(let id, let lines):
                            unrecognized(id: id, lines: lines).id(id)
                        }
                    }
                    if !cockpit.streaming.isEmpty {
                        assistantText(cockpit.streaming).id("streaming")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: cockpit.lines.count) { scrollToEnd(proxy) }
            .onChange(of: cockpit.streaming) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if !cockpit.streaming.isEmpty { proxy.scrollTo("streaming", anchor: .bottom) }
            else if let last = cockpit.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func row(_ line: CockpitModel.Line) -> some View {
        switch line.role {
        case .user:
            userBubble(line)

        case .assistant:
            assistantText(line.text)

        case .thinking:
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "brain").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text(line.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .italic()
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .tool:
            chip(icon: icon(for: line.verb), text: line.text, mono: true)

        case .toolResult:
            chip(icon: "arrow.turn.down.right", text: line.text, mono: true, dim: true)

        case .notice:
            chip(icon: "info.circle", text: line.text, mono: false, dim: true)

        case .unknown:
            EmptyView()
        }
    }

    /// A mensagem do usuário: encostada à direita, contida, com a hora dentro
    /// do balão.
    ///
    /// O `Spacer` com folga mínima é o que impede o balão de esticar até a
    /// borda: ele encolhe até o conteúdo e para. E a hora fica alinhada pela
    /// ÚLTIMA linha de base do texto, não pelo centro — é isso que a põe ao pé
    /// do balão quando a mensagem tem várias linhas, em vez de flutuando no
    /// meio da altura.
    private func userBubble(_ line: CockpitModel.Line) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 64)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(line.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.22),
                        in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private func assistantText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(icon: String, text: String, mono: Bool, dim: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(dim ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .frame(width: 13)
            Text(text)
                .font(.system(size: 11, design: mono ? .monospaced : .default))
                .foregroundStyle(dim ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    /// O verbo canônico vira ícone. É o vocabulário da spec §4.1 aparecendo:
    /// a mesma forma serve a qualquer harness, porque o verbo é o mesmo.
    private func icon(for verb: CanonicalTool?) -> String {
        switch verb {
        case .read: "doc.text"
        case .write: "square.and.pencil"
        case .edit: "pencil"
        case .execute: "terminal"
        case .search: "magnifyingglass"
        case .fetch: "globe"
        case nil: "wrench.and.screwdriver"
        }
    }

    /// Spec §5.4: preservado e exibido, a um clique — sem competir com a conversa.
    @ViewBuilder
    private func unrecognized(id: UUID, lines: [CockpitModel.Line]) -> some View {
        let isOpen = expanded.contains(id)
        VStack(alignment: .leading, spacing: 5) {
            Button {
                if isOpen { expanded.remove(id) } else { expanded.insert(id) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                    Text(lines.count == 1 ? "1 evento não reconhecido"
                                          : "\(lines.count) eventos não reconhecidos")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)

            if isOpen {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 12)
            }
        }
    }

    // MARK: - Permissão

    private func permissionCard(_ request: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("Permissão necessária")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text("Claude quer usar \(request.displayName ?? request.toolName).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let detail = detail(of: request) {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Negar") { Task { await cockpit.resolve(allow: false) } }
                Button("Permitir") { Task { await cockpit.resolve(allow: true) } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func detail(of request: PermissionRequest) -> String? {
        request.input["command"]?.stringValue
        ?? request.input["file_path"]?.stringValue
        ?? request.description
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 7) {
            TextField("Peça uma alteração…", text: $cockpit.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.system(size: 13))
                .onSubmit { Task { await cockpit.send() } }

            HStack(spacing: 8) {
                if !cockpit.model.isEmpty {
                    Text(cockpit.model)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.quaternary.opacity(0.4), in: Capsule())
                }
                if cockpit.isBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("trabalhando").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if cockpit.pending != nil {
                    Text("aguardando você").font(.system(size: 10)).foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    Task { await cockpit.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 19))
                }
                .buttonStyle(.plain)
                .disabled(cockpit.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
    }
}

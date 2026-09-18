import SwiftUI
import HarnessCore
import ClaudeHarness

struct ChatView: View {
    @Bindable var cockpit: CockpitModel
    @State private var expanded: Set<UUID> = []
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if let pending = cockpit.pending {
                permissionCard(pending)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }
            composer
        }

        .navigationTitle(cockpit.title)
        .navigationSubtitle(cockpit.locationSummary)

        .task(id: cockpit.sessionID) { await cockpit.loadBranch() }
        .onChange(of: cockpit.sessionID, initial: true) { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        let cockpit = self.cockpit
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 48, event.modifierFlags.contains(.shift) else { return event }
            let modes = Self.modeChoices.map(\.mode)
            let current = cockpit.preferredMode ?? cockpit.detectedMode ?? .manual
            let next = modes[((modes.firstIndex(of: current) ?? 0) + 1) % modes.count]
            Task { await cockpit.choose(mode: next) }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - Transcript

    private var transcript: some View {
        GeometryReader { geometry in
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
                        assistantBubble(cockpit.streaming, at: nil).id("streaming")
                    } else if cockpit.isBusy, cockpit.pending == nil {
                        HStack(spacing: 0) {
                            TypingIndicator()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.quaternary.opacity(0.4),
                                            in: RoundedRectangle(cornerRadius: 13))
                            Spacer(minLength: 64)
                        }
                        .id("typing")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: cockpit.lines.count) { scrollToEnd(proxy) }
            .onChange(of: cockpit.streaming) { scrollToEnd(proxy) }
        }
        .id(cockpit.sessionID)
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
            assistantBubble(line.text, at: line.timestamp)

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

    private func userBubble(_ line: CockpitModel.Line) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 64)
            bubble(text: line.text, moment: line.timestamp,
                   tint: AnyShapeStyle(Color.accentColor.opacity(0.22)))
        }
    }

    private func assistantBubble(_ text: String, at moment: Date?) -> some View {
        HStack(spacing: 0) {
            bubble(text: text, moment: moment, tint: AnyShapeStyle(.quaternary.opacity(0.4)),
                   markdown: true)
            Spacer(minLength: 64)
        }
    }

    private func bubble(text: String, moment: Date?, tint: AnyShapeStyle,
                        markdown: Bool = false) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            if markdown {
                MarkdownText(text: text)
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let moment {
                Text(moment, format: .dateTime.hour().minute())
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint, in: RoundedRectangle(cornerRadius: 13))
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
                modeBadge
                modelBadge
                effortBadge
                if cockpit.isBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(busyLabel(at: context.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button {
                        Task { await cockpit.stop() }
                    } label: {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Parar o que está rodando")
                } else if cockpit.pending != nil {
                    Text("aguardando você").font(.system(size: 10)).foregroundStyle(.orange)
                } else if let status = visibleStatus {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(status.hasPrefix("procurando")
                                         ? AnyShapeStyle(.secondary)
                                         : AnyShapeStyle(.orange))
                        .lineLimit(1)
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

    private var modelBadge: some View {
        Menu {
            Picker("Modelo", selection: modelSelection) {
                ForEach(CockpitModel.modelChoices, id: \.id) { choice in
                    Text(choice.name).tag(choice.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 3) {
                Text(modelLabel)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary.opacity(0.4), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Escolher o modelo das próximas mensagens")
    }

    static let modeChoices: [(mode: PermissionMode, name: String, symbol: String, color: Color)] = [
        (.auto, "Automático", "forward.fill", .yellow),
        (.plan, "Planejamento", "pause.fill", .blue),
        (.acceptEdits, "Aceitar edições", "forward.fill", .purple),
        (.manual, "Manual", "pause.fill", .gray),
    ]

    private var currentMode: PermissionMode {
        cockpit.preferredMode ?? cockpit.detectedMode ?? .manual
    }

    private var modeBadge: some View {
        let current = currentMode
        let choice = Self.modeChoices.first { $0.mode == current }
            ?? (mode: current, name: current.rawValue, symbol: "pause.fill", color: Color.gray)
        return Menu {
            Picker("Modo", selection: modeSelection) {
                ForEach(Self.modeChoices, id: \.mode) { choice in
                    Label(choice.name, systemImage: choice.symbol).tag(choice.mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 8))
                Text(choice.name)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10))
            .foregroundStyle(choice.color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary.opacity(0.4), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Modo de permissão — Shift+Tab alterna")
    }

    private var modeSelection: Binding<PermissionMode> {
        Binding(
            get: { currentMode },
            set: { mode in Task { await cockpit.choose(mode: mode) } }
        )
    }

    private var effortBadge: some View {
        Menu {
            Picker("Esforço", selection: effortSelection) {
                ForEach(CockpitModel.effortChoices, id: \.id) { choice in
                    Text(choice.name).tag(choice.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 3) {
                Text(effortLabel)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary.opacity(0.4), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Escolher o esforço das próximas mensagens")
    }

    private var effortSelection: Binding<EffortLevel?> {
        Binding(
            get: { cockpit.preferredEffort ?? cockpit.detectedEffort },
            set: { level in Task { await cockpit.choose(effort: level) } }
        )
    }

    private var effortLabel: String {
        guard let level = cockpit.preferredEffort ?? cockpit.detectedEffort else { return "Esforço" }
        return CockpitModel.effortChoices.first { $0.id == level }?.name ?? level.rawValue
    }

    private var modelSelection: Binding<String?> {
        Binding(
            get: {
                if let id = cockpit.preferredModel { return id }
                let reported = cockpit.model.lowercased()
                return CockpitModel.modelChoices.first { choice in
                    choice.id.map { reported.contains($0) } ?? false
                }?.id
            },
            set: { id in Task { await cockpit.choose(model: id) } }
        )
    }

    private var modelLabel: String {
        let reported = cockpit.model
        guard let alias = cockpit.preferredModel else {
            return reported.isEmpty ? "modelo" : CockpitModel.displayName(for: reported)
        }
        if reported.lowercased().contains(alias.lowercased()) {
            return CockpitModel.displayName(for: reported)
        }
        return CockpitModel.modelChoices.first { $0.id == alias }?.name ?? alias
    }

    private var visibleStatus: String? {
        let status = cockpit.status
        guard status.hasPrefix("falhou") || status.hasPrefix("encerrada") else { return nil }
        return status
    }

    private func busyLabel(at now: Date) -> String {
        guard let start = cockpit.turnStartedAt else { return "Pensando" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60
            ? "Pensando · \(seconds)s"
            : "Pensando · \(seconds / 60)m \(seconds % 60)s"
    }
}

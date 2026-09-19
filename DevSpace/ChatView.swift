import SwiftUI
import HarnessCore
import ClaudeHarness

struct ChatView: View {
    @Bindable var cockpit: CockpitModel
    @State private var expanded: Set<UUID> = []
    @State private var keyMonitor: Any?

    struct ZoomedImage: Identifiable, Equatable {
        let id = UUID()
        let data: Data
    }

    @State private var zoomed: ZoomedImage?
    @State private var nearBottom = true

    struct MentionCandidate: Identifiable {
        let path: String
        let isDirectory: Bool
        var id: String { path }
    }

    @State private var fileIndex: [MentionCandidate] = []
    @State private var mentionSelection = 0
    @State private var mentionDismissed = false

    private struct ScrollEdgeState: Equatable {
        var distance: CGFloat
        var contentHeight: CGFloat
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                transcript
                composer
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }

        .navigationTitle(cockpit.title)
        .navigationSubtitle(cockpit.locationSummary)

        .task(id: cockpit.sessionID) { await cockpit.loadBranch() }
        .task(id: cockpit.workingDirectory) { await loadFileIndex() }
        .onChange(of: cockpit.prompt) {
            mentionSelection = 0
            mentionDismissed = false
        }
        .onChange(of: cockpit.sessionID, initial: true) { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            let cockpit = self.cockpit
            Task { @MainActor in
                if cockpit.hasUnread { cockpit.hasUnread = false }
            }
        }
        .overlay { lightbox }
    }

    @ViewBuilder
    private var lightbox: some View {
        if let zoomed, let image = NSImage(data: zoomed.data) {
            ZStack {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .transition(.opacity)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 24)
                    .padding(36)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            }
            .contentShape(Rectangle())
            .onTapGesture { closeLightbox() }
            .help("Clique ou Esc para fechar")
        }
    }

    private func closeLightbox() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { zoomed = nil }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        let cockpit = self.cockpit
        let zoomed = $zoomed
        let view = self
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let matches = view.currentMentionMatches()
            if !matches.isEmpty {
                let selected = min(view.mentionSelection, matches.count - 1)
                switch event.keyCode {
                case 125:
                    view.mentionSelection = min(selected + 1, matches.count - 1)
                    return nil
                case 126:
                    view.mentionSelection = max(selected - 1, 0)
                    return nil
                case 36:
                    view.acceptMention(matches[selected])
                    return nil
                case 48 where !event.modifierFlags.contains(.shift):
                    view.acceptMention(matches[selected])
                    return nil
                case 53:
                    view.mentionDismissed = true
                    return nil
                default:
                    break
                }
            }
            if event.keyCode == 53, zoomed.wrappedValue != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    zoomed.wrappedValue = nil
                }
                return nil
            }
            if event.keyCode == 48, event.modifierFlags.contains(.shift) {
                let modes = Self.modeChoices.map(\.mode)
                let current = cockpit.preferredMode ?? cockpit.detectedMode ?? .manual
                let next = modes[((modes.firstIndex(of: current) ?? 0) + 1) % modes.count]
                Task { await cockpit.choose(mode: next) }
                return nil
            }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v" {
                let images = Self.pasteboardImages()
                if !images.isEmpty {
                    for data in images { cockpit.attach(imageData: data) }
                    return nil
                }
            }
            return event
        }
    }

    static func pasteboardImages() -> [Data] {
        let board = NSPasteboard.general
        let types = board.types ?? []
        guard types.contains(.png) || types.contains(.tiff) else { return [] }
        return (board.readObjects(forClasses: [NSImage.self]) ?? [])
            .compactMap { object in
                guard let image = object as? NSImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff)
                else { return nil }
                return bitmap.representation(using: .png, properties: [:])
            }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
                    } else if cockpit.isBusy, cockpit.pending == nil,
                              cockpit.pendingQuestion == nil {
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
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { transientCards }
            .onScrollGeometryChange(for: ScrollEdgeState.self) { geometry in
                ScrollEdgeState(
                    distance: geometry.contentSize.height
                        - (geometry.contentOffset.y + geometry.containerSize.height
                           - geometry.contentInsets.bottom),
                    contentHeight: geometry.contentSize.height)
            } action: { old, new in
                if new.distance <= 100 {
                    nearBottom = true
                } else if old.contentHeight == new.contentHeight,
                          new.distance > old.distance {
                    nearBottom = false
                }
            }
            .overlay(alignment: .bottom) {
                if !nearBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { jumpToEnd(proxy) }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(9)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(.quaternary, lineWidth: 1))
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .help("Ir para o final")
                }
            }
            .animation(.easeOut(duration: 0.15), value: nearBottom)
            .onAppear {
                nearBottom = true
                jumpToEnd(proxy)
            }
            .onChange(of: cockpit.lines.count) { scrollToEnd(proxy) }
            .onChange(of: cockpit.streaming) { scrollToEnd(proxy) }
            .onChange(of: cockpit.pendingQuestion?.id) { scrollToEnd(proxy) }
        }
        .id(cockpit.sessionID)
    }

    @ViewBuilder
    private var transientCards: some View {
        if cockpit.pending != nil || cockpit.pendingQuestion != nil {
            VStack(spacing: 6) {
                if let pending = cockpit.pending {
                    permissionCard(pending)
                }
                if let question = cockpit.pendingQuestion {
                    QuestionCard(
                        prompt: question,
                        answer: { selections in
                            nearBottom = true
                            Task { await cockpit.answerQuestion(selections) }
                        },
                        dismiss: { Task { await cockpit.dismissQuestion() } }
                    )
                    .id(question.id)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(.bar)
        }
    }

    private func jumpToEnd(_ proxy: ScrollViewProxy) {
        if !cockpit.streaming.isEmpty { proxy.scrollTo("streaming", anchor: .bottom) }
        else if let last = cockpit.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard nearBottom else { return }
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
                   tint: AnyShapeStyle(Color.accentColor.opacity(0.22)),
                   images: line.images)
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
                        markdown: Bool = false, images: [Data] = []) -> some View {
        let sizes = images.map(Self.displaySize(for:))
        let contentWidth = sizes.map(\.width).max()
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: sizes[index].width, height: sizes[index].height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                zoomed = ZoomedImage(data: data)
                            }
                        }
                        .help("Clique para ampliar")
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if markdown {
                    MarkdownText(text: text)
                } else if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !images.isEmpty { Spacer(minLength: 12) }
                if let moment {
                    Text(moment, format: .dateTime.hour().minute())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: contentWidth)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint, in: RoundedRectangle(cornerRadius: 13))
    }

    private static func displaySize(for data: Data) -> CGSize {
        guard let image = NSImage(data: data),
              image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = min(1, min(280 / image.size.width, 220 / image.size.height))
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
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
            mentionSuggestions

            if !cockpit.pendingImages.isEmpty {
                pendingImageRow
            }

            TextField("Peça uma alteração…", text: $cockpit.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.system(size: 13))
                .onSubmit { submit() }

            HStack(spacing: 8) {
                modeBadge
                folderBadge
                modelBadge
                effortBadge
                if cockpit.isBusy {
                    ProgressView().controlSize(.mini)
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
                } else if cockpit.pending != nil || cockpit.pendingQuestion != nil {
                    Text("Aguardando você").font(.system(size: 10)).foregroundStyle(.orange)
                } else if let status = visibleStatus {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(status.hasPrefix("procurando")
                                         ? AnyShapeStyle(.secondary)
                                         : AnyShapeStyle(.orange))
                        .lineLimit(1)
                }
                Spacer()
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 19))
                }
                .buttonStyle(.plain)
                .disabled(cockpit.prompt.trimmingCharacters(in: .whitespaces).isEmpty
                          && cockpit.pendingImages.isEmpty)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Menções com @

    private var activeMentionQuery: String? {
        let text = cockpit.prompt
        guard let at = text.range(of: "@", options: .backwards) else { return nil }
        let token = text[at.upperBound...]
        guard !token.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        if at.lowerBound > text.startIndex {
            let previous = text[text.index(before: at.lowerBound)]
            guard previous.isWhitespace || previous.isNewline else { return nil }
        }
        return String(token)
    }

    private func currentMentionMatches() -> [MentionCandidate] {
        guard !mentionDismissed, let query = activeMentionQuery else { return [] }
        guard !query.isEmpty else { return Array(fileIndex.prefix(8)) }
        let lowered = query.lowercased()
        let ranked = fileIndex.compactMap { candidate -> (MentionCandidate, Int)? in
            let name = (candidate.path as NSString).lastPathComponent.lowercased()
            if name.hasPrefix(lowered) { return (candidate, 0) }
            if name.contains(lowered) { return (candidate, 1) }
            if candidate.path.lowercased().contains(lowered) { return (candidate, 2) }
            return nil
        }
        return ranked.sorted { $0.1 < $1.1 }.prefix(8).map(\.0)
    }

    @ViewBuilder
    private var mentionSuggestions: some View {
        let matches = currentMentionMatches()
        if !matches.isEmpty {
            let selected = min(mentionSelection, matches.count - 1)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, candidate in
                    HStack(spacing: 6) {
                        Image(systemName: candidate.isDirectory ? "folder" : "doc.text")
                            .font(.system(size: 10))
                            .frame(width: 14)
                            .foregroundStyle(index == selected ? .white : .secondary)
                        Text(candidate.path)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(index == selected
                                ? AnyShapeStyle(Color.accentColor)
                                : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(index == selected ? .white : .primary)
                    .contentShape(Rectangle())
                    .onTapGesture { acceptMention(candidate) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func acceptMention(_ candidate: MentionCandidate) {
        guard let at = cockpit.prompt.range(of: "@", options: .backwards) else { return }
        let prefix = String(cockpit.prompt[..<at.lowerBound])
        if candidate.isDirectory {
            cockpit.prompt = prefix + "@" + candidate.path + "/"
        } else {
            cockpit.prompt = prefix + "@" + candidate.path + " "
        }
    }

    private func loadFileIndex() async {
        let root = cockpit.workingDirectory
        fileIndex = await Task.detached(priority: .utility) {
            Self.indexFiles(under: root)
        }.value
    }

    nonisolated private static func indexFiles(under root: URL) -> [MentionCandidate] {
        let skip: Set<String> = ["node_modules", ".git", ".build", "DerivedData",
                                 ".next", "dist", "build", "Pods", ".venv", "vendor"]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var results: [MentionCandidate] = []
        for case let url as URL in enumerator {
            if results.count >= 4000 { break }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDirectory, skip.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let relative = String(url.path.dropFirst(root.path.count)
                .drop(while: { $0 == "/" }))
            guard !relative.isEmpty else { continue }
            results.append(MentionCandidate(path: relative, isDirectory: isDirectory))
        }
        return results.sorted {
            let a = $0.path.filter { $0 == "/" }.count
            let b = $1.path.filter { $0 == "/" }.count
            return a == b ? $0.path < $1.path : a < b
        }
    }

    private func submit() {
        let text = cockpit.prompt
        cockpit.prompt = ""
        nearBottom = true
        Task { await cockpit.send(text: text) }
    }

    private var pendingImageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cockpit.pendingImages) { pasted in
                    if let image = NSImage(data: pasted.data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    cockpit.removeImage(pasted.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .padding(2)
                                .help("Remover imagem")
                            }
                    }
                }
            }
            .padding(.top, 2)
        }
        .frame(height: 62)
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

    private var folderBadge: some View {
        Button(action: chooseSessionFolder) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 8))
                Text(cockpit.workingDirectory.lastPathComponent)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary.opacity(0.4), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(cockpit.workingDirectory.path)
    }

    private func chooseSessionFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Usar"
        panel.directoryURL = cockpit.workingDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await cockpit.choose(directory: url) }
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
        return status.prefix(1).uppercased() + status.dropFirst()
    }

    private func busyLabel(at now: Date) -> String {
        guard let start = cockpit.turnStartedAt else { return "Pensando" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60
            ? "Pensando · \(seconds)s"
            : "Pensando · \(seconds / 60)m \(seconds % 60)s"
    }
}

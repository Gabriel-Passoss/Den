import SwiftUI
import HarnessCore

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
    @State private var scrollPosition = ScrollPosition()
    @State private var escArmed = false
    @State private var escDisarm: Task<Void, Never>?

    struct MentionCandidate: Identifiable {
        let path: String
        let isDirectory: Bool
        var id: String { path }
    }

    @State private var fileIndex: [MentionCandidate] = []
    @State private var mentionSelection = 0
    @State private var mentionDismissed = false

    @AppStorage("DevSpace.gitInspector") private var showChanges = false
    let gitChanges: GitChangesModel

    private struct ScrollEdgeState: Equatable {
        var isNearBottom: Bool
        var distance: CGFloat
        var contentHeight: CGFloat

        static func bucket(_ value: CGFloat) -> CGFloat { (value / 8).rounded() * 8 }
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

        .focusedSceneValue(\.cockpit, cockpit)

        .inspector(isPresented: $showChanges) {
            GitChangesPanel(model: gitChanges, directory: cockpit.workingDirectory,
                            close: { showChanges = false })
                .inspectorColumnWidth(min: 280, ideal: 560, max: 560)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                harnessSwitcher
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showChanges.toggle()
                } label: {
                    Label {
                        Text("Alterações")
                    } icon: {
                        Image("GitChanges")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                }
                .keyboardShortcut("0", modifiers: [.option, .command])
                .help(showChanges ? "Ocultar alterações do Git"
                                  : "Mostrar alterações do Git")
            }
        }
        .task(id: "\(showChanges)|\(cockpit.workingDirectory.path)") {
            guard showChanges else { return }
            await gitChanges.load(directory: cockpit.workingDirectory)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await gitChanges.load(directory: cockpit.workingDirectory)
            }
        }

        .task(id: cockpit.sessionID) { await cockpit.loadBranch() }
        .task(id: cockpit.workingDirectory) { await loadFileIndex() }
        .onChange(of: cockpit.prompt) {
            mentionSelection = 0
            mentionDismissed = false
        }
        .onChange(of: cockpit.sessionID, initial: true) { installKeyMonitor() }
        .onChange(of: cockpit.isBusy) {
            if !cockpit.isBusy {
                escDisarm?.cancel()
                escArmed = false
                if showChanges {
                    let gitChanges = self.gitChanges
                    let directory = cockpit.workingDirectory
                    Task { await gitChanges.load(directory: directory) }
                }
            }
        }
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
        if let zoomed, let image = Self.decodedImage(zoomed.data) {
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
            if event.keyCode == 36, event.modifierFlags.contains(.shift),
               let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
               editor.isFieldEditor {
                editor.insertNewlineIgnoringFieldEditor(nil)
                return nil
            }
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
            if event.keyCode == 53, cockpit.isBusy {
                if view.escArmed {
                    view.escDisarm?.cancel()
                    view.escArmed = false
                    Task { await cockpit.stop() }
                } else {
                    view.armEscInterrupt()
                }
                return nil
            }
            if event.keyCode == 48, event.modifierFlags.contains(.shift) {
                if let mode = cockpit.knobs.first(where: { $0.category == .mode }),
                   !mode.options.isEmpty {
                    let values = mode.options.map(\.value)
                    let at = values.firstIndex(of: mode.currentValue ?? "") ?? -1
                    let next = values[(at + 1) % values.count]
                    Task { await cockpit.choose(knob: mode.id, value: next) }
                }
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

    private func armEscInterrupt() {
        withAnimation(.easeOut(duration: 0.15)) { escArmed = true }
        escDisarm?.cancel()
        escDisarm = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { escArmed = false }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - Transcript

    private var transcript: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(cockpit.blocks) { block in
                        switch block {
                        case .line(let line):
                            row(line).id(line.id)
                        case .collapsed(let id, let lines):
                            steps(id: id, lines: lines).id(id)
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
            .defaultScrollAnchor(.bottom)
            .scrollPosition($scrollPosition)
            .safeAreaInset(edge: .bottom, spacing: 0) { transientCards }
            .onScrollGeometryChange(for: ScrollEdgeState.self) { geometry in
                let distance = geometry.contentSize.height
                    - (geometry.contentOffset.y + geometry.containerSize.height
                       - geometry.contentInsets.bottom)
                return ScrollEdgeState(
                    isNearBottom: distance <= 100,
                    distance: ScrollEdgeState.bucket(distance),
                    contentHeight: ScrollEdgeState.bucket(geometry.contentSize.height))
            } action: { old, new in
                let follow: Bool
                if new.isNearBottom {
                    follow = true
                } else if old.contentHeight == new.contentHeight,
                          new.distance > old.distance {
                    follow = false
                } else {
                    follow = nearBottom  // conteúdo cresceu: preserva a escolha
                }
                if nearBottom != follow { nearBottom = follow }
            }
            .overlay(alignment: .bottom) {
                Group {
                if !nearBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { jumpToEnd() }
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
            }
            .onAppear {
                nearBottom = true
                jumpToEnd()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    jumpToEnd()
                }
            }
            .onChange(of: cockpit.lines.count) { scrollToEnd() }
            .onChange(of: cockpit.streaming) { scrollToEnd() }
            .onChange(of: cockpit.pendingQuestion?.id) { scrollToEnd() }
            .onChange(of: typingVisible) { scrollToEnd() }
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

    private var typingVisible: Bool {
        cockpit.streaming.isEmpty && cockpit.isBusy
            && cockpit.pending == nil && cockpit.pendingQuestion == nil
    }

    private func jumpToEnd() {
        scrollPosition.scrollTo(edge: .bottom)
    }

    private func scrollToEnd() {
        guard nearBottom else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            scrollPosition.scrollTo(edge: .bottom)
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
                Text(Self.clipped(line.text))
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
                   images: line.images, files: line.files)
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
                        markdown: Bool = false, images: [Data] = [],
                        files: [String] = []) -> some View {
        let sizes = images.map(Self.displaySize(for:))
        let contentWidth = sizes.map(\.width).max()
        return VStack(alignment: .center, spacing: 6) {
            ForEach(files, id: \.self) { name in
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                if let image = Self.decodedImage(data) {
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
                    MarkdownText(text: Self.clipped(text, limit: 12_000))
                } else if !text.isEmpty {
                    Text(Self.clipped(text, limit: 12_000))
                        .font(.system(size: 13))
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let moment {
                    Text(moment, format: .dateTime.hour().minute())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: images.isEmpty ? nil : max(contentWidth ?? 0, 220),
                   alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint, in: RoundedRectangle(cornerRadius: 13))
    }

    private static let decodedImages = NSCache<NSData, NSImage>()

    static func decodedImage(_ data: Data) -> NSImage? {
        let key = data as NSData
        if let cached = decodedImages.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        decodedImages.setObject(image, forKey: key)
        return image
    }

    private static func displaySize(for data: Data) -> CGSize {
        guard let image = decodedImage(data),
              image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = min(1, min(280 / image.size.width, 220 / image.size.height))
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private static func clipped(_ text: String, limit: Int = 1_200) -> String {
        guard text.utf8.count > limit else { return text }
        let head = String(text.prefix(limit))
        let hidden = text.count - head.count
        return head + "\n⋯ +\(hidden) caracteres não exibidos"
    }

    private func chip(icon: String, text: String, mono: Bool, dim: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(dim ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .frame(width: 13)
            Text(Self.clipped(text))
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
    private func steps(id: UUID, lines: [CockpitModel.Line]) -> some View {
        let isOpen = expanded.contains(id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { expanded.remove(id) } else { expanded.insert(id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10))
                    Text(lines.count == 1 ? "1 passo" : "\(lines.count) passos")
                        .font(.system(size: 11))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Recolher os passos" : "Ver o que a IA fez")
            .accessibilityLabel(isOpen ? "Recolher passos" : "Expandir \(lines.count) passos")

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines) { line in
                        if line.role == .unknown {
                            Text(line.text)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            row(line)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(.quaternary.opacity(isOpen ? 0.18 : 0),
                    in: RoundedRectangle(cornerRadius: 9))
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

            Text("\(cockpit.harnessName) quer usar \(request.displayName ?? request.toolName).")
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
                ForEach(request.options, id: \.id) { option in
                    let button = Button(option.label) {
                        Task { await cockpit.resolve(option) }
                    }

                    if option.kind == .allowOnce {
                        button.keyboardShortcut(.defaultAction)
                    } else {
                        button
                    }
                }
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

            if !cockpit.pendingAttachments.isEmpty {
                pendingAttachmentRow
            }

            TextField("Peça uma alteração…", text: $cockpit.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.system(size: 13))
                .onSubmit { submit() }

            HStack(spacing: 8) {
                ForEach(cockpit.knobs.filter { $0.category == .mode }) { knobBadge($0) }
                folderBadge
                ForEach(cockpit.knobs.filter { $0.category != .mode }) { knobBadge($0) }
                if cockpit.isBusy {
                    ProgressView().controlSize(.mini)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(busyLabel(at: context.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if escArmed {
                        Text("Esc duas vezes interrompe")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
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
                Button(action: attachFiles) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Anexar arquivos")
                Button {
                    if cockpit.isBusy {
                        Task { await cockpit.stop() }
                    } else {
                        submit()
                    }
                } label: {
                    Image(systemName: cockpit.isBusy ? "stop.circle.fill"
                                                     : "arrow.up.circle.fill")
                        .font(.system(size: 19))
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeInOut(duration: 0.2), value: cockpit.isBusy)
                }
                .buttonStyle(.plain)
                .disabled(!cockpit.isBusy
                          && cockpit.prompt.trimmingCharacters(in: .whitespaces).isEmpty
                          && cockpit.pendingAttachments.isEmpty)
                .help(cockpit.isBusy ? "Parar o que está rodando" : "Enviar mensagem")
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

    private var pendingAttachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cockpit.pendingAttachments) { pending in
                    if pending.isImage, let image = Self.decodedImage(pending.data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                removeAttachmentButton(pending.id, help: "Remover imagem")
                            }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Text(pending.name ?? "arquivo")
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 160, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 56)
                        .background(.quaternary.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            removeAttachmentButton(pending.id, help: "Remover arquivo")
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
        .frame(height: 62)
    }

    private func removeAttachmentButton(_ id: UUID, help: String) -> some View {
        Button {
            cockpit.removeAttachment(id)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white, .black.opacity(0.6))
        }
        .buttonStyle(.plain)
        .padding(2)
        .help(help)
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

    private static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp"]

    private func attachFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Anexar"
        panel.directoryURL = cockpit.workingDirectory
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if Self.imageExtensions.contains(url.pathExtension.lowercased()),
               let image = NSImage(contentsOf: url),
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                cockpit.attach(imageData: png)
            } else if url.pathExtension.lowercased() == "pdf",
                      let data = try? Data(contentsOf: url) {
                cockpit.attach(fileData: data, name: url.lastPathComponent,
                               mediaType: "application/pdf")
            } else {
                mentionPath(for: url)
            }
        }
    }

    private func mentionPath(for url: URL) {
        let root = cockpit.workingDirectory.path
        let path = url.path.hasPrefix(root + "/")
            ? String(url.path.dropFirst(root.count + 1))
            : url.path
        var prompt = cockpit.prompt
        if !prompt.isEmpty, !prompt.hasSuffix(" ") { prompt += " " }
        cockpit.prompt = prompt + "@" + path + " "
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

    /// Pull-down, não pop-up. Pela letra do HIG uma escolha mutuamente
    /// exclusiva pede pop-up, mas trocar de harness não é selecionar um estado
    /// barato: fecha o segmento, transfere o contexto e sobe outro processo.
    /// É um comando — e é por isso que abre para baixo em vez de sobre o botão.
    ///
    /// Sem `.buttonStyle`/`.menuStyle` próprios, de propósito: é a chrome de
    /// sistema que traz o Liquid Glass e a animação de abertura.
    private var harnessSwitcher: some View {
        Menu {
            ForEach(HarnessRegistry.all.map(\.id), id: \.rawValue) { candidate in
                Button {
                    Task { await cockpit.switchHarness(to: candidate) }
                } label: {
                    Label {
                        Text(HarnessBadge.name(for: candidate))
                    } icon: {
                        HarnessBadge(harness: candidate, size: 14)
                    }
                }
                .disabled(candidate == cockpit.harness)
            }
        } label: {
            HStack(spacing: 6) {
                HarnessBadge(harness: cockpit.harness, size: 15)
                Text(cockpit.harnessName)
            }
            .padding(.horizontal, 6)
        }
        .labelStyle(.titleAndIcon)
        .disabled(!cockpit.canSwitchHarness)
        .help(cockpit.isBusy
              ? "Espere o turno terminar para trocar de harness"
              : "Trocar de harness levando a conversa junto")
    }

    static let modeLooks: [String: (symbol: String, color: Color)] = [
        "auto": ("forward.fill", .yellow),
        "plan": ("pause.fill", .blue),
        "acceptEdits": ("forward.fill", .purple),
        "manual": ("pause.fill", .gray),
        "dontAsk": ("forward.fill", .orange),
        "bypassPermissions": ("forward.fill", .red),
        "build": ("hammer.fill", .green),
    ]

    private func selection(for knob: HarnessKnob) -> Binding<String?> {
        Binding(
            get: { cockpit.knob(knob.id)?.currentValue },
            set: { value in Task { await cockpit.choose(knob: knob.id, value: value) } }
        )
    }

    @ViewBuilder
    private func knobOption(_ option: HarnessKnob.Option, in knob: HarnessKnob) -> some View {
        if knob.category == .mode, let icon = Self.modeLooks[option.value] {
            Label(option.label, systemImage: icon.symbol).tag(Optional(option.value))
        } else {
            Text(option.label).tag(Optional(option.value))
        }
    }

    /// Um menu por botão que o harness declarou. O Claude Code oferece modelo,
    /// esforço e permissão; o OpenCode oferece modelo e modo, descobertos em
    /// runtime. Nenhum dos dois está escrito aqui.
    @ViewBuilder
    private func knobBadge(_ knob: HarnessKnob) -> some View {
        let current = knob.currentValue
        let look = knob.category == .mode ? Self.modeLooks[current ?? ""] : nil

        Menu {
            Picker(knob.name, selection: selection(for: knob)) {
                /// Lista plana vira um grupo sem título, então o `Section` só
                /// aparece de fato quando o harness nomeou os grupos — os 23
                /// modelos do OpenCode, separados por provedor.
                ForEach(Array(knob.groupedOptions.enumerated()), id: \.offset) { _, bucket in
                    Section {
                        ForEach(bucket.options, id: \.value) { option in
                            knobOption(option, in: knob)
                        }
                    } header: {
                        if let group = bucket.group { Text(group) }
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 3) {
                if let look {
                    Image(systemName: look.symbol).font(.system(size: 8))
                }
                Text(knob.label(for: current) ?? knob.name)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
            }
            .font(.system(size: 10))
            .foregroundStyle(look.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary.opacity(0.4), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Escolher \(knob.name.lowercased()) das próximas mensagens")
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

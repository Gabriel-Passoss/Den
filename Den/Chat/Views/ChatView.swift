import SwiftUI
import HarnessCore

struct ChatView: View {
    @Bindable var chat: ChatModel
    @State private var slash = SlashController()
    @State private var mentions = MentionController()
    @State private var expanded: Set<UUID> = []
    @State private var keys = ChatKeyMonitor()

    @State private var zoomed: ZoomedImage?
    @State private var nearBottom = true
    @State private var scrollPosition = ScrollPosition()
    @State private var tableLock = TableScrollLock()

    @AppStorage(InspectorPane.storageKey) private var pane: InspectorPane = .closed
    @AppStorage("Den.inspectorWidth") private var inspectorWidth: Double = 480
    @State private var lastOpenPane: InspectorPane = .changes
    @Environment(RunManager.self) private var runs
    @Environment(RunConfigurationsModel.self) private var runConfigurations
    @Environment(\.chrome) private var chrome
    let gitChanges: GitChangesModel

    private static let minimumChatWidth: CGFloat = 420
    private static let minimumInspectorWidth: Double = 320

    private struct ScrollEdgeState: Equatable {
        var isNearBottom: Bool
        var distance: CGFloat
        var contentHeight: CGFloat

        static func bucket(_ value: CGFloat) -> CGFloat { (value / 8).rounded() * 8 }
    }

    var body: some View {
        GeometryReader { geometry in
            let room = Double(geometry.size.width - Self.minimumChatWidth)
            let docked = room >= Self.minimumInspectorWidth
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header
                    transcript
                    ChatComposer(chat: chat, slash: slash, mentions: mentions,
                                 keys: keys) { nearBottom = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)

                if pane != .closed, docked {
                    ResizeHandle(width: $inspectorWidth,
                                 range: Self.minimumInspectorWidth...room,
                                 growsTowardTrailing: false)
                    inspector
                        .frame(width: min(max(inspectorWidth, Self.minimumInspectorWidth), room))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .trailing) {
                if pane != .closed, !docked {
                    inspector
                        .frame(width: min(max(inspectorWidth, Self.minimumInspectorWidth),
                                          Double(geometry.size.width) - 56))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.borderStrong).frame(width: 1)
                        }
                        .shadow(color: .black.opacity(0.5), radius: 28, x: -8)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }

        .navigationTitle(chat.title)
        .focusedSceneValue(\.chat, chat)
        .task(id: "\(pane == .changes)|\(chat.workingDirectory.path)") {
            guard pane == .changes else { return }
            await gitChanges.load(directory: chat.workingDirectory)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await gitChanges.load(directory: chat.workingDirectory)
            }
        }

        .task(id: chat.sessionID) { await chat.loadBranch() }
        .task(id: chat.workingDirectory) { await mentions.loadIndex(under: chat.workingDirectory) }
        .onChange(of: chat.prompt) {
            mentions.selection = 0
            mentions.dismissed = false
            slash.selection = 0
            slash.dismissed = false
            if SlashCatalog.query(in: chat.prompt) == nil { slash.group = nil }
        }
        .onChange(of: chat.sessionID, initial: true) {
            keys.install(chat: chat, slash: slash, mentions: mentions,
                         zoomed: $zoomed) { nearBottom = true }
        }
        .onChange(of: chat.isBusy) {
            if !chat.isBusy {
                keys.disarmEsc()
                if pane == .changes {
                    let gitChanges = self.gitChanges
                    let directory = chat.workingDirectory
                    Task { await gitChanges.load(directory: directory) }
                }
            }
        }
        .onChange(of: pane) {
            if pane != .closed { lastOpenPane = pane }
        }
        .onDisappear { keys.remove() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            let chat = self.chat
            Task { @MainActor in
                if chat.hasUnread { chat.hasUnread = false }
            }
        }
        .overlay { lightbox }
    }

    private var header: some View {
        TopBar(leadingInset: chrome.leadingInset + (chrome.sidebarHidden ? 8 : 20)) {
            SidebarToggle()
            ViewThatFits(in: .horizontal) {
                breadcrumb(folder: true, branch: true)
                breadcrumb(folder: false, branch: true)
                breadcrumb(folder: false, branch: false)
            }
            Spacer(minLength: 12)
            HarnessSwitcher(chat: chat)
            panelToggle
        }
        .onKeyboardShortcut("0", modifiers: [.option, .command]) { toggle(.changes) }
        .onKeyboardShortcut("9", modifiers: [.option, .command]) { toggle(.run) }
    }

    private func breadcrumb(folder: Bool, branch: Bool) -> some View {
        HStack(spacing: 8) {
            if folder {
                Text(chat.workingDirectory.lastPathComponent)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .help(chat.workingDirectory.path)
                Text("/")
                    .foregroundStyle(Theme.textFaint)
            }
            Text(chat.title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
            if branch, let name = chat.branch {
                BranchPill(branch: name)
            }
        }
        .font(.system(size: 14))
    }

    private var panelToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                pane = pane == .closed ? lastOpenPane : .closed
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14))
                .foregroundStyle(pane == .closed ? Theme.textSecondary : Theme.text)
                .iconLabel(size: 32)
                .overlay(alignment: .topTrailing) {
                    if runActive {
                        Circle()
                            .fill(Theme.added)
                            .frame(width: 7, height: 7)
                            .offset(x: -5, y: 5)
                    }
                }
        }
        .buttonStyle(DenButtonStyle(kind: .secondary))
        .help(pane == .closed ? "Mostrar alterações e execução (⌥⌘0 / ⌥⌘9)"
                              : "Ocultar painel")
        .accessibilityLabel(pane == .closed ? "Mostrar painel" : "Ocultar painel")
    }

    private var inspector: some View {
        InspectorView(pane: $pane, gitChanges: gitChanges,
                      directory: chat.workingDirectory, runRoot: runRoot,
                      runActive: runActive)
    }

    private var runRoot: URL { runConfigurations.root(for: chat.workingDirectory) }

    private var runActive: Bool {
        runConfigurations.configurations(in: runRoot).contains { runs.isActive($0.id) }
    }

    private func toggle(_ target: InspectorPane) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if pane == target {
                pane = .closed
            } else {
                pane = target
                lastOpenPane = target
            }
        }
    }

    @ViewBuilder
    private var lightbox: some View {
        if let zoomed, let image = ImageCache.decodedImage(zoomed.data) {
            ZStack {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .transition(.opacity)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 24)
                    .padding(36)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            }
            .contentShape(Rectangle())
            .onTapGesture { closeLightbox() }
            .help("Clique ou Esc para fechar")
        }
    }

    private func zoom(_ data: Data) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            zoomed = ZoomedImage(data: data)
        }
    }

    private func closeLightbox() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { zoomed = nil }
    }

    // MARK: - Transcript

    private var transcript: some View {
        let blocks = chat.blocks
        let starts = Self.turnStarts(in: blocks)
        let tailStartsTurn = blocks.last.map {
            Self.isUserBlock($0) || Self.harness(of: $0) != chat.harness
        } ?? true
        let lastID = blocks.last?.id
        return ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if blocks.isEmpty, !chat.isBusy, chat.streaming.isEmpty {
                        SessionWelcome(chat: chat)
                    }
                    ForEach(blocks) { block in
                        switch block {
                        case .line(let line) where line.role == .user || line.role == .compaction:
                            TranscriptRow(line: line, expanded: $expanded,
                                          onZoom: zoom).id(line.id)
                        case .line(let line):
                            AssistantTurn(harness: line.harness ?? chat.harness,
                                          showsHeader: starts.contains(line.id),
                                          moment: line.timestamp) {
                                TranscriptRow(line: line, expanded: $expanded, onZoom: zoom)
                            }
                            .id(line.id)
                        case .collapsed(let id, let lines):
                            AssistantTurn(harness: Self.harness(of: block) ?? chat.harness,
                                          showsHeader: starts.contains(id),
                                          moment: lines.first?.timestamp) {
                                ToolSteps(id: id, lines: lines, expanded: $expanded,
                                          isLive: id == lastID && chat.isBusy
                                              && chat.streaming.isEmpty,
                                          onZoom: zoom)
                            }
                            .id(id)
                        }
                    }
                    if let since = chat.compactingSince {
                        CompactionProgressCard(since: since).id("compacting")
                    } else if !chat.streaming.isEmpty {
                        AssistantTurn(harness: chat.harness, showsHeader: tailStartsTurn,
                                      moment: nil) {
                            MessageBubble(text: chat.streaming, moment: nil,
                                          style: .assistant, markdown: true)
                        }
                        .id("streaming")
                    } else if chat.isBusy, chat.pending == nil,
                              chat.pendingQuestion == nil {
                        AssistantTurn(harness: chat.harness, showsHeader: tailStartsTurn,
                                      moment: nil) {
                            ThinkingRow(chat: chat)
                                .padding(.vertical, 4)
                        }
                        .id("typing")
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 30)
                .frame(maxWidth: 784, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition($scrollPosition)
            .scrollDisabled(tableLock.isLocked)
            .environment(tableLock)
            .overlay(alignment: .bottom) {
                Group {
                if !nearBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { jumpToEnd() }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 34, height: 34)
                            .background(Theme.raised, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.borderControl, lineWidth: 1))
                            .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .help("Ir para o final")
                    .accessibilityLabel("Ir para o final")
                }
                }
                .animation(.easeOut(duration: 0.15), value: nearBottom)
            }
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
                let follow: Bool = if new.isNearBottom {
                    true
                } else if old.contentHeight == new.contentHeight,
                          new.distance > old.distance {
                    false
                } else {
                    nearBottom
                }
                if nearBottom != follow { nearBottom = follow }
            }
            .onAppear {
                nearBottom = true
                jumpToEnd()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    jumpToEnd()
                }
            }
            .onChange(of: chat.lines.count) { scrollToEnd() }
            .onChange(of: chat.streaming) { scrollToEnd() }
            .onChange(of: chat.pendingQuestion?.id) { scrollToEnd() }
            .onChange(of: typingVisible) { scrollToEnd() }
            .onChange(of: chat.compactingSince) { scrollToEnd() }
        .id(chat.sessionID)
    }

    private static func isUserBlock(_ block: ChatBlock) -> Bool {
        if case .line(let line) = block {
            return line.role == .user || line.role == .compaction
        }
        return false
    }

    static func harness(of block: ChatBlock) -> HarnessID? {
        switch block {
        case .line(let line): line.harness
        case .collapsed(_, let lines): lines.lazy.compactMap(\.harness).first
        }
    }

    static func turnStarts(in blocks: [ChatBlock]) -> Set<UUID> {
        var starts = Set<UUID>()
        var afterUser = true
        var previous: HarnessID?
        for block in blocks {
            if isUserBlock(block) {
                afterUser = true
            } else {
                let author = harness(of: block)
                if afterUser || author != previous { starts.insert(block.id) }
                afterUser = false
                previous = author
            }
        }
        return starts
    }

    @ViewBuilder
    private var transientCards: some View {
        if chat.pending != nil || chat.pendingQuestion != nil {
            VStack(spacing: 8) {
                if let pending = chat.pending {
                    PermissionCard(request: pending,
                                   harnessName: chat.harnessName) { option in
                        Task { await chat.resolve(option) }
                    }
                }
                if let question = chat.pendingQuestion {
                    QuestionCard(
                        prompt: question,
                        answer: { selections in
                            nearBottom = true
                            Task { await chat.answerQuestion(selections) }
                        },
                        dismiss: { Task { await chat.dismissQuestion() } }
                    )
                    .id(question.id)
                }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 784)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background {
                LinearGradient(colors: [Theme.canvas.opacity(0), Theme.canvas],
                               startPoint: .top, endPoint: .init(x: 0.5, y: 0.12))
            }
        }
    }

    private var typingVisible: Bool {
        chat.streaming.isEmpty && chat.isBusy && chat.compactingSince == nil
            && chat.pending == nil && chat.pendingQuestion == nil
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

}

struct AssistantTurn<Content: View>: View {
    let harness: HarnessID
    let showsHeader: Bool
    let moment: Date?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if showsHeader {
                    HarnessBadge(harness: harness, size: 28)
                } else {
                    Color.clear
                }
            }
            .frame(width: 28, height: showsHeader ? 28 : 1)

            VStack(alignment: .leading, spacing: 8) {
                if showsHeader {
                    HStack(spacing: 6) {
                        Text(HarnessBadge.name(for: harness))
                            .fontWeight(.medium)
                        if let moment {
                            Text("·")
                            Text(moment, format: .dateTime.hour().minute())
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(height: 28, alignment: .center)
                    .padding(.bottom, -6)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BranchPill: View {
    let branch: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .semibold))
            Text(branch)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .frame(maxWidth: 220)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
        .help(branch)
    }
}

struct SessionWelcome: View {
    let chat: ChatModel

    var body: some View {
        VStack(spacing: 18) {
            HarnessBadge(harness: chat.harness, size: 40)
            VStack(spacing: 5) {
                Text("\(chat.harnessName) em \(chat.workingDirectory.lastPathComponent)")
                    .font(.system(size: 17, weight: .semibold))
                Text("Descreva o que quer mudar. O agente lê, edita e executa no projeto.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                hint(Text("@").font(.system(size: 12, weight: .semibold, design: .monospaced)),
                     "cita arquivos")
                hint(Text("/").font(.system(size: 12, weight: .semibold, design: .monospaced)),
                     "abre comandos")
                hint(Image(systemName: "paperclip").font(.system(size: 11, weight: .medium)),
                     "anexa imagens e PDFs")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func hint(_ glyph: some View, _ text: String) -> some View {
        HStack(spacing: 6) {
            glyph
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}

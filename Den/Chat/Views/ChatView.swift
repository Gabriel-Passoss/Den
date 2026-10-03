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
    @State private var lastOpenPane: InspectorPane = .changes
    @Environment(RunManager.self) private var runs
    @Environment(RunConfigurationsModel.self) private var runConfigurations
    @Environment(WorktreeModel.self) private var worktrees
    @Environment(PullRequestMonitor.self) private var monitor
    @AppStorage(GitHubCLI.pathKey) private var ghPath = ""
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
                ChatComposer(chat: chat, slash: slash, mentions: mentions,
                             keys: keys) { nearBottom = true }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }

        .navigationTitle(chat.title)
        .navigationSubtitle(chat.locationSummary)

        .focusedSceneValue(\.chat, chat)

        .inspector(isPresented: inspectorPresented) {
            inspectorContent
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HarnessSwitcher(chat: chat)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggle(.changes)
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
                .help(pane == .changes ? "Ocultar alterações do Git"
                                       : "Mostrar alterações do Git")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggle(.run)
                } label: {
                    Label {
                        Text("Execução")
                    } icon: {
                        Image(systemName: "play.rectangle")
                            .overlay(alignment: .topTrailing) {
                                if runActive {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 3, y: -2)
                                }
                            }
                    }
                }
                .keyboardShortcut("9", modifiers: [.option, .command])
                .help(pane == .run ? "Ocultar execução" : "Mostrar execução")
            }
        }
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
        .task(id: chat.sessionID) {
            let id = chat.sessionID
            monitor.appear(id)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
            }
            monitor.disappear(id)
        }
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
                worktrees.clearWarning(chat.sessionID)
                monitor.turnEnded(chat.sessionID)
                if pane == .changes {
                    let gitChanges = self.gitChanges
                    let directory = chat.workingDirectory
                    Task { await gitChanges.load(directory: directory) }
                }
            }
        }
        .onDisappear { keys.remove() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            let chat = self.chat
            let monitor = self.monitor
            Task { @MainActor in
                if chat.hasUnread { chat.hasUnread = false }
                monitor.appBecameActive()
            }
        }
        .overlay { lightbox }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(get: { pane != .closed }, set: { if !$0 { pane = .closed } })
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if (pane == .closed ? lastOpenPane : pane) == .run {
            RunPanel(root: runRoot, close: { pane = .closed })
                .inspectorColumnWidth(min: 320, ideal: 560, max: 784)
        } else {
            GitChangesPanel(model: gitChanges, directory: chat.workingDirectory,
                            close: { pane = .closed })
                .inspectorColumnWidth(min: 280, ideal: 784, max: 784)
        }
    }

    private var runRoot: URL { runConfigurations.root(for: chat.workingDirectory) }

    private var runActive: Bool {
        runConfigurations.configurations(in: runRoot).contains { runs.isActive($0.id) }
    }

    private func toggle(_ target: InspectorPane) {
        if pane == target {
            pane = .closed
        } else {
            pane = target
            lastOpenPane = target
        }
    }

    @ViewBuilder
    private var lightbox: some View {
        if let zoomed, let image = ImageCache.decodedImage(zoomed.data) {
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.blocks) { block in
                        switch block {
                        case .line(let line):
                            TranscriptRow(line: line, expanded: $expanded,
                                          onZoom: zoom).id(line.id)
                        case .collapsed(let id, let lines):
                            ToolSteps(id: id, lines: lines, expanded: $expanded,
                                      onZoom: zoom).id(id)
                        }
                    }
                    if let since = chat.compactingSince {
                        CompactionProgressCard(since: since).id("compacting")
                    } else if !chat.streaming.isEmpty {
                        HStack(spacing: 0) {
                            MessageBubble(text: chat.streaming, moment: nil,
                                          tint: AnyShapeStyle(.quaternary.opacity(0.4)),
                                          markdown: true)
                            Spacer(minLength: 64)
                        }
                        .id("streaming")
                    } else if chat.isBusy, chat.pending == nil,
                              chat.pendingQuestion == nil {
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
            .scrollDisabled(tableLock.isLocked)
            .environment(tableLock)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    taskBars
                    transientCards
                }
            }
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
                    follow = nearBottom
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
            .onChange(of: chat.lines.count) { scrollToEnd() }
            .onChange(of: chat.streaming) { scrollToEnd() }
            .onChange(of: chat.pendingQuestion?.id) { scrollToEnd() }
            .onChange(of: typingVisible) { scrollToEnd() }
            .onChange(of: chat.compactingSince) { scrollToEnd() }
        .id(chat.sessionID)
    }

    @ViewBuilder
    private var taskBars: some View {
        let id = chat.sessionID
        let bars = monitor.bars(for: id)
        let setup = monitor.setupNeeded(for: id)
        if setup != nil || !bars.isEmpty {
            VStack(spacing: 6) {
                if let setup {
                    GitHubSetupBar(state: setup, choose: chooseGh,
                                   retry: { Task { await monitor.reconfigure(path: ghPath.isEmpty ? nil : ghPath) } },
                                   dismiss: { monitor.hideSetup(for: id) })
                }
                ForEach(bars) { bar in
                    PullRequestBar(repo: bar.repo,
                                   branch: worktrees.worktree(for: id)?.branch ?? "",
                                   pullRequest: bar.pullRequest,
                                   checkedAt: monitor.checkedAt(id, repo: bar.repo),
                                   refresh: { monitor.refresh(id, repo: bar.repo) },
                                   dismiss: {
                                       withAnimation(.easeOut(duration: 0.2)) {
                                           monitor.dismiss(id, repo: bar.repo)
                                       }
                                   })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, chat.pending == nil && chat.pendingQuestion == nil ? 6 : 0)
            .background(.bar)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bars.map(\.id))
        }
    }

    private func chooseGh() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Usar"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard await GitHubCLI.version(at: url.path) != nil else { return }
            ghPath = url.path
            await monitor.reconfigure(path: url.path)
        }
    }

    @ViewBuilder
    private var transientCards: some View {
        if chat.pending != nil || chat.pendingQuestion != nil {
            VStack(spacing: 6) {
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
            .padding(.horizontal, 20)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(.bar)
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

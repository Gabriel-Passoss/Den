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
    @Environment(RunManager.self) private var runs
    @Environment(RunConfigurationsModel.self) private var runConfigurations
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
                    ChatHeader(chat: chat, runActive: runActive)
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
        .onDisappear { keys.remove() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            let chat = self.chat
            Task { @MainActor in
                if chat.hasUnread { chat.hasUnread = false }
            }
        }
        .overlay { Lightbox(zoomed: $zoomed) }
        .followsTask(of: chat)
    }

    private var inspector: some View {
        InspectorView(pane: $pane, gitChanges: gitChanges,
                      directory: chat.workingDirectory, runRoot: runRoot,
                      runActive: runActive, chat: chat)
    }

    private var runRoot: URL { runConfigurations.root(for: chat.workingDirectory) }

    private var runActive: Bool {
        runConfigurations.configurations(in: runRoot).contains { runs.isActive($0.id) }
    }

    private func zoom(_ data: Data) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            zoomed = ZoomedImage(data: data)
        }
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
                JumpToEndButton(isVisible: !nearBottom) {
                    withAnimation(.easeOut(duration: 0.2)) { jumpToEnd() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    TaskBars(chat: chat)
                    TransientCards(chat: chat) { nearBottom = true }
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

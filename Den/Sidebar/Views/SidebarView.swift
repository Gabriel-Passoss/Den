import SwiftUI
import UniformTypeIdentifiers
import HarnessCore

private nonisolated final class DragTracker: NSItemProvider {
    var onEnd: (() -> Void)?
    deinit { onEnd?() }
}

struct SidebarView: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(WorktreeModel.self) private var worktrees
    @Environment(PullRequestMonitor.self) private var monitor
    var lightsInset: CGFloat = 0
    var collapse: () -> Void = {}

    @State private var collapsed: Set<String> = []
    @State private var dropTarget: String?
    @State private var dragging: UUID?
    @State private var dragGeneration = 0
    @State private var pendingDelete: SessionSummary?

    @State private var tipTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(workspace: workspace, lightsInset: lightsInset, collapse: collapse)
            SidebarSearch(workspace: workspace)
            list
        }
        .background(Theme.sidebar)
        .confirmationDialog(
            "Apagar \"\(pendingDelete?.title ?? "")\"?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive) {
                if let summary = pendingDelete {
                    Task { await workspace.deleteSession(summary.id) }
                    worktrees.forget(summary.id)
                }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                sectionTitle("Pastas") {
                    Button {
                        workspace.addFolder()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .iconLabel(size: 22)
                    }
                    .buttonStyle(.denGhost(radius: 6))
                    .help("Nova pasta")
                    .accessibilityLabel("Nova pasta")
                }

                ForEach(workspace.folderGroups) { group in
                    folder(group)
                }

                sectionTitle("Sessões") { EmptyView() }
                    .padding(.top, workspace.folderGroups.isEmpty ? 0 : 14)

                NewSessionRow(workspace: workspace)

                ForEach(workspace.looseSessions) { summary in
                    row(for: summary, in: nil)
                }

                if workspace.folderGroups.isEmpty, workspace.looseSessions.isEmpty {
                    SidebarEmptyList(search: workspace.search)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            receiveDrop(providers, into: nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Sidebar")
        .onChange(of: workspace.summaries, initial: true) {
            monitor.noteActivity(Dictionary(workspace.summaries.map { ($0.id, $0.updatedAt) },
                                            uniquingKeysWith: { max($0, $1) }))
        }
    }

    private func sectionTitle(_ title: String,
                              @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 28)
    }

    @ViewBuilder
    private func folder(_ group: WorkspaceModel.Group) -> some View {
        let isOpen = !collapsed.contains(group.id)
        FolderHeader(
            name: group.name,
            count: group.sessions.count,
            isOpen: isOpen,
            isDropTarget: dropTarget == group.id,
            toggle: { toggleCollapse(group.id) },
            rename: { workspace.renameFolder(group.id, to: $0) },
            newSession: { Task { await workspace.newSession(assignedTo: group.id) } },
            remove: { workspace.removeFolder(group.id) }
        )
        .onDrop(of: [.plainText], isTargeted: dropBinding(group.id)) { providers in
            receiveDrop(providers, into: group.id)
        }
        .onDrag {
            dragging = nil
            return NSItemProvider(object: ("folder:" + group.id) as NSString)
        } preview: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Theme.accent)
                Text(group.name).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(Theme.hoverRaised, in: RoundedRectangle(cornerRadius: 8))
        }
        .hoverTip({ anchor in
            PaneTip(title: group.name,
                    detail: group.sessions.count == 1
                        ? "1 sessão" : "\(group.sessions.count) sessões",
                    indicator: nil, anchor: anchor)
        }, update: { scheduleTip($0) })

        if isOpen {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(group.sessions) { summary in
                    row(for: summary, in: group.id)
                }
                if group.sessions.isEmpty {
                    Text("nenhuma conversa")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.leading, 10)
                        .frame(height: 28)
                }
            }
            .padding(.leading, 22)
            .padding(.bottom, 4)
            .transition(.opacity)
        }
    }

    private func scheduleTip(_ next: PaneTip?) {
        tipTask?.cancel()
        guard let next else {
            HoverTipPanel.shared.hide()
            return
        }
        let delay = HoverTipPanel.shared.isVisible ? 60 : 350
        tipTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            HoverTipPanel.shared.show(next)
        }
    }

    private func badge(for summary: SessionSummary) -> TaskBadge? {
        worktrees.worktree(for: summary.id).map {
            TaskBadge.make(worktree: $0, pullRequests: monitor.pullRequests(for: summary.id).map(\.pullRequest))
        }
    }

    private func hoverLines(for summary: SessionSummary) -> [PaneTip.Line] {
        worktrees.worktree(for: summary.id).map {
            PaneTip.Line.task($0, bars: monitor.pullRequests(for: summary.id))
        } ?? []
    }

    private var deleteMessage: String {
        var text = "A conversa e o histórico dela serão removidos permanentemente."
        if let summary = pendingDelete, let worktree = worktrees.worktree(for: summary.id) {
            text += " As worktrees em \(worktree.displayLocation) continuam no disco."
        }
        return text
    }

    private func row(for summary: SessionSummary, in folderID: String?) -> some View {
        let inFolder = workspace.membership[summary.id.uuidString] != nil
        return SessionRow(
            summary: summary,
            indicator: workspace.indicator(for: summary.id),
            task: badge(for: summary),
            isSelected: workspace.selectedID == summary.id,
            select: { Task { await workspace.select(summary.id) } },
            rename: { name in
                Task { await workspace.renameSession(summary.id, to: name) }
            },
            unfile: inFolder ? {
                withAnimation(.easeInOut(duration: 0.22)) {
                    workspace.moveSession(summary.id, toFolder: nil)
                }
            } : nil,
            delete: { pendingDelete = summary }
        )
        .hoverTip({ anchor in
            var detail = [String]()
            if inFolder, let group = workspace.folderGroups.first(where: {
                $0.id == workspace.membership[summary.id.uuidString]
            }) { detail.append(group.name) }
            if let harness = summary.harnesses.last {
                detail.append(HarnessBadge.name(for: harness))
            }
            detail.append(summary.updatedAt.formatted(.relative(presentation: .named)))
            return PaneTip(title: summary.title,
                           detail: detail.joined(separator: " · "),
                           indicator: workspace.indicator(for: summary.id),
                           anchor: anchor,
                           lines: hoverLines(for: summary))
        }, update: { scheduleTip($0) })
        .opacity(dragging == summary.id ? 0 : 1)
        .onDrop(of: [.plainText], delegate: SessionDropDelegate(
            target: summary.id, areaFolderID: folderID,
            workspace: workspace, dragging: $dragging))
        .onDrag {
            dragging = summary.id
            dragGeneration += 1
            let generation = dragGeneration
            let provider = DragTracker(object: summary.id.uuidString as NSString)
            provider.onEnd = {
                Task { @MainActor in
                    guard dragGeneration == generation else { return }
                    withAnimation(.easeOut(duration: 0.15)) { dragging = nil }
                }
            }
            return provider
        } preview: {
            SessionRow(
                summary: summary,
                indicator: workspace.indicator(for: summary.id),
                isSelected: true,
                select: {}, rename: { _ in }
            )
            .frame(width: 250, alignment: .leading)
            .background(Theme.hoverRaised, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func dropBinding(_ folderID: String) -> Binding<Bool> {
        Binding(
            get: { dropTarget == folderID },
            set: { targeted in
                if targeted { dropTarget = folderID }
                else if dropTarget == folderID { dropTarget = nil }
            }
        )
    }

    private func receiveDrop(_ providers: [NSItemProvider], into folderID: String?) -> Bool {
        dragging = nil
        let readable = providers.filter { $0.canLoadObject(ofClass: NSString.self) }
        guard !readable.isEmpty else { return false }
        for provider in readable {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? String else { return }
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if string.hasPrefix("folder:") {
                            workspace.moveFolder(String(string.dropFirst(7)), before: folderID)
                        } else if let id = UUID(uuidString: string) {
                            workspace.moveSession(id, toFolder: folderID)
                        }
                    }
                }
            }
        }
        return true
    }

    private func toggleCollapse(_ id: String) {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.22)) {
                if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
            }
        }
    }
}

private struct SessionDropDelegate: DropDelegate {
    let target: UUID
    let areaFolderID: String?
    let workspace: WorkspaceModel
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            workspace.placeSession(dragging, near: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil }
        if dragging != nil { return true }

        let providers = info.itemProviders(for: [.plainText])
        guard !providers.isEmpty else { return false }
        let workspace = self.workspace
        let areaFolderID = self.areaFolderID
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? String,
                      string.hasPrefix("folder:") else { return }
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        workspace.moveFolder(String(string.dropFirst(7)),
                                             before: areaFolderID)
                    }
                }
            }
        }
        return true
    }
}

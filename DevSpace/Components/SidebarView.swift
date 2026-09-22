import SwiftUI
import UniformTypeIdentifiers
import HarnessCore

private final class DragTracker: NSItemProvider {
    var onEnd: (() -> Void)?
    deinit { onEnd?() }
}

struct SidebarView: View {
    @Bindable var workspace: WorkspaceModel

    @State private var collapsed: Set<String> = []
    @State private var dropTarget: String?
    @State private var dragging: UUID?
    @State private var dragGeneration = 0
    @State private var pendingDelete: SessionSummary?

    @State private var tipTask: Task<Void, Never>?

    var body: some View {
        list
            .safeAreaInset(edge: .top, spacing: 0) { caption }
            .searchable(text: $workspace.search, placement: .sidebar, prompt: "Buscar sessões")
            .navigationSplitViewColumnWidth(min: 148, ideal: 280, max: 360)
            .background(SidebarColumnConfigurator())

            .toolbar {
                ToolbarItem { Spacer() }
                ToolbarItem {
                    Menu {
                        Button("Nova sessão") { Task { await workspace.newSession() } }
                        Menu("Nova sessão com") {
                            ForEach(workspace.availableHarnesses, id: \.rawValue) { harness in
                                Button {
                                    Task { await workspace.newSession(harness: harness) }
                                } label: {
                                    Label {
                                        Text(HarnessBadge.name(for: harness))
                                    } icon: {
                                        HarnessBadge(harness: harness, size: 13)
                                    }
                                }
                            }
                        }
                        Button("Nova pasta") { workspace.addFolder() }
                    } label: {
                        Label("Nova", systemImage: "plus")
                    }
                    .help("Nova sessão ou nova pasta")
                }
            }
    }

    // MARK: - Lista

    @ViewBuilder
    private var list: some View {
        List(selection: selectionBinding) {
            ForEach(workspace.folderGroups) { group in
                Section(isExpanded: expansion(group.id)) {
                    ForEach(group.sessions) { summary in
                        row(for: summary, in: group.id)
                    }
                    if group.sessions.isEmpty {
                        Text("nenhuma conversa")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    FolderHeader(
                        name: group.name,
                        count: group.sessions.count,
                        isOpen: !collapsed.contains(group.id),
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
                            Text(group.name).font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
                        .environment(\.colorScheme, .dark)
                    }
                    .hoverTip({ anchor in
                        PaneTip(title: group.name,
                                detail: group.sessions.count == 1
                                    ? "1 sessão" : "\(group.sessions.count) sessões",
                                indicator: nil, anchor: anchor)
                    }, update: { scheduleTip($0) })
                }
            }

            if !workspace.folderGroups.isEmpty {
                Divider()
                    .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
                    .selectionDisabled()
            }

            Button {
                Task { await workspace.newSession() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                    Text("Nova sessão")
                        .font(.system(size: 13))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
                        .contextMenu {
                ForEach(workspace.availableHarnesses, id: \.rawValue) { harness in
                    Button("Nova sessão com \(HarnessBadge.name(for: harness))") {
                        Task { await workspace.newSession(harness: harness) }
                    }
                }
            }
            .buttonStyle(.plain)
            .selectionDisabled()
            .help("Iniciar uma sessão nova")

            ForEach(workspace.looseSessions) { summary in
                row(for: summary, in: nil)
            }
        }
        .listStyle(.sidebar)
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            receiveDrop(providers, into: nil)
        }
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
                }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("A conversa e o histórico dela serão removidos permanentemente.")
        }
        .overlay {
            if workspace.folderGroups.isEmpty, workspace.looseSessions.isEmpty {
                if workspace.search.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma conversa",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Crie uma sessão nova para começar.")
                    )
                } else {
                    ContentUnavailableView.search(text: workspace.search)
                }
            }
        }
    }

    private var caption: some View {
        Text("Sessões")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 4)
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

    // MARK: - Seleção

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { workspace.selectedID },
            set: { id in
                guard let id else { return }
                Task { await workspace.select(id) }
            }
        )
    }

    private func row(for summary: SessionSummary, in folderID: String?) -> some View {
        let inFolder = workspace.membership[summary.id.uuidString] != nil
        return SessionRow(
            summary: summary,
            indicator: workspace.indicator(for: summary.id),
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
            detail.append(summary.updatedAt.formatted(.relative(presentation: .named)))
            return PaneTip(title: summary.title,
                           detail: detail.joined(separator: " · "),
                           indicator: workspace.indicator(for: summary.id),
                           anchor: anchor)
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
                select: {}, rename: { _ in }
            )
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(width: 250, alignment: .leading)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
            .environment(\.colorScheme, .dark)
        }
        .padding(.leading, folderID != nil ? 10 : 0)
        .tag(summary.id)
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

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { open in
                withAnimation(.easeInOut(duration: 0.22)) {
                    if open { collapsed.remove(id) } else { collapsed.insert(id) }
                }
            }
        )
    }

    private func toggleCollapse(_ id: String) {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.22)) {
                if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
            }
        }
    }

}

private struct SidebarColumnConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            var probe: NSView? = view
            while let current = probe, !(current is NSSplitView) {
                probe = current.superview
            }
            guard let split = probe as? NSSplitView,
                  let controller = split.delegate as? NSSplitViewController,
                  let item = controller.splitViewItems.first else { return }
            item.canCollapse = false
            item.minimumThickness = 148
            item.maximumThickness = 360
        }
    }
}

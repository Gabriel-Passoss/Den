import SwiftUI
import UniformTypeIdentifiers

enum FileTypeIcon {
    private static var cache: [String: NSImage] = [:]

    private static let overrides: [String: String] = [
        "ts": "com.microsoft.typescript",
    ]

    private static let aliases: [String: String] = [
        "jsx": "react", "tsx": "react",
        "mjs": "js", "cjs": "js",
        "yaml": "yml",
        "jpeg": "jpg",
    ]

    static func image(for name: String) -> NSImage {
        let ext = (name as NSString).pathExtension.lowercased()
        if let cached = cache[ext] { return cached }

        let assetName = "filetype-" + (aliases[ext] ?? ext)
        if let custom = NSImage(named: assetName) {
            cache[ext] = custom
            return custom
        }
        let type: UTType? = overrides[ext].flatMap { UTType($0) }
            ?? UTType(filenameExtension: ext)
            ?? UTType(filenameExtension: ext, conformingTo: .sourceCode)
        let image = NSWorkspace.shared.icon(for: type ?? .plainText)
        cache[ext] = image
        return image
    }
}

struct GitChangesPanel: View {
    let model: GitChangesModel
    let directory: URL

    @State private var selection: String?
    @State private var openFolders: Set<String> = []
    @State private var collapsedRepos: Set<String> = []

    private static let listRowHeight: CGFloat = 30
    private static let maxListHeight: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            summary
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var summary: some View {
        let totals = model.repos.flatMap(\.files).reduce(into: (added: 0, removed: 0)) {
            let counts = Self.counts(of: $1)
            $0.added += counts.added
            $0.removed += counts.removed
        }
        return HStack(spacing: 8) {
            if model.changeCount > 0 {
                Text(model.changeCount == 1 ? "1 arquivo" : "\(model.changeCount) arquivos")
                    .foregroundStyle(Theme.textSecondary)
                Text("+\(totals.added)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.added)
                Text("−\(totals.removed)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.removed)
                if model.reviewedCount > 0 {
                    Text("· \(model.reviewedCount)/\(model.changeCount) revisados")
                        .foregroundStyle(model.reviewedCount == model.changeCount
                                         ? Theme.added : Theme.textTertiary)
                        .help("Arquivos revisados")
                }
            } else {
                Text("Alterações do Git")
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 4)
            if model.isLoading, model.loadedOnce {
                ProgressView().controlSize(.mini)
            }
            Button {
                Task { await model.load(directory: directory, force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .iconLabel(size: 26)
            }
            .buttonStyle(.denGhost(radius: 7))
            .disabled(model.isLoading)
            .help("Atualizar alterações")
            .accessibilityLabel("Atualizar alterações")
        }
        .font(.system(size: 13))
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !model.loadedOnce {
            placeholder { ProgressView().controlSize(.small) }
        } else if !model.hasRepo {
            placeholder {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.textFaint)
                Text("Sem repositório Git nesta pasta")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
        } else if model.changeCount == 0 {
            placeholder {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.added)
                Text("Sem alterações")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if let branch = model.repos.first?.branch {
                    Text("Tudo limpo em \(branch)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        } else {
            let selected = selectedFile
            fileList
            if let selected {
                fileHeader(selected.file, in: selected.repo)
                diff(selected.file)
            } else {
                Spacer()
            }
        }
    }

    private func placeholder(@ViewBuilder body: () -> some View) -> some View {
        VStack(spacing: 8) { body() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func key(_ file: GitChangesModel.FileChange, in repo: GitChangesModel.Repo) -> String {
        repo.id + "/" + file.path
    }

    private var selectedFile: (file: GitChangesModel.FileChange, repo: GitChangesModel.Repo)? {
        let all = model.repos.flatMap { repo in repo.files.map { (file: $0, repo: repo) } }
        if let selection, let match = all.first(where: { key($0.file, in: $0.repo) == selection }) {
            return match
        }
        return all.first { !model.isReviewed($0.file, in: $0.repo) } ?? all.first
    }

    private var visibleRowCount: Int {
        model.repos.reduce(0) { total, repo in
            var rows = model.repos.count > 1 ? 1 : 0
            if !collapsedRepos.contains(repo.id) {
                for item in repo.items {
                    switch item {
                    case .single: rows += 1
                    case .group(let dir, let files):
                        rows += 1
                        if openFolders.contains(repo.id + "/" + dir) { rows += files.count }
                    }
                }
                if repo.truncatedFiles { rows += 1 }
            }
            return total + rows
        }
    }

    private var fileList: some View {
        let height = min(CGFloat(visibleRowCount) * (Self.listRowHeight + 1) + 12,
                         Self.maxListHeight)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(model.repos) { repo in
                    if model.repos.count > 1 {
                        repoHeader(repo)
                    }
                    if !collapsedRepos.contains(repo.id) {
                        ForEach(repo.items) { item in
                            switch item {
                            case .single(let file):
                                fileRow(file, in: repo)
                            case .group(let dir, let files):
                                groupRow(dir: dir, files: files, in: repo)
                                if openFolders.contains(repo.id + "/" + dir) {
                                    ForEach(files) { file in
                                        fileRow(file, in: repo, within: dir)
                                            .padding(.leading, 18)
                                    }
                                }
                            }
                        }
                        if repo.truncatedFiles {
                            Text("Mostrando só os primeiros arquivos")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 10)
                                .frame(height: Self.listRowHeight)
                        }
                    }
                }
            }
            .padding(6)
        }
        .scrollIndicators(.automatic)
        .frame(height: height)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func repoHeader(_ repo: GitChangesModel.Repo) -> some View {
        let isCollapsed = collapsedRepos.contains(repo.id)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                if isCollapsed {
                    collapsedRepos.remove(repo.id)
                } else {
                    collapsedRepos.insert(repo.id)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(repo.name)
                    .font(.system(size: 12.5, weight: .semibold))
                if let branch = repo.branch {
                    Text(branch)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                Text("\(repo.files.count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.listRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.denGhost(radius: 7))
        .help(repo.root.path)
        .accessibilityLabel(isCollapsed ? "Expandir \(repo.name)" : "Recolher \(repo.name)")
    }

    private func fileRow(_ file: GitChangesModel.FileChange, in repo: GitChangesModel.Repo,
                         within dir: String? = nil) -> some View {
        let rowKey = key(file, in: repo)
        let isSelected = selectedFile.map { key($0.file, in: $0.repo) } == rowKey
        let done = model.isReviewed(file, in: repo)
        let counts = Self.counts(of: file)
        let display = dir.map { String(file.path.dropFirst($0.count)) }
            ?? sessionRelativePath(of: file.path, in: repo)
        return HStack(spacing: 8) {
            Button {
                selection = rowKey
            } label: {
                HStack(spacing: 9) {
                    badge(for: file.state)
                    pathText(display: display)
                        .opacity(done ? 0.5 : 1)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 4)
                    if counts.added > 0 {
                        Text("+\(counts.added)")
                            .foregroundStyle(Theme.added)
                    }
                    if counts.removed > 0 {
                        Text("−\(counts.removed)")
                            .foregroundStyle(Theme.removed)
                    }
                }
                .font(.system(size: 11.5, design: .monospaced))
                .padding(.leading, 8)
                .frame(height: Self.listRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(file.path)

            reviewButton(done: done) {
                model.setReviewed(!done, for: file, in: repo)
            }
            .padding(.trailing, 4)
        }
        .background(isSelected ? Theme.hover : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func groupRow(dir: String, files: [GitChangesModel.FileChange],
                          in repo: GitChangesModel.Repo) -> some View {
        let folderKey = repo.id + "/" + dir
        let isOpen = openFolders.contains(folderKey)
        let reviewed = files.count { model.isReviewed($0, in: repo) }
        let allDone = reviewed == files.count && !files.isEmpty
        let displayDir = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { openFolders.remove(folderKey) } else { openFolders.insert(folderKey) }
                }
            } label: {
                HStack(spacing: 9) {
                    badge(for: .untracked)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: isOpen ? "folder.fill" : "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(allDone ? Theme.textTertiary : Theme.accent)
                    pathText(display: sessionRelativePath(of: displayDir, in: repo) + "/")
                        .opacity(allDone ? 0.5 : 1)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 4)
                    Text(reviewed > 0 ? "\(reviewed)/\(files.count)" : "\(files.count)")
                        .foregroundStyle(allDone ? Theme.added : Theme.textTertiary)
                }
                .font(.system(size: 11.5, design: .monospaced))
                .padding(.leading, 8)
                .frame(height: Self.listRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(dir)

            reviewButton(done: allDone) {
                withAnimation(.easeOut(duration: 0.15)) {
                    for file in files { model.setReviewed(!allDone, for: file, in: repo) }
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func reviewButton(done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(done ? Theme.added : Theme.textFaint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(done ? "Desmarcar como revisado" : "Marcar como revisado")
        .accessibilityLabel(done ? "Revisado" : "Não revisado")
    }

    private func fileHeader(_ file: GitChangesModel.FileChange,
                            in repo: GitChangesModel.Repo) -> some View {
        let done = model.isReviewed(file, in: repo)
        return HStack(spacing: 8) {
            Image(nsImage: FileTypeIcon.image(for: file.name))
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(sessionRelativePath(of: file.path, in: repo))
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .help(file.path)
            Spacer(minLength: 6)
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    model.setReviewed(!done, for: file, in: repo)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: done ? "checkmark.circle.fill" : "checkmark.circle")
                    Text(done ? "Revisado" : "Marcar revisado")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(done ? Theme.added : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
            }
            .buttonStyle(DenButtonStyle(kind: .secondary, radius: 7))
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 42)
        .background(Theme.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func diff(_ file: GitChangesModel.FileChange) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if file.lines.isEmpty {
                    Text(file.state == .deleted ? "Arquivo apagado" : "Sem diff para mostrar")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(14)
                }
                ForEach(file.lines) { line in
                    diffRow(line)
                }
                if file.truncated {
                    Text("Diff longo — mostrando o início")
                        .font(.system(size: 11.5))
                        .italic()
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 4)
            .textSelection(.enabled)
        }
        .id(file.path)
        .frame(maxHeight: .infinity)
    }

    private func diffRow(_ line: GitDisplayLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.kind == .hunk ? "⋯" : line.number.map(String.init) ?? "")
                .foregroundStyle(Theme.textFaint)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)
            Text(sign(for: line.kind))
                .foregroundStyle(signColor(for: line.kind))
                .frame(width: 14, alignment: .leading)
            Text(line.text)
                .italic(line.kind == .hunk)
                .foregroundStyle(line.kind == .hunk ? Theme.hunk : Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 1.5)
        .background(background(for: line.kind))
    }

    private func sign(for kind: GitDiffLine.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .hunk, .context: " "
        }
    }

    private func signColor(for kind: GitDiffLine.Kind) -> Color {
        switch kind {
        case .added: Theme.added
        case .removed: Theme.removed
        case .hunk, .context: Theme.textFaint
        }
    }

    private func background(for kind: GitDiffLine.Kind) -> Color {
        switch kind {
        case .added: Theme.addedFill
        case .removed: Theme.removedFill
        case .hunk: Theme.hunkFill
        case .context: .clear
        }
    }

    static func counts(of file: GitChangesModel.FileChange) -> (added: Int, removed: Int) {
        file.lines.reduce(into: (added: 0, removed: 0)) { totals, line in
            switch line.kind {
            case .added: totals.added += 1
            case .removed: totals.removed += 1
            case .hunk, .context: break
            }
        }
    }

    private func sessionRelativePath(of path: String,
                                     in repo: GitChangesModel.Repo) -> String {
        let full = repo.root.appending(path: path).standardizedFileURL.path
        let base = directory.standardizedFileURL.path
        let fullParts = full.split(separator: "/").map(String.init)
        let baseParts = base.split(separator: "/").map(String.init)
        var shared = 0
        while shared < min(fullParts.count, baseParts.count),
              fullParts[shared] == baseParts[shared] {
            shared += 1
        }
        let ups = Array(repeating: "..", count: baseParts.count - shared)
        return (ups + fullParts[shared...]).joined(separator: "/")
    }

    private func pathText(display relative: String) -> Text {
        let trimmed = relative.hasSuffix("/") ? String(relative.dropLast()) : relative
        let folder = (trimmed as NSString).deletingLastPathComponent
        let name = (trimmed as NSString).lastPathComponent + (relative.hasSuffix("/") ? "/" : "")
        let nameText = Text(name).foregroundStyle(Theme.text)
        guard !folder.isEmpty else { return nameText }
        let folderText = Text(folder + "/").foregroundStyle(Theme.textTertiary)
        return Text("\(folderText)\(nameText)")
    }

    private func badge(for state: GitFileState) -> some View {
        Text(state.badge)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(badgeColor(for: state))
            .frame(width: 14)
            .accessibilityLabel(accessibilityName(for: state))
    }

    private func badgeColor(for state: GitFileState) -> Color {
        switch state {
        case .modified: Theme.modified
        case .added, .untracked: Theme.added
        case .deleted: Theme.removed
        case .renamed: Theme.renamed
        case .conflicted: Theme.accent
        }
    }

    private func accessibilityName(for state: GitFileState) -> String {
        switch state {
        case .modified: "Modificado"
        case .added: "Adicionado"
        case .deleted: "Apagado"
        case .renamed: "Renomeado"
        case .untracked: "Não rastreado"
        case .conflicted: "Em conflito"
        }
    }

}

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
    var close: (() -> Void)?

    @State private var collapsedFiles: Set<String> = []
    @State private var openFolders: Set<String> = []
    @State private var collapsedRepos: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 7) {
            Text("Alterações")
                .font(.system(size: 12, weight: .semibold))
            if model.changeCount > 0 {
                Text(model.reviewedCount > 0
                     ? "\(model.reviewedCount)/\(model.changeCount)"
                     : "\(model.changeCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.reviewedCount == model.changeCount
                                     ? AnyShapeStyle(.green)
                                     : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                    .help(model.reviewedCount > 0 ? "Arquivos revisados" : "Arquivos alterados")
            }
            Spacer()
            if model.isLoading, model.loadedOnce {
                ProgressView().controlSize(.mini)
            }
            Button {
                Task { await model.load(directory: directory, force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
            .help("Atualizar alterações")
            .accessibilityLabel("Atualizar alterações")
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Recolher painel (⌥⌘0)")
                .accessibilityLabel("Recolher painel de alterações")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Conteúdo

    @ViewBuilder
    private var content: some View {
        if !model.loadedOnce {
            placeholder { ProgressView().controlSize(.small) }
        } else if !model.hasRepo {
            placeholder {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("Sem repositório Git nesta pasta")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else if model.changeCount == 0 {
            placeholder {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(.green.opacity(0.8))
                Text("Sem alterações")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let branch = model.repos.first?.branch {
                    Text("Tudo limpo em \(branch)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6,
                           pinnedViews: .sectionHeaders) {
                    ForEach(model.repos) { repo in
                        if model.repos.count > 1 {
                            repoHeader(repo)
                        }
                        if !collapsedRepos.contains(repo.id) {
                            ForEach(repo.items) { item in
                                switch item {
                                case .single(let file):
                                    Section {
                                        fileBody(file, in: repo)
                                    } header: {
                                        fileHeader(file, in: repo)
                                    }
                                case .group(let dir, let files):
                                    groupCard(dir: dir, files: files, in: repo)
                                }
                            }
                            if repo.truncatedFiles {
                                Text("Mostrando só os primeiros arquivos")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    private func placeholder(@ViewBuilder body: () -> some View) -> some View {
        VStack(spacing: 8) { body() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Caminho relativo à sessão

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
        let folder = (relative as NSString).deletingLastPathComponent
        let name = (relative as NSString).lastPathComponent
        let nameText = Text(name).font(.system(size: 12, weight: .medium))
        guard !folder.isEmpty else { return nameText }
        return Text(folder + "/")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            + nameText
    }

    private func repoHeader(_ repo: GitChangesModel.Repo) -> some View {
        let isCollapsed = collapsedRepos.contains(repo.id)
        let reviewed = repo.files.count { model.isReviewed($0, in: repo) }
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                if isCollapsed {
                    collapsedRepos.remove(repo.id)
                } else {
                    collapsedRepos.insert(repo.id)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(repo.name)
                    .font(.system(size: 11, weight: .semibold))
                if let branch = repo.branch {
                    Text(branch)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isCollapsed, !repo.files.isEmpty {
                    Text(reviewed > 0 ? "\(reviewed)/\(repo.files.count)"
                                      : "\(repo.files.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(reviewed == repo.files.count
                                         ? AnyShapeStyle(.green)
                                         : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(repo.root.path)
        .accessibilityLabel(isCollapsed ? "Expandir \(repo.name)" : "Recolher \(repo.name)")
    }

    // MARK: - Grupos de arquivos novos (pastas 100% não rastreadas)

    @ViewBuilder
    private func groupCard(dir: String, files: [GitChangesModel.FileChange],
                           in repo: GitChangesModel.Repo) -> some View {
        let key = repo.id + "/" + dir
        let isOpen = openFolders.contains(key)
        let reviewed = files.count { model.isReviewed($0, in: repo) }
        let allDone = reviewed == files.count && !files.isEmpty
        let displayDir = dir.hasSuffix("/") ? String(dir.dropLast()) : dir

        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(allDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                pathText(display: sessionRelativePath(of: displayDir, in: repo))
                    .foregroundStyle(allDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(reviewed > 0 ? "\(reviewed)/\(files.count)" : "\(files.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(allDone ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                badge(for: .untracked)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { openFolders.remove(key) } else { openFolders.insert(key) }
                }
            }
            .help(dir)

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    for file in files { model.setReviewed(!allDone, for: file, in: repo) }
                }
            } label: {
                Image(systemName: allDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(allDone ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(allDone ? "Desmarcar todos como revisados" : "Marcar todos como revisados")
            .accessibilityLabel(allDone ? "Pasta revisada" : "Pasta não revisada")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary, lineWidth: 1))

        if isOpen {
            ForEach(files) { file in
                Section {
                    fileBody(file, in: repo)
                        .padding(.leading, 14)
                } header: {
                    fileHeader(file, in: repo, within: dir)
                        .padding(.leading, 14)
                }
            }
        }
    }

    // MARK: - Arquivos

    private func fileHeader(_ file: GitChangesModel.FileChange,
                            in repo: GitChangesModel.Repo,
                            within dir: String? = nil) -> some View {
        let key = repo.id + "/" + file.path
        let done = model.isReviewed(file, in: repo)
        let display = dir.map { String(file.path.dropFirst($0.count)) }
            ?? sessionRelativePath(of: file.path, in: repo)
        return HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(nsImage: FileTypeIcon.image(for: file.name))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .opacity(done ? 0.55 : 1)
                pathText(display: display)
                    .foregroundStyle(done ? AnyShapeStyle(.secondary)
                                          : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                badge(for: file.state)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    if collapsedFiles.contains(key) {
                        collapsedFiles.remove(key)
                    } else {
                        collapsedFiles.insert(key)
                    }
                }
            }
            .help(file.path)

            reviewButton(for: file, in: repo)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary, lineWidth: 1))
    }

    @ViewBuilder
    private func fileBody(_ file: GitChangesModel.FileChange,
                          in repo: GitChangesModel.Repo) -> some View {
        let key = repo.id + "/" + file.path
        let done = model.isReviewed(file, in: repo)
        if !done, !collapsedFiles.contains(key), !file.lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(file.lines) { line in
                    diffRow(line)
                }
                if file.truncated {
                    Text("Diff longo — mostrando o início")
                        .font(.system(size: 10))
                        .italic()
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary, lineWidth: 1))
        }
    }

    private func diffRow(_ line: GitDisplayLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.kind == .hunk ? "⋯" : line.number.map(String.init) ?? "")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .italic(line.kind == .hunk)
                .foregroundStyle(line.kind == .hunk
                                 ? AnyShapeStyle(.tertiary)
                                 : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(background(for: line.kind))
    }

    private func background(for kind: GitDiffLine.Kind) -> Color {
        switch kind {
        case .added: .green.opacity(0.13)
        case .removed: .red.opacity(0.13)
        case .hunk, .context: .clear
        }
    }

    private func reviewButton(for file: GitChangesModel.FileChange,
                              in repo: GitChangesModel.Repo) -> some View {
        let done = model.isReviewed(file, in: repo)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                model.setReviewed(!done, for: file, in: repo)
            }
        } label: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(done ? "Desmarcar como revisado" : "Marcar como revisado")
        .accessibilityLabel(done ? "Revisado" : "Não revisado")
    }

    private func badge(for state: GitFileState) -> some View {
        Text(state.badge)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(badgeColor(for: state))
            .frame(width: 16, height: 16)
            .background(badgeColor(for: state).opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(accessibilityName(for: state))
    }

    private func badgeColor(for state: GitFileState) -> Color {
        switch state {
        case .modified: .blue
        case .added, .untracked: .green
        case .deleted: .red
        case .renamed: .purple
        case .conflicted: .orange
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

import SwiftUI

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
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.repos) { repo in
                        if model.repos.count > 1 {
                            repoHeader(repo)
                        }
                        if !collapsedRepos.contains(repo.id) {
                            ForEach(repo.files) { file in
                                if file.isDirectory {
                                    folderCard(file, in: repo)
                                } else {
                                    fileCard(file, in: repo)
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

    // MARK: - Pastas não rastreadas

    private func folderCard(_ file: GitChangesModel.FileChange,
                            in repo: GitChangesModel.Repo) -> some View {
        let key = repo.id + "/" + file.path
        let isOpen = openFolders.contains(key)
        let done = model.isReviewed(file, in: repo)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    Text(file.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    badge(for: file.state)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if isOpen { openFolders.remove(key) } else { openFolders.insert(key) }
                    }
                }
                .help(file.path)

                reviewButton(for: file, in: repo)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if isOpen {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(file.children, id: \.self) { child in
                        HStack(spacing: 5) {
                            Image(systemName: done ? "checkmark.circle.fill" : "doc.text")
                                .font(.system(size: 9))
                                .foregroundStyle(done ? AnyShapeStyle(.green)
                                                      : AnyShapeStyle(.tertiary))
                            Text(child)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if file.children.isEmpty {
                        Text("Pasta vazia")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 30)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
            }
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary, lineWidth: 1))
    }

    // MARK: - Arquivos

    private func fileCard(_ file: GitChangesModel.FileChange,
                          in repo: GitChangesModel.Repo) -> some View {
        let key = repo.id + "/" + file.path
        let done = model.isReviewed(file, in: repo)
        let isOpen = !done && !collapsedFiles.contains(key) && !file.lines.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon(for: file.name))
                        .font(.system(size: 11))
                        .foregroundStyle(done ? AnyShapeStyle(.secondary)
                                              : iconColor(for: file.name))
                    Text(file.name)
                        .font(.system(size: 12, weight: .medium))
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

            if isOpen {
                Divider().opacity(0.5)
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
            }
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary, lineWidth: 1))
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
        case .added: .green
        case .deleted: .red
        case .renamed: .purple
        case .untracked: .secondary
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

    private func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": "swift"
        case "json", "js", "ts", "jsx", "tsx": "curlybraces"
        case "md", "txt": "doc.plaintext"
        case "yml", "yaml", "toml", "plist", "xcconfig": "list.bullet"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg": "photo"
        case "sh", "fish", "zsh", "bash": "terminal"
        default: "doc.text"
        }
    }

    private func iconColor(for name: String) -> AnyShapeStyle {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": AnyShapeStyle(.orange)
        case "json", "js", "ts", "jsx", "tsx": AnyShapeStyle(.yellow)
        default: AnyShapeStyle(.secondary)
        }
    }
}

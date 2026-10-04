import SwiftUI
import AppKit
import DenMemory

struct MemoryPanel: View {
    @Bindable var memory: MemoryModel
    let chat: ChatModel

    @State private var layer: MemoryLayer = .project
    @State private var openPage: String?

    private var scope: MemoryScope? {
        switch layer {
        case .user: .user
        case .project: memory.project(for: chat.workingDirectory).map(MemoryScope.project)
        }
    }

    private func pages(in scope: MemoryScope) -> [MemoryPage] {
        _ = memory.revision
        return memory.pages(in: scope)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let scope {
                let pages = pages(in: scope)
                if pages.isEmpty {
                    notice(icon: "brain", title: "Nenhuma memória ainda", detail: layer.emptyExplanation)
                } else {
                    list(pages, in: scope)
                }
            } else {
                notice(icon: "folder.badge.questionmark", title: "Fora de um repositório",
                       detail: "Esta conversa não está num repositório git. A memória de projeto vale por repositório.")
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { memory.reload() }
        .onChange(of: layer) { openPage = nil }
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(MemoryLayer.allCases.reversed(), id: \.self) { candidate in
                Button { layer = candidate } label: {
                    Text(candidate.title)
                        .font(.system(size: 12, weight: layer == candidate ? .medium : .regular))
                        .foregroundStyle(layer == candidate ? Theme.text : Theme.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .hoverFill(selected: layer == candidate)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(layer == candidate ? [.isSelected] : [])
            }
            Spacer()
            Button { chat.captureMemory(atLeast: MemoryModel.leaveThreshold, announcing: true) } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .iconLabel(size: 26)
            }
            .buttonStyle(.denGhost)
            .disabled(!memory.isEnabled || memory.status == .capturing)
            .help("Capturar agora o que esta conversa ensinou")
            .accessibilityLabel("Capturar agora")
            Button(action: openFolder) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .iconLabel(size: 26)
            }
            .buttonStyle(.denGhost)
            .disabled(scope == nil)
            .help("Abrir a pasta da wiki")
            .accessibilityLabel("Abrir pasta")
            Toggle("Memória", isOn: $memory.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(memory.isEnabled ? "Desligar a memória" : "Ligar a memória")
                .accessibilityLabel("Memória")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private func list(_ pages: [MemoryPage], in scope: MemoryScope) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(MemoryCategory.known(in: scope.layer), id: \.self) { category in
                    let group = pages.filter { $0.category == category }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.label.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textFaint)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 2)
                            ForEach(group) { page in
                                MemoryPageRow(page: page, file: memory.file(for: page, in: scope),
                                              isOpen: openPage == page.slug,
                                              toggle: { openPage = openPage == page.slug ? nil : page.slug },
                                              delete: { memory.delete(page, in: scope) })
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private func notice(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Theme.textFaint)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if memory.status == .capturing {
                ProgressView().controlSize(.mini)
            }
            Text(memory.isEnabled ? memory.status.caption
                                  : "Memória desligada: nada é capturado nem enviado ao agente.")
                .font(.system(size: 11))
                .foregroundStyle(memory.isEnabled && memory.status.isFailure ? Theme.alertText : Theme.textTertiary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func openFolder() {
        guard let scope else { return }
        let folder = memory.directory(of: scope)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

import SwiftUI
import AppKit
import HarnessCore

struct ChatComposer: View {
    @Bindable var chat: ChatModel
    let slash: SlashController
    let mentions: MentionController
    let keys: ChatKeyMonitor
    var stickToBottom: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            slashSuggestions
            mentionSuggestions

            if !chat.pendingAttachments.isEmpty {
                pendingAttachmentRow
            }

            TextField("Peça uma alteração…", text: $chat.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.system(size: 13))
                .onSubmit { submit() }

            HStack(spacing: 8) {
                ForEach(chat.knobs.filter { $0.category == .mode }) { KnobBadge(knob: $0, chat: chat) }
                folderBadge
                ForEach(chat.knobs.filter { $0.category != .mode }) { KnobBadge(knob: $0, chat: chat) }
                if chat.isBusy {
                    ProgressView().controlSize(.mini)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(busyLabel(at: context.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if keys.escArmed {
                        Text("Esc duas vezes interrompe")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
                } else if chat.pending != nil || chat.pendingQuestion != nil {
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
                if let context = chat.contextLabel {
                    Text(context)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .help("Tokens no contexto agora")
                }
                Button(action: attachFiles) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Anexar arquivos")
                Button {
                    if chat.isBusy {
                        Task { await chat.stop() }
                    } else {
                        submit()
                    }
                } label: {
                    Image(systemName: chat.isBusy ? "stop.circle.fill"
                                                     : "arrow.up.circle.fill")
                        .font(.system(size: 19))
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeInOut(duration: 0.2), value: chat.isBusy)
                }
                .buttonStyle(.plain)
                .disabled(!chat.isBusy
                          && chat.prompt.trimmingCharacters(in: .whitespaces).isEmpty
                          && chat.pendingAttachments.isEmpty)
                .help(chat.isBusy ? "Parar o que está rodando" : "Enviar mensagem")
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

    @ViewBuilder
    private var slashSuggestions: some View {
        let matches = slash.matches(prompt: chat.prompt, catalog: chat.catalog)
        if !matches.isEmpty {
            SlashCommandList(commands: matches,
                             selection: min(slash.selection, matches.count - 1),
                             group: slash.group,
                             choose: { if slash.run($0, in: chat) { stickToBottom() } },
                             back: { slash.leaveGroup(in: chat) })
        }
    }

    @ViewBuilder
    private var mentionSuggestions: some View {
        let matches = mentions.matches(prompt: chat.prompt)
        if !matches.isEmpty {
            let selected = min(mentions.selection, matches.count - 1)
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
                    .onTapGesture { mentions.accept(candidate, in: chat) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func submit() {
        let text = chat.prompt
        chat.prompt = ""
        stickToBottom()
        Task { await chat.send(text: text) }
    }

    private var pendingAttachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chat.pendingAttachments) { pending in
                    if pending.isImage, let image = ImageCache.decodedImage(pending.data) {
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
            chat.removeAttachment(id)
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
                Text(chat.workingDirectory.lastPathComponent)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary.opacity(0.4), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(chat.workingDirectory.path)
    }

    private func attachFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Anexar"
        panel.directoryURL = chat.workingDirectory
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if Self.imageExtensions.contains(url.pathExtension.lowercased()),
               let image = NSImage(contentsOf: url),
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                chat.attach(imageData: png)
            } else if url.pathExtension.lowercased() == "pdf",
                      let data = try? Data(contentsOf: url) {
                chat.attach(fileData: data, name: url.lastPathComponent,
                               mediaType: "application/pdf")
            } else {
                mentionPath(for: url)
            }
        }
    }

    private func mentionPath(for url: URL) {
        let root = chat.workingDirectory.path
        let path = url.path.hasPrefix(root + "/")
            ? String(url.path.dropFirst(root.count + 1))
            : url.path
        var prompt = chat.prompt
        if !prompt.isEmpty, !prompt.hasSuffix(" ") { prompt += " " }
        chat.prompt = prompt + "@" + path + " "
    }

    private func chooseSessionFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Usar"
        panel.directoryURL = chat.workingDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await chat.choose(directory: url) }
    }

    private var visibleStatus: String? {
        let status = chat.status
        guard status.hasPrefix("falhou") || status.hasPrefix("encerrada") else { return nil }
        return status.prefix(1).uppercased() + status.dropFirst()
    }

    private func busyLabel(at now: Date) -> String {
        let verb = chat.compactingSince == nil ? "Pensando" : "Compactando"
        guard let start = chat.compactingSince ?? chat.turnStartedAt else { return verb }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60
            ? "\(verb) · \(seconds)s"
            : "\(verb) · \(seconds / 60)m \(seconds % 60)s"
    }

    private static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp"]
}

import SwiftUI
import AppKit
import HarnessCore

struct ChatComposer: View {
    @Bindable var chat: ChatModel
    let slash: SlashController
    let mentions: MentionController
    let keys: ChatKeyMonitor
    var stickToBottom: () -> Void

    @State private var focusRequested = false

    private static let placeholder = "Peça uma alteração…"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            slashSuggestions
            mentionSuggestions

            if !chat.pendingAttachments.isEmpty || !chat.pendingPastes.isEmpty {
                pendingAttachmentRow
            }

            ComposerTextView(text: $chat.prompt, focusRequested: $focusRequested,
                             placeholder: Self.placeholder,
                             onSubmit: submit,
                             onPaste: { chat.capturePaste($0) })
                .overlay(alignment: .topLeading) {
                    if chat.prompt.isEmpty {
                        Text(Self.placeholder)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)

            ViewThatFits(in: .horizontal) {
                controls(.full)
                controls(.medium)
                controls(.compact)
            }
        }
        .padding(8)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.borderControl, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 4)
        .overlay(alignment: .topLeading) { statusChip }
        .padding(.horizontal, 32)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .frame(maxWidth: 784)
        .frame(maxWidth: .infinity)
    }

    enum Density { case full, medium, compact }

    private func controls(_ density: Density) -> some View {
        HStack(spacing: 6) {
            folderChip(compact: density == .compact)
            ForEach(chat.knobs.filter { $0.category == .mode }) {
                KnobBadge(knob: $0, chat: chat, compact: density != .full)
            }
            Spacer(minLength: 6)
            if chat.contextTokens > 0 || chat.contextWindow != nil {
                ContextRing(chat: chat, showsLabel: density != .compact)
            }
            ForEach(chat.knobs.filter { $0.category != .mode }) { knob in
                if knob.category == .effort, EffortPicker.fits(knob) {
                    EffortPicker(knob: knob, chat: chat, showsLabel: density != .compact)
                } else {
                    KnobBadge(knob: knob, chat: chat, compact: density != .full)
                }
            }
            Button(action: attachFiles) {
                Image(systemName: "paperclip")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .iconLabel(size: 32)
            }
            .buttonStyle(.denGhost(radius: 9))
            .help("Anexar arquivos")
            .accessibilityLabel("Anexar arquivos")
            sendButton
        }
    }

    private var sendButton: some View {
        Button {
            if chat.isBusy {
                Task { await chat.stop() }
            } else {
                submit()
            }
        } label: {
            Image(systemName: chat.isBusy ? "stop.fill" : "arrow.up")
                .font(.system(size: chat.isBusy ? 12 : 15, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(DenButtonStyle(kind: .primary, radius: 10))
        .disabled(!chat.isBusy
                  && chat.prompt.trimmingCharacters(in: .whitespaces).isEmpty
                  && chat.pendingAttachments.isEmpty
                  && chat.pendingPastes.isEmpty)
        .help(chat.isBusy ? "Parar o que está rodando" : "Enviar mensagem")
        .accessibilityLabel(chat.isBusy ? "Parar" : "Enviar mensagem")
    }

    @ViewBuilder
    private var statusChip: some View {
        let waiting = chat.pending != nil || chat.pendingQuestion != nil
        let interrupting = chat.isBusy && keys.escArmed
        if !waiting, interrupting || (!chat.isBusy && visibleStatus != nil) {
            HStack(spacing: 7) {
                if interrupting {
                    Image(systemName: "escape")
                        .foregroundStyle(Theme.accentSoft)
                    Text("Esc de novo interrompe")
                } else if let status = visibleStatus {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.modified)
                    Text(status)
                        .lineLimit(1)
                }
            }
            .transition(.opacity)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Theme.canvas.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderStrong, lineWidth: 1))
            .fixedSize()
            .offset(x: 10, y: -30)
            .allowsHitTesting(false)
        }
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
                .padding(4)
                .background(Theme.canvas.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    @ViewBuilder
    private var mentionSuggestions: some View {
        let matches = mentions.matches(prompt: chat.prompt)
        if !matches.isEmpty {
            let selected = min(mentions.selection, matches.count - 1)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, candidate in
                    HStack(spacing: 8) {
                        Image(systemName: candidate.isDirectory ? "folder" : "doc.text")
                            .font(.system(size: 11))
                            .frame(width: 14)
                            .foregroundStyle(index == selected ? Theme.accent : Theme.textTertiary)
                        Text(candidate.path)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(index == selected ? Theme.hoverRaised : .clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .foregroundStyle(index == selected ? Theme.text : Theme.textSecondary)
                    .contentShape(Rectangle())
                    .onTapGesture { mentions.accept(candidate, in: chat) }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Theme.borderStrong, lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                removeButton(help: "Remover imagem") {
                                    chat.removeAttachment(pending.id)
                                }
                            }
                    } else {
                        HStack(spacing: 7) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.accent)
                            Text(pending.name ?? "arquivo")
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 160, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 56)
                        .background(Theme.hover, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(alignment: .topTrailing) {
                            removeButton(help: "Remover arquivo") {
                                chat.removeAttachment(pending.id)
                            }
                        }
                    }
                }
                ForEach(chat.pendingPastes) { pasteChip($0) }
            }
            .padding(.top, 2)
            .padding(.horizontal, 4)
        }
        .frame(height: 62)
    }

    private func pasteChip(_ paste: PastedText) -> some View {
        Button {
            chat.expandPaste(paste.id)
            focusRequested = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.plaintext")
                        .foregroundStyle(Theme.accent)
                    Text("Texto colado")
                        .fontWeight(.medium)
                }
                .font(.system(size: 11.5))
                Text(paste.headline)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(LongText.lineLabel(paste.lineCount))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(width: 170, height: 56, alignment: .leading)
            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("Clique para mostrar o texto inteiro no campo")
        .overlay(alignment: .topTrailing) {
            removeButton(help: "Remover texto colado") { chat.removePaste(paste.id) }
        }
    }

    private func removeButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text, Theme.canvas.opacity(0.85))
        }
        .buttonStyle(.plain)
        .padding(3)
        .help(help)
        .accessibilityLabel(help)
    }

    private func folderChip(compact: Bool) -> some View {
        Button(action: chooseSessionFolder) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                if !compact {
                    Text(chat.workingDirectory.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160)
                }
                Chevron(size: 8)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.denGhost)
        .fixedSize()
        .help(chat.workingDirectory.path)
        .accessibilityLabel("Pasta da sessão: \(chat.workingDirectory.lastPathComponent)")
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

    private static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp"]
}

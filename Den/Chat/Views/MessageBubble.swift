import SwiftUI

struct MessageBubble: View {
    enum Style { case user, assistant }

    let text: String
    let moment: Date?
    var style: Style = .assistant
    var markdown: Bool = false
    var images: [Data] = []
    var files: [String] = []
    var onZoom: (Data) -> Void = { _ in }
    var isOpen = true
    var onToggle: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        switch style {
        case .assistant:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        case .user:
            HStack(alignment: .bottom, spacing: 8) {
                timestamp
                    .opacity(hovering ? 1 : 0)
                    .padding(.bottom, 2)
                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Theme.bubble, in: UnevenRoundedRectangle(
                        topLeadingRadius: 16, bottomLeadingRadius: 16,
                        bottomTrailingRadius: 4, topTrailingRadius: 16, style: .continuous))
            }
            .onHover { hovering = $0 }
        }
    }

    private var content: some View {
        let sizes = images.map { ImageCache.displaySize(for: $0) }
        let contentWidth = sizes.map(\.width).max()
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(files, id: \.self) { name in
                HStack(spacing: 7) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                    Text(name)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.hoverRaised, in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                if let image = ImageCache.decodedImage(data) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: sizes[index].width, height: sizes[index].height)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture {
                            onZoom(data)
                        }
                        .help("Clique para ampliar")
                }
            }
            Group {
                if let onToggle, !markdown {
                    collapsible(onToggle)
                } else if markdown {
                    MarkdownText(text: visibleText)
                } else if !text.isEmpty {
                    plainText(visibleText)
                }
            }
            .frame(minWidth: images.isEmpty ? nil : max(contentWidth ?? 0, 220),
                   alignment: .leading)
        }
    }

    private func collapsible(_ onToggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            plainText(isOpen ? visibleText : LongText.preview(text))
                .lineLimit(isOpen ? nil : LongText.previewLines)
                .mask(LinearGradient(colors: isOpen ? [.black, .black]
                                                    : [.black, .black, .black.opacity(0.2)],
                                     startPoint: .top, endPoint: .bottom))
            Button(action: onToggle) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                    Text(isOpen ? "Recolher"
                                : "Mostrar tudo · \(LongText.lineLabel(LongText.lineCount(text)))")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Recolher mensagem" : "Mostrar a mensagem inteira")
        }
    }

    private var visibleText: String { Self.clipped(text, limit: 12_000) }

    private func plainText(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 14))
            .lineSpacing(2)
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var timestamp: some View {
        if let moment {
            Text(moment, format: .dateTime.hour().minute())
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
    }

    static func clipped(_ text: String, limit: Int = 1_200) -> String {
        guard text.utf8.count > limit else { return text }
        let head = String(text.prefix(limit))
        let hidden = text.count - head.count
        guard hidden > 0 else { return text }
        return head + "\n⋯ +\(hidden) caracteres não exibidos"
    }
}

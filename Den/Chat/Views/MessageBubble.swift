import SwiftUI
import HarnessCore

struct MessageBubble: View {
    let text: String
    let moment: Date?
    let tint: AnyShapeStyle
    var markdown: Bool = false
    var images: [Data] = []
    var files: [String] = []
    var onZoom: (Data) -> Void = { _ in }
    var isOpen = true
    var onToggle: (() -> Void)?

    var body: some View {
        let sizes = images.map { ImageCache.displaySize(for: $0) }
        let contentWidth = sizes.map(\.width).max()
        return VStack(alignment: .center, spacing: 6) {
            ForEach(files, id: \.self) { name in
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                if let image = ImageCache.decodedImage(data) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: sizes[index].width, height: sizes[index].height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            onZoom(data)
                        }
                        .help("Clique para ampliar")
                }
            }
            Group {
                if let onToggle, !markdown {
                    collapsible(onToggle)
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        if markdown {
                            MarkdownText(text: visibleText)
                        } else if !text.isEmpty {
                            plainText(visibleText)
                        }
                        timestamp
                    }
                }
            }
            .frame(minWidth: images.isEmpty ? nil : max(contentWidth ?? 0, 220),
                   alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint, in: RoundedRectangle(cornerRadius: 13))
    }

    private func collapsible(_ onToggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            plainText(isOpen ? visibleText : LongText.preview(text))
                .lineLimit(isOpen ? nil : LongText.previewLines)
                .mask(LinearGradient(colors: isOpen ? [.black, .black]
                                                    : [.black, .black, .black.opacity(0.2)],
                                     startPoint: .top, endPoint: .bottom))
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                        Text(isOpen ? "Recolher"
                                    : "Mostrar tudo · \(LongText.lineLabel(LongText.lineCount(text)))")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isOpen ? "Recolher mensagem" : "Mostrar a mensagem inteira")
                Spacer(minLength: 0)
                timestamp
            }
        }
    }

    private var visibleText: String { Self.clipped(text, limit: 12_000) }

    private func plainText(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 13))
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var timestamp: some View {
        if let moment {
            Text(moment, format: .dateTime.hour().minute())
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
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

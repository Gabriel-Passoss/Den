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
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if markdown {
                    MarkdownText(text: Self.clipped(text, limit: 12_000))
                } else if !text.isEmpty {
                    Text(Self.clipped(text, limit: 12_000))
                        .font(.system(size: 13))
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let moment {
                    Text(moment, format: .dateTime.hour().minute())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: images.isEmpty ? nil : max(contentWidth ?? 0, 220),
                   alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint, in: RoundedRectangle(cornerRadius: 13))
    }

    static func clipped(_ text: String, limit: Int = 1_200) -> String {
        guard text.utf8.count > limit else { return text }
        let head = String(text.prefix(limit))
        let hidden = text.count - head.count
        guard hidden > 0 else { return text }
        return head + "\n⋯ +\(hidden) caracteres não exibidos"
    }
}

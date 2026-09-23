import SwiftUI
import HarnessCore

struct TranscriptRow: View {
    let line: CockpitModel.Line
    @Binding var expanded: Set<UUID>
    var onZoom: (Data) -> Void

    var body: some View { row(line) }

    @ViewBuilder
    private func row(_ line: CockpitModel.Line) -> some View {
        switch line.role {
        case .user:
            userBubble(line)

        case .assistant:
            assistantBubble(line.text, at: line.timestamp)

        case .thinking:
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "brain").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text(MessageBubble.clipped(line.text))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .italic()
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .tool:
            chip(icon: icon(for: line.verb), text: line.text, mono: true)

        case .toolResult:
            chip(icon: "arrow.turn.down.right", text: line.text, mono: true, dim: true)

        case .notice:
            chip(icon: "info.circle", text: line.text, mono: false, dim: true)

        case .compaction:
            CompactionMark(text: line.text)

        case .digest:
            DigestRow(title: line.title ?? CockpitModel.Digest.summary,
                      text: line.text,
                      mono: line.title == CockpitModel.Digest.command,
                      isOpen: expanded.contains(line.id)) {
                withAnimation(.easeOut(duration: 0.15)) {
                    if expanded.contains(line.id) {
                        expanded.remove(line.id)
                    } else {
                        expanded.insert(line.id)
                    }
                }
            }

        case .unknown:
            EmptyView()
        }
    }

    private func userBubble(_ line: CockpitModel.Line) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 64)
            MessageBubble(text: line.text, moment: line.timestamp,
                          tint: AnyShapeStyle(Color.accentColor.opacity(0.22)),
                          images: line.images, files: line.files, onZoom: onZoom)
        }
    }

    private func assistantBubble(_ text: String, at moment: Date?) -> some View {
        HStack(spacing: 0) {
            MessageBubble(text: text, moment: moment,
                          tint: AnyShapeStyle(.quaternary.opacity(0.4)), markdown: true)
            Spacer(minLength: 64)
        }
    }

    private func chip(icon: String, text: String, mono: Bool, dim: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(dim ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .frame(width: 13)
            Text(MessageBubble.clipped(text))
                .font(.system(size: 11, design: mono ? .monospaced : .default))
                .foregroundStyle(dim ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func icon(for verb: CanonicalTool?) -> String {
        switch verb {
        case .read: "doc.text"
        case .write: "square.and.pencil"
        case .edit: "pencil"
        case .execute: "terminal"
        case .search: "magnifyingglass"
        case .fetch: "globe"
        case nil: "wrench.and.screwdriver"
        }
    }
}

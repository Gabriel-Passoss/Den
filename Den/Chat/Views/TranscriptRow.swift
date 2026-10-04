import SwiftUI
import HarnessCore

struct TranscriptRow: View {
    let line: ChatLine
    @Binding var expanded: Set<UUID>
    var onZoom: (Data) -> Void

    var body: some View { row(line) }

    @ViewBuilder
    private func row(_ line: ChatLine) -> some View {
        switch line.role {
        case .user:
            userBubble(line)

        case .assistant:
            MessageBubble(text: line.text, moment: line.timestamp,
                          style: .assistant, markdown: true)

        case .thinking:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 14)
                    .padding(.top, 2)
                Text(MessageBubble.clipped(line.text))
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Theme.textMuted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .tool:
            step(line)

        case .toolResult:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 14)
                    .padding(.top, 2)
                Text(MessageBubble.clipped(line.text))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(line.text.hasPrefix("falhou")
                                     ? Theme.removed : Theme.textTertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

        case .notice:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .frame(width: 14)
                    .padding(.top, 1)
                Text(MessageBubble.clipped(line.text))
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textTertiary)

        case .compaction:
            CompactionMark(text: line.text)

        case .digest:
            DigestRow(title: line.title ?? Digest.summary,
                      text: line.text,
                      mono: line.title == Digest.command,
                      isOpen: expanded.contains(line.id)) { toggle(line.id) }

        case .unknown:
            EmptyView()
        }
    }

    private func userBubble(_ line: ChatLine) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 96)
            MessageBubble(text: line.text, moment: line.timestamp,
                          style: .user,
                          images: line.images, files: line.files, onZoom: onZoom,
                          isOpen: expanded.contains(line.id),
                          onToggle: LongText.isLong(line.text) ? { toggle(line.id) } : nil)
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.15)) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }

    private func step(_ line: ChatLine) -> some View {
        let verb = Text(Self.verb(for: line.verb))
            .foregroundStyle(Theme.textMuted)
        let detail = Text(MessageBubble.clipped(line.text))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.text)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: Self.icon(for: line.verb))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 14)
            Text("\(verb) \(detail)")
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    static func icon(for verb: CanonicalTool?) -> String {
        switch verb {
        case .read: "doc.text"
        case .write: "plus.square"
        case .edit: "pencil"
        case .execute: "terminal"
        case .search: "magnifyingglass"
        case .fetch: "globe"
        case nil: "wrench.and.screwdriver"
        }
    }

    static func verb(for verb: CanonicalTool?) -> String {
        switch verb {
        case .read: "Leu"
        case .write: "Criou"
        case .edit: "Editou"
        case .execute: "Executou"
        case .search: "Buscou"
        case .fetch: "Acessou"
        case nil: "Usou"
        }
    }
}

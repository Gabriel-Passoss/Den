import SwiftUI
import HarnessCore

struct ToolSteps: View {
    let id: UUID
    let lines: [ChatLine]
    @Binding var expanded: Set<UUID>
    var onZoom: (Data) -> Void

    var body: some View {
        let isOpen = expanded.contains(id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { expanded.remove(id) } else { expanded.insert(id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10))
                    Text(lines.count == 1 ? "1 passo" : "\(lines.count) passos")
                        .font(.system(size: 11))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Recolher os passos" : "Ver o que a IA fez")
            .accessibilityLabel(isOpen ? "Recolher passos" : "Expandir \(lines.count) passos")

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines) { line in
                        if line.role == .unknown {
                            Text(line.text)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            TranscriptRow(line: line, expanded: $expanded, onZoom: onZoom)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(.quaternary.opacity(isOpen ? 0.18 : 0),
                    in: RoundedRectangle(cornerRadius: 9))
    }
}

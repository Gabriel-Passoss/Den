import SwiftUI
import HarnessCore
import ClaudeHarness

struct HarnessBadge: View {

    let harness: HarnessID?
    var size: CGFloat = 15

    var body: some View {
        Group {
            if let harness, let asset = Self.asset(for: harness) {
                Image(asset)
                    .resizable()
                    .interpolation(.high)
            } else {

                Text(harness.map { Self.name(for: $0).prefix(1) } ?? "?")
                    .font(.system(size: size * 0.6, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }

    static func asset(for harness: HarnessID) -> String? {
        switch harness {
        case .claudeCode: "HarnessClaudeCode"
        default: nil
        }
    }

    static func name(for harness: HarnessID) -> String {
        switch harness {
        case .claudeCode: "Claude Code"
        default: harness.rawValue
        }
    }
}

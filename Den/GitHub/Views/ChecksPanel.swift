import SwiftUI
import AppKit

struct ChecksRing: View {
    let summary: ChecksSummary

    @State private var turning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.borderControl, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: arc)
                .stroke(summary.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(isRunning && turning ? 270 : -90))
                .animation(isRunning ? .linear(duration: 1.1).repeatForever(autoreverses: false)
                                     : .easeInOut(duration: 0.4), value: turning)
        }
        .animation(.easeInOut(duration: 0.4), value: arc)
        .onAppear { turning = true }
    }

    private var isRunning: Bool {
        if case .running = summary { return true }
        return false
    }

    private var arc: Double {
        switch summary {
        case .absent: 0
        case .running: 0.3
        case .passing: 1
        case .failing(let passed, let total): max(Double(passed) / Double(max(total, 1)), 0.04)
        }
    }
}

extension ChecksSummary {
    var color: Color {
        switch self {
        case .absent: Theme.textTertiary
        case .running: Theme.modified
        case .passing: Theme.added
        case .failing: Theme.removed
        }
    }

    var count: String {
        switch self {
        case .absent: ""
        case .running(let passed, let total), .failing(let passed, let total): "\(passed)/\(total)"
        case .passing(let total): "\(total)/\(total)"
        }
    }
}

extension CheckRun.State {
    var color: Color {
        switch self {
        case .failed: Theme.removed
        case .running: Theme.modified
        case .queued: Theme.borderControl
        case .passed: Theme.added
        case .skipped: Theme.textFaint
        }
    }
}

struct ChecksPanel: View {
    let pullRequest: PullRequest
    let checkedAt: Date?
    var refresh: () -> Void

    private static let maxListHeight: CGFloat = 320

    var body: some View {
        let checks = PullRequestStatus.ordered(pullRequest.checks)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Checks")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(PullRequestStatus.headline(pullRequest))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 2) {
                ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                    Rectangle().fill(check.state.color).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 8)
            .background(Theme.borderStrong)
            .clipShape(Capsule())
            FittedScroll(maxHeight: Self.maxListHeight) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                        CheckRow(check: check)
                    }
                }
            }
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(PullRequestStatus.updatedLabel(since: checkedAt, now: context.date))
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .iconLabel(size: 24)
                }
                .buttonStyle(.denGhost(radius: 6))
                .help("Atualizar agora")
                .accessibilityLabel("Atualizar")
            }
        }
        .padding(16)
        .frame(width: 340)
        .foregroundStyle(Theme.text)
        .background(Theme.raised)
    }
}

private struct CheckRow: View {
    let check: CheckRun

    @State private var hovering = false

    var body: some View {
        Button {
            if let url = check.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                swatch
                Text(check.name)
                    .foregroundStyle(check.state == .skipped ? Theme.textTertiary : Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(PullRequestStatus.detail(of: check, at: context.date))
                }
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .opacity(check.url == nil ? 0 : 1)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 6)
            .frame(height: 26)
            .hoverFill(hovering && check.url != nil, radius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(check.url == nil)
    }

    @ViewBuilder
    private var swatch: some View {
        if check.state == .running {
            SpinningRing(color: check.state.color, size: 10)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(check.state == .queued ? .clear : check.state.color)
                .overlay {
                    if check.state == .queued {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Theme.textFaint, lineWidth: 1)
                    }
                }
                .frame(width: 10, height: 10)
        }
    }
}

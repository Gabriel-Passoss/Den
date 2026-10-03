import SwiftUI
import AppKit

struct ChecksPopover: View {
    let pullRequest: PullRequest
    let checkedAt: Date?
    var refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Checks").font(.system(size: 12, weight: .semibold))
                Text("· " + PullRequestStatus.headline(pullRequest))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(PullRequestStatus.ordered(pullRequest.checks).enumerated()),
                        id: \.offset) { _, check in
                    row(check)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            Divider()
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(PullRequestStatus.updatedLabel(since: checkedAt, now: context.date))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Spacer()
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Atualizar agora")
                .accessibilityLabel("Atualizar")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }

    private func row(_ check: CheckRun) -> some View {
        Button {
            if let url = check.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                icon(check.state).frame(width: 14)
                Text(check.name).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(PullRequestStatus.detail(of: check, at: context.date))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(check.url == nil ? 0 : 1)
            }
            .padding(6)
            .background(check.state == .failed ? Color.red.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(check.url == nil)
    }

    @ViewBuilder
    private func icon(_ state: CheckRun.State) -> some View {
        switch state {
        case .failed:
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
        case .running:
            SpinningRing(color: .yellow, size: 11)
        case .queued:
            Image(systemName: "circle.dashed").font(.system(size: 11)).foregroundStyle(.secondary)
        case .passed:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

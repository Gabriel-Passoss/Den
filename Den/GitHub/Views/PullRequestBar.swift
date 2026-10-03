import SwiftUI
import AppKit

struct PullRequestBar: View {
    let repo: TaskWorktree.Repo
    let branch: String
    let pullRequest: PullRequest
    let checkedAt: Date?
    var refresh: () -> Void
    var dismiss: () -> Void

    @State private var showingChecks = false
    @State private var hoveringChecks = false
    @State private var pulse = false

    private var tone: PullRequestTone { PullRequestStatus.tone(pullRequest) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            Button { NSWorkspace.shared.open(pullRequest.url) } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: tone.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tone.color)
                        Text("#\(pullRequest.number)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .monospacedDigit()
                    }
                    Text(repo.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(pullRequest.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Abrir no GitHub · \(branch)")
            trailing
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .iconLabel(size: 24)
            }
            .buttonStyle(.denGhost(radius: 6))
            .help("Dispensar até o PR mudar")
            .accessibilityLabel("Dispensar")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        .foregroundStyle(Theme.text)
        .background(fill, in: shape)
        .overlay(shape.strokeBorder(stroke, lineWidth: 1).allowsHitTesting(false))
        .scaleEffect(pulse ? 1.015 : 1)
        .animation(.easeInOut(duration: 0.25), value: tone)
        .onChange(of: tone) { _, new in
            guard new == .merged else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { pulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pulse = false }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pull-request-bar")
    }

    @ViewBuilder
    private var trailing: some View {
        if pullRequest.state == .open, !pullRequest.isDraft {
            reviewPill
            diffPill
            if PullRequestStatus.checks(pullRequest) != .none { checksChip }
        } else {
            diffPill
            Text(PullRequestStatus.label(pullRequest))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tone.color)
                .padding(.horizontal, 4)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var reviewPill: some View {
        if pullRequest.mergeable == .conflicting {
            pill("Conflito com \(pullRequest.base.isEmpty ? "a base" : pullRequest.base)",
                 symbol: "exclamationmark.triangle", color: Theme.alertText, fill: Theme.alertFill)
        } else if pullRequest.review == .changesRequested {
            pill("Mudanças pedidas", symbol: "arrow.uturn.backward",
                 color: Theme.alertText, fill: Theme.alertFill)
        } else if pullRequest.review == .approved {
            pill("Aprovado", symbol: "checkmark", color: Theme.added, fill: Theme.addedFill)
        }
    }

    private func pill(_ text: String, symbol: String, color: Color, fill: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .fixedSize()
    }

    private var diffPill: some View {
        HStack(spacing: 5) {
            Text("+\(pullRequest.additions)").foregroundStyle(Theme.added)
            Text("−\(pullRequest.deletions)").foregroundStyle(Theme.removed)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .fixedSize()
    }

    private var checksChip: some View {
        let summary = PullRequestStatus.checks(pullRequest)
        return Button { showingChecks.toggle() } label: {
            HStack(spacing: 7) {
                ChecksRing(summary: summary)
                    .frame(width: 16, height: 16)
                Text(summary.count)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(summary == .passing(total: passingTotal) ? Theme.textTertiary
                                                                              : summary.color)
                    .lineLimit(1)
                    .fixedSize()
            }
            .chipLabel(horizontalPadding: 8)
            .hoverFill(hoveringChecks, selected: showingChecks)
        }
        .buttonStyle(.plain)
        .onHover { hoveringChecks = $0 }
        .help("Checks: \(PullRequestStatus.headline(pullRequest)) · clique para ver cada um")
        .accessibilityLabel("Checks")
        .accessibilityValue(PullRequestStatus.headline(pullRequest))
        .popover(isPresented: $showingChecks, arrowEdge: .top) {
            ChecksPanel(pullRequest: pullRequest, checkedAt: checkedAt, refresh: refresh)
                .presentationBackground(Theme.raised)
                .environment(\.colorScheme, .dark)
        }
    }

    private var passingTotal: Int {
        if case .passing(let total) = PullRequestStatus.checks(pullRequest) { return total }
        return -1
    }

    private var fill: Color {
        switch tone {
        case .failure: Theme.removedFill
        case .merged: Theme.accentFill
        case .draft, .closed: Theme.card
        case .open, .attention: Theme.raised
        }
    }

    private var stroke: Color {
        switch tone {
        case .failure: Theme.removed.opacity(0.45)
        case .merged: Theme.accent.opacity(0.45)
        case .draft, .closed: Theme.borderCard
        case .open, .attention: Theme.borderControl
        }
    }
}

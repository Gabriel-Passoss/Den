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
    @State private var pulse = false

    private var tone: PullRequestTone { PullRequestStatus.tone(pullRequest) }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: tone.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone.color)
                Text("#\(pullRequest.number)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            Text(repo.name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Text(pullRequest.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dispensar até o PR mudar")
            .accessibilityLabel("Dispensar")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { NSWorkspace.shared.open(pullRequest.url) }
        .help("\(pullRequest.title)\n\(branch)")
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
            if PullRequestStatus.checks(pullRequest) != .none { checksPill }
        } else {
            diffPill
            Text(PullRequestStatus.label(pullRequest))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone.color)
                .padding(.horizontal, 4)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var reviewPill: some View {
        if pullRequest.mergeable == .conflicting {
            pill("Conflito com \(pullRequest.base.isEmpty ? "a base" : pullRequest.base)",
                 symbol: "exclamationmark.triangle", color: .orange)
        } else if pullRequest.review == .changesRequested {
            pill("Mudanças pedidas", symbol: "arrow.uturn.backward", color: .orange)
        } else if pullRequest.review == .approved {
            pill("Aprovado", symbol: "checkmark", color: .green)
        }
    }

    private func pill(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(color.opacity(0.14), in: Capsule())
        .fixedSize()
    }

    private var diffPill: some View {
        HStack(spacing: 4) {
            Text("+\(pullRequest.additions)").foregroundStyle(.green)
            Text("−\(pullRequest.deletions)").foregroundStyle(.red)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .fixedSize()
    }

    private var checksPill: some View {
        let summary = PullRequestStatus.checks(pullRequest)
        let color: Color
        let count: String
        switch summary {
        case .failing(let passed, let total): color = .red; count = "\(passed)/\(total)"
        case .running(let passed, let total): color = .yellow; count = "\(passed)/\(total)"
        case .passing(let total): color = .green; count = "\(total)/\(total)"
        case .none: color = .secondary; count = ""
        }
        return Button { showingChecks.toggle() } label: {
            HStack(spacing: 5) {
                switch summary {
                case .running: SpinningRing(color: color)
                case .failing: Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                default: Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                }
                Text(count).monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(color.opacity(0.16), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Checks")
        .popover(isPresented: $showingChecks, arrowEdge: .top) {
            ChecksPopover(pullRequest: pullRequest, checkedAt: checkedAt, refresh: refresh)
        }
    }

    private var background: AnyShapeStyle {
        switch tone {
        case .failure: AnyShapeStyle(Color.red.opacity(0.09))
        case .merged: AnyShapeStyle(InlineCode.color.opacity(0.10))
        case .draft, .closed: AnyShapeStyle(Color.gray.opacity(0.09))
        case .open, .attention: AnyShapeStyle(.quaternary.opacity(0.25))
        }
    }

    private var border: AnyShapeStyle {
        switch tone {
        case .failure: AnyShapeStyle(Color.red.opacity(0.35))
        case .merged: AnyShapeStyle(InlineCode.color.opacity(0.38))
        case .draft, .closed: AnyShapeStyle(Color.gray.opacity(0.3))
        case .open, .attention: AnyShapeStyle(.quaternary)
        }
    }
}

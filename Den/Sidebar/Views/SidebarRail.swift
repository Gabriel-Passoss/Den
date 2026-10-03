import SwiftUI
import AppKit

struct PaneTip: Equatable {
    let title: String
    let detail: String?
    let indicator: WorkspaceModel.SessionIndicator?
    let anchor: CGRect
    var lines: [Line] = []

    struct Line: Equatable {
        let color: Color?
        let text: String

        static func task(_ worktree: TaskWorktree, bars: [PullRequestMonitor.Bar]) -> [Line] {
            bars.map { bar in
                Line(color: PullRequestStatus.tone(bar.pullRequest).color,
                     text: "\(bar.repo.name) #\(bar.pullRequest.number) · "
                         + PullRequestStatus.label(bar.pullRequest))
            } + [Line(color: nil, text: worktree.branch)]
        }
    }
}

struct PaneHoverCard: View {
    static let maxWidth: CGFloat = 240
    static let margin: CGFloat = 12

    let tip: PaneTip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tip.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = tip.detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ForEach(Array(tip.lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 5) {
                    if let color = line.color {
                        Circle().fill(color).frame(width: 6, height: 6)
                    }
                    Text(line.text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let indicator = tip.indicator {
                HStack(spacing: 5) {
                    Circle()
                        .fill(SessionRow.color(for: indicator))
                        .frame(width: 6, height: 6)
                    Text(SessionRow.label(for: indicator))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 120, alignment: .leading)
        .foregroundStyle(Theme.text)
        .background(Color(hex: 0x1E222B), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.borderControl, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .environment(\.colorScheme, .dark)
        .padding(Self.margin)
    }
}

@MainActor
final class HoverTipPanel {
    static let shared = HoverTipPanel()

    private var panel: NSPanel?
    private(set) var isVisible = false

    func show(_ tip: PaneTip) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow,
              let content = window.contentView else { return }

        let host = NSHostingView(rootView: PaneHoverCard(tip: tip))
        let size = Self.size(of: tip)

        let panel = self.panel ?? makePanel()
        panel.contentView = host

        let flippedY = content.bounds.height - tip.anchor.midY
        let inWindow = NSPoint(x: tip.anchor.maxX - 4, y: flippedY)
        var origin = window.convertPoint(toScreen: inWindow)
        origin.y -= size.height / 2
        if let screen = window.screen {
            origin.y = max(screen.visibleFrame.minY,
                           min(origin.y, screen.visibleFrame.maxY - size.height))
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0.12
            panel.animator().alphaValue = 1
        }
        isVisible = true
    }

    static func size(of tip: PaneTip) -> NSSize {
        NSHostingController(rootView: PaneHoverCard(tip: tip)).sizeThatFits(
            in: NSSize(width: PaneHoverCard.maxWidth + 2 * PaneHoverCard.margin, height: 10_000))
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

struct HoverTipModifier: ViewModifier {
    let enabled: Bool
    let make: (CGRect) -> PaneTip
    let update: (PaneTip?) -> Void

    @State private var anchor: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { anchor = $0 }
            .onHover { inside in
                guard enabled else { return }
                update(inside ? make(anchor) : nil)
            }
    }
}

extension View {
    func hoverTip(enabled: Bool = true,
                  _ make: @escaping (CGRect) -> PaneTip,
                  update: @escaping (PaneTip?) -> Void) -> some View {
        modifier(HoverTipModifier(enabled: enabled, make: make, update: update))
    }
}

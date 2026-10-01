import SwiftUI
import AppKit
import HarnessCore

struct EffortPicker: View {
    let knob: HarnessKnob
    let chat: ChatModel
    var showsLabel = true

    @State private var isOpen = false
    @State private var hovering = false

    static func fits(_ knob: HarnessKnob) -> Bool { (2...7).contains(knob.options.count) }

    private var currentLabel: String {
        knob.label(for: knob.currentValue) ?? EffortSlider.unsetLabel
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isOpen ? Theme.accent : Theme.textTertiary)
                if showsLabel {
                    Text(currentLabel)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Chevron(size: 8)
            }
            .chipLabel()
            .hoverFill(hovering, selected: isOpen)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .fixedSize()
        .help("\(knob.name): \(currentLabel)")
        .accessibilityLabel(knob.name)
        .accessibilityValue(currentLabel)
        .accessibilityIdentifier("effort-picker")
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            EffortSlider(knob: knob, chat: chat) { isOpen = false }
                .presentationBackground(Theme.raised)
                .environment(\.colorScheme, .dark)
        }
    }
}

struct EffortSlider: View {
    let knob: HarnessKnob
    let chat: ChatModel
    var done: () -> Void = {}

    @State private var draft: Int?
    @State private var dragging = false
    @State private var finished = false

    static let unsetLabel = "Padrão"
    private static let thumb: CGFloat = 18
    private static let trackWidth: CGFloat = 248

    private var stops: Int { knob.options.count }

    private var committed: Int? {
        knob.currentValue.flatMap { value in knob.options.firstIndex { $0.value == value } }
    }

    private var shown: Int? { draft ?? committed }

    private var shownLabel: String { shown.map { knob.options[$0].label } ?? Self.unsetLabel }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(knob.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(shownLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(draft != nil && draft != committed ? Theme.accentSoft
                                     : committed == nil ? Theme.textTertiary : Theme.text)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.16), value: shownLabel)
            }
            track
            HStack {
                Text(knob.options.first?.label ?? "")
                Spacer()
                Text(knob.options.last?.label ?? "")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .frame(width: Self.trackWidth + 32)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(by: -1); return .handled }
        .onKeyPress(.rightArrow) { move(by: 1); return .handled }
        .onKeyPress(.return) { finish(); return .handled }
        .onDisappear {
            guard !finished, let draft, draft != committed else { return }
            commit(draft)
        }
        .accessibilityElement()
        .accessibilityIdentifier("effort-slider")
        .accessibilityLabel(knob.name)
        .accessibilityValue(shownLabel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let step = (proxy.size.width - Self.thumb) / CGFloat(stops - 1)
            let center = proxy.size.height / 2
            let x = { (index: Int) in Self.thumb / 2 + CGFloat(index) * step }
            let thumb = dragging ? Self.thumb + 2 : Self.thumb

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.borderControl)
                    .frame(height: 6)
                if let shown {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: x(shown), height: 6)
                }
                ForEach(0..<stops, id: \.self) { index in
                    Circle()
                        .fill(index <= (shown ?? -1) ? Theme.onAction.opacity(0.5) : Theme.textFaint)
                        .frame(width: 5, height: 5)
                        .position(x: x(index), y: center)
                }
                if let shown {
                    Circle()
                        .fill(Theme.text)
                        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: dragging ? 3 : 0))
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                        .position(x: x(shown), y: center)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !dragging {
                            withAnimation(.easeOut(duration: 0.12)) { dragging = true }
                        }
                        let index = nearest(value.location.x, step: step)
                        guard shown != index else { return }
                        NSHapticFeedbackManager.defaultPerformer
                            .perform(.alignment, performanceTime: .now)
                        withAnimation(.snappy(duration: 0.16)) { draft = index }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.12)) { dragging = false }
                        finish()
                    }
            )
        }
        .frame(width: Self.trackWidth, height: 24)
    }

    private func nearest(_ location: CGFloat, step: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        let index = Int(((location - Self.thumb / 2) / step).rounded())
        return min(max(index, 0), stops - 1)
    }

    private func move(by offset: Int) {
        let start = shown ?? (offset > 0 ? -1 : stops)
        let next = min(max(start + offset, 0), stops - 1)
        guard next != shown else { return }
        withAnimation(.snappy(duration: 0.16)) { draft = next }
    }

    private func finish() {
        finished = true
        if let draft, draft != committed { commit(draft) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            done()
        }
    }

    private func commit(_ index: Int) {
        guard knob.options.indices.contains(index) else { return }
        let value = knob.options[index].value
        Task { await chat.choose(knob: knob.id, value: value) }
    }
}

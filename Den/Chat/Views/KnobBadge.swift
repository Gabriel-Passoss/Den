import SwiftUI
import HarnessCore

struct KnobBadge: View {
    let knob: HarnessKnob
    let chat: ChatModel
    var compact = false

    static let modeLooks: [String: (symbol: String, color: Color)] = [
        "auto": ("forward.fill", Theme.modified),
        "plan": ("list.bullet.clipboard", Theme.hunk),
        "acceptEdits": ("pencil.line", Theme.renamed),
        "manual": ("shield", Theme.textSecondary),
        "dontAsk": ("forward.fill", Theme.accent),
        "bypassPermissions": ("exclamationmark.shield", Theme.removed),
        "build": ("hammer", Theme.added),
    ]

    private func selection(for knob: HarnessKnob) -> Binding<String?> {
        Binding(
            get: { chat.knob(knob.id)?.currentValue },
            set: { value in Task { await chat.choose(knob: knob.id, value: value) } }
        )
    }

    @ViewBuilder
    private func knobOption(_ option: HarnessKnob.Option, in knob: HarnessKnob) -> some View {
        if knob.category == .mode, let icon = Self.modeLooks[option.value] {
            Label(option.label, systemImage: icon.symbol).tag(Optional(option.value))
        } else {
            Text(option.label).tag(Optional(option.value))
        }
    }

    var body: some View {
        MenuChip(bordered: knob.category == .mode) {
            Picker(knob.name, selection: selection(for: knob)) {
                ForEach(Array(knob.groupedOptions.enumerated()), id: \.offset) { _, bucket in
                    Section {
                        ForEach(bucket.options, id: \.value) { option in
                            knobOption(option, in: knob)
                        }
                    } header: {
                        if let group = bucket.group { Text(group) }
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            label
        }
        .help("\(knob.name): \(knob.label(for: knob.currentValue) ?? "—")")
        .accessibilityLabel("\(knob.name): \(knob.label(for: knob.currentValue) ?? "—")")
    }

    private var label: some View {
        let current = knob.currentValue
        let look = knob.category == .mode ? Self.modeLooks[current ?? ""] : nil
        return HStack(spacing: 6) {
            if let look {
                Image(systemName: look.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(look.color)
            }
            if !compact || knob.category == .model || (look == nil && knob.category == .mode) {
                Text(knob.label(for: current) ?? knob.name)
                    .foregroundStyle(knob.category == .model ? Theme.text : Theme.textSecondary)
                    .fontWeight(knob.category == .model ? .medium : .regular)
                    .lineLimit(1)
            }
            Chevron(size: 8)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .contentShape(Rectangle())
    }
}

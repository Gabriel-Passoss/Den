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

    static func sections(for knob: HarnessKnob,
                         choose: @escaping (String) -> Void) -> [DenMenuSection] {
        knob.groupedOptions.enumerated().map { index, bucket in
            DenMenuSection(
                id: bucket.group ?? "bucket-\(index)",
                header: bucket.group,
                items: bucket.options.map { option in
                    let look = knob.category == .mode ? modeLooks[option.value] : nil
                    let current = option.value == knob.currentValue
                    return DenMenuItem(
                        id: option.value,
                        title: option.label,
                        icon: look.map { DenMenuIcon.symbol($0.symbol, $0.color) },
                        isSelected: current
                    ) {
                        guard !current else { return }
                        choose(option.value)
                    }
                }
            )
        }
    }

    var body: some View {
        let sections = Self.sections(for: knob) { value in
            Task { await chat.choose(knob: knob.id, value: value) }
        }
        return DenMenuChip(sections: sections, bordered: knob.category == .mode) {
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
        .chipLabel()
    }
}

import SwiftUI
import HarnessCore

struct KnobBadge: View {
    let knob: HarnessKnob
    let cockpit: CockpitModel

    static let modeLooks: [String: (symbol: String, color: Color)] = [
        "auto": ("forward.fill", .yellow),
        "plan": ("pause.fill", .blue),
        "acceptEdits": ("forward.fill", .purple),
        "manual": ("pause.fill", .gray),
        "dontAsk": ("forward.fill", .orange),
        "bypassPermissions": ("forward.fill", .red),
        "build": ("hammer.fill", .green),
    ]

    private func selection(for knob: HarnessKnob) -> Binding<String?> {
        Binding(
            get: { cockpit.knob(knob.id)?.currentValue },
            set: { value in Task { await cockpit.choose(knob: knob.id, value: value) } }
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
        let current = knob.currentValue
        let look = knob.category == .mode ? Self.modeLooks[current ?? ""] : nil

        Menu {
            Picker(knob.name, selection: selection(for: knob)) {
                /// Lista plana vira um grupo sem título, então o `Section` só
                /// aparece de fato quando o harness nomeou os grupos — os 23
                /// modelos do OpenCode, separados por provedor.
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
            HStack(spacing: 3) {
                if let look {
                    Image(systemName: look.symbol).font(.system(size: 8))
                }
                Text(knob.label(for: current) ?? knob.name)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
            }
            .font(.system(size: 10))
            .foregroundStyle(look.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary.opacity(0.4), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Escolher \(knob.name.lowercased()) das próximas mensagens")
    }
}

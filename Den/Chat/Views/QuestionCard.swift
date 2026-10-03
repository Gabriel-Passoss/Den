import SwiftUI

struct QuestionCard: View {
    let prompt: QuestionPrompt
    var answer: ([String: [String]]) -> Void
    var dismiss: () -> Void

    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(prompt.questions, id: \.text) { question in
                VStack(alignment: .leading, spacing: 8) {
                    if !question.header.isEmpty {
                        Text(question.header)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.accentSoft)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.accentFill, in: Capsule())
                    }
                    Text(question.text)
                        .font(.system(size: 13.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 4) {
                        ForEach(question.options, id: \.label) { option in
                            OptionRow(option: option,
                                      selected: selections[question.text]?.contains(option.label)
                                        ?? false,
                                      multiple: question.multiSelect) {
                                select(question, option)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: dismiss) {
                    Text("Dispensar").pillLabel()
                }
                .buttonStyle(.denGhost)
                .foregroundStyle(Theme.textSecondary)
                Spacer()
                if needsSubmit {
                    Button(action: submit) {
                        Text("Responder").pillLabel()
                    }
                    .buttonStyle(.denPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!allAnswered)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.borderControl, lineWidth: 1))
    }

    private struct OptionRow: View {
        let option: QuestionPrompt.Option
        let selected: Bool
        let multiple: Bool
        var action: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: selected
                          ? (multiple ? "checkmark.square.fill" : "largecircle.fill.circle")
                          : (multiple ? "square" : "circle"))
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                            .font(.system(size: 13, weight: .medium))
                        if !option.detail.isEmpty {
                            Text(option.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Theme.accentFill : hovering ? Theme.hover : Theme.raised,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.6) : Theme.borderStrong,
                                  lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }

    private func select(_ question: QuestionPrompt.Question,
                        _ option: QuestionPrompt.Option) {
        var chosen = selections[question.text] ?? []
        if question.multiSelect {
            if chosen.contains(option.label) { chosen.remove(option.label) }
            else { chosen.insert(option.label) }
        } else {
            chosen = [option.label]
        }
        selections[question.text] = chosen
        if !needsSubmit { submit() }
    }

    private var needsSubmit: Bool {
        prompt.questions.count > 1 || prompt.questions.contains(where: \.multiSelect)
    }

    private var allAnswered: Bool {
        prompt.questions.allSatisfy { !(selections[$0.text] ?? []).isEmpty }
    }

    private func submit() {
        guard allAnswered else { return }
        answer(selections.mapValues(Array.init))
    }
}

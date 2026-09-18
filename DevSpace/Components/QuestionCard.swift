import SwiftUI

struct QuestionCard: View {
    let prompt: CockpitModel.QuestionPrompt
    var answer: ([String: [String]]) -> Void
    var dismiss: () -> Void

    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(prompt.questions, id: \.text) { question in
                VStack(alignment: .leading, spacing: 7) {
                    if !question.header.isEmpty {
                        Text(question.header)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary.opacity(0.5), in: Capsule())
                    }
                    Text(question.text)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(question.options, id: \.label) { option in
                        optionButton(question, option)
                    }
                }
            }

            HStack {
                Button("Dispensar", action: dismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if needsSubmit {
                    Button("Responder", action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!allAnswered)
                }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
    }

    private func optionButton(_ question: CockpitModel.QuestionPrompt.Question,
                              _ option: CockpitModel.QuestionPrompt.Option) -> some View {
        let selected = selections[question.text]?.contains(option.label) ?? false
        return Button {
            select(question, option)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                    if !option.detail.isEmpty {
                        Text(option.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                                 : AnyShapeStyle(.quaternary.opacity(0.35)),
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func select(_ question: CockpitModel.QuestionPrompt.Question,
                        _ option: CockpitModel.QuestionPrompt.Option) {
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

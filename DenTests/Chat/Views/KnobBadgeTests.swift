import Testing
import HarnessCore
@testable import Den

@MainActor
private final class Chosen {
    var values: [String] = []
}

private func modeKnob(current: String?) -> HarnessKnob {
    HarnessKnob(id: "mode", category: .mode, name: "Permissão", currentValue: current,
                options: [
                    HarnessKnob.Option(value: "manual", label: "Manual"),
                    HarnessKnob.Option(value: "auto", label: "Automático"),
                    HarnessKnob.Option(value: "plan", label: "Plano"),
                ])
}

@MainActor
@Test func sectionsMirrorTheGroupsTheKnobDeclares() {
    let knob = HarnessKnob(id: "model", category: .model, name: "Modelo", currentValue: "opus",
                           options: [
                               HarnessKnob.Option(value: "opus", label: "Opus", group: "Anthropic"),
                               HarnessKnob.Option(value: "sonnet", label: "Sonnet", group: "Anthropic"),
                               HarnessKnob.Option(value: "gpt", label: "GPT", group: "OpenAI"),
                           ])

    let sections = KnobBadge.sections(for: knob) { _ in }

    #expect(sections.map(\.header) == ["Anthropic", "OpenAI"])
    #expect(sections.map { $0.items.map(\.id) } == [["opus", "sonnet"], ["gpt"]])
    #expect(sections.map { $0.items.map(\.title) } == [["Opus", "Sonnet"], ["GPT"]])
}

@MainActor
@Test func ungroupedOptionsLandInOneHeaderlessSection() {
    let sections = KnobBadge.sections(for: modeKnob(current: "auto")) { _ in }

    #expect(sections.count == 1)
    #expect(sections[0].header == nil)
    #expect(sections[0].items.count == 3)
}

@MainActor
@Test func onlyTheCurrentValueIsMarked() {
    let sections = KnobBadge.sections(for: modeKnob(current: "auto")) { _ in }
    let selected = sections.flatMap(\.items).filter(\.isSelected)

    #expect(selected.map(\.id) == ["auto"])
}

@MainActor
@Test func pickingTheValueThatIsAlreadyCurrentChangesNothing() {
    let chosen = Chosen()
    let sections = KnobBadge.sections(for: modeKnob(current: "auto")) { chosen.values.append($0) }

    sections.flatMap(\.items).first { $0.id == "auto" }?.action()

    #expect(chosen.values.isEmpty)
}

@MainActor
@Test func pickingAnotherValueReportsIt() {
    let chosen = Chosen()
    let sections = KnobBadge.sections(for: modeKnob(current: "auto")) { chosen.values.append($0) }

    sections.flatMap(\.items).first { $0.id == "plan" }?.action()

    #expect(chosen.values == ["plan"])
}

@MainActor
@Test func modeOptionsCarryTheirIconAndModelOptionsDoNot() {
    let mode = KnobBadge.sections(for: modeKnob(current: nil)) { _ in }
    let auto = try? #require(mode.flatMap(\.items).first { $0.id == "auto" })
    if case .symbol(let name, _) = auto?.icon {
        #expect(name == "forward.fill")
    } else {
        Issue.record("o modo automático deveria trazer o ícone de modeLooks")
    }

    let model = HarnessKnob(id: "model", category: .model, name: "Modelo", currentValue: "auto",
                            options: [HarnessKnob.Option(value: "auto", label: "Auto")])
    #expect(KnobBadge.sections(for: model) { _ in }.flatMap(\.items).allSatisfy { $0.icon == nil })
}

@MainActor
@Test func anOptionWithNoLookKeepsItsLabelAndNoIcon() {
    let knob = HarnessKnob(id: "mode", category: .mode, name: "Permissão", currentValue: nil,
                           options: [HarnessKnob.Option(value: "unknown", label: "Desconhecido")])

    let item = try? #require(KnobBadge.sections(for: knob) { _ in }.flatMap(\.items).first)

    #expect(item?.title == "Desconhecido")
    #expect(item?.icon == nil)
}

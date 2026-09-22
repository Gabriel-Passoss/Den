import Testing
import Foundation
import HarnessCore
@testable import OpenCodeHarness

private func value(_ text: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// Forma real devolvida pelo `session/new` do opencode 1.18.31, encurtada.
private let recordedConfigOptions = value(#"""
[{"id":"model","name":"Model","category":"model","type":"select",
  "currentValue":"opencode/big-pickle",
  "options":[{"value":"openai/gpt-5.4","name":"OpenAI/GPT-5.4"},
             {"value":"opencode/big-pickle","name":"OpenCode Zen/Big Pickle"}]},
 {"id":"mode","name":"Session Mode","category":"mode","type":"select",
  "currentValue":"build",
  "options":[{"value":"build","name":"build","description":"The default agent."},
             {"value":"plan","name":"plan","description":"Plan mode."}]}]
"""#)

@Test func theConfigOptionsBecomeKnobs() {
    let knobs = OpenCodeKnobs.parse(recordedConfigOptions)

    #expect(knobs.map(\.id) == ["model", "mode"])
    #expect(knobs.map(\.category) == [.model, .mode])
    #expect(knobs[0].currentValue == "opencode/big-pickle")
    #expect(knobs[1].currentValue == "build")
}

@Test func theKnobNamesAndLabelsAreCapitalized() {
    let knobs = OpenCodeKnobs.parse(recordedConfigOptions)

    #expect(knobs[0].name == "Modelo")
    #expect(knobs[1].name == "Modo")

    #expect(knobs[1].options.map(\.label) == ["Construir", "Plano"])
}

/// Forma real de quando o modelo escolhido aceita esforço: o CLI passa a
/// devolver um terceiro botão, classificado como `thought_level`.
private let recordedWithEffort = value(#"""
[{"id":"model","name":"Model","category":"model","type":"select",
  "currentValue":"openai/gpt-5.5",
  "options":[{"value":"openai/gpt-5.5","name":"OpenAI/GPT-5.5"}]},
 {"id":"effort","name":"Effort","category":"thought_level","type":"select",
  "currentValue":"none",
  "options":[{"value":"none","name":"None"},{"value":"low","name":"Low"},
             {"value":"medium","name":"Medium"},{"value":"high","name":"High"},
             {"value":"xhigh","name":"Xhigh"},{"value":"default","name":"Default"}]},
 {"id":"mode","name":"Session Mode","category":"mode","type":"select",
  "currentValue":"build","options":[{"value":"build","name":"build"}]}]
"""#)

@Test func thoughtLevelIsEffort() {
    let knobs = OpenCodeKnobs.parse(recordedWithEffort)

    /// Sem isto o esforço cai no balde do modo e o painel o desenha do lado
    /// errado do campo de texto.
    #expect(knobs.map(\.category) == [.model, .effort, .mode])
    #expect(knobs[1].name == "Esforço")
    #expect(knobs[1].options.map(\.label)
            == ["Nenhum", "Baixo", "Médio", "Alto", "Muito alto", "Padrão"])
}

@Test func anUnknownBucketLandsBesideTheModel() {
    let knobs = OpenCodeKnobs.parse(value(#"""
        [{"id":"verbosity","name":"Verbosity","category":"chattiness",
          "currentValue":"low","options":[{"value":"low","name":"low"}]}]
        """#))

    #expect(knobs[0].category == .effort)
    #expect(knobs[0].name == "Verbosity")
    #expect(knobs[0].options[0].label == "Low")
}

@Test func theProviderBecomesASectionAndLeavesTheModelName() {
    let knobs = OpenCodeKnobs.parse(recordedConfigOptions)

    #expect(knobs[0].options.map(\.label) == ["GPT-5.4", "Big Pickle"])
    #expect(knobs[0].options.map(\.group) == ["OpenAI", "OpenCode Zen"])

    /// O botão fechado mostra o modelo sem repetir o provedor.
    #expect(knobs[0].label(for: "opencode/big-pickle") == "Big Pickle")
}

@Test func aModelWithoutAProviderKeepsItsWholeName() {
    let knobs = OpenCodeKnobs.parse(value(#"""
        [{"id":"model","name":"Model","category":"model","currentValue":"local",
          "options":[{"value":"local","name":"Llamafile"},
                     {"value":"odd","name":"/leading"}]}]
        """#))

    #expect(knobs[0].options.map(\.label) == ["Llamafile", "/leading"])
    #expect(knobs[0].options.allSatisfy { $0.group == nil })
}

@Test func theOptionsGroupInTheOrderTheyArrived() {
    let model = OpenCodeKnobs.parse(recordedConfigOptions)[0]
    let buckets = model.groupedOptions

    #expect(buckets.map(\.group) == ["OpenAI", "OpenCode Zen"])
    #expect(buckets.map { $0.options.count } == [1, 1])
}

@Test func theCurrentModelIsReadableForTheCockpit() {
    #expect(OpenCodeKnobs.model(in: OpenCodeKnobs.parse(recordedConfigOptions))
            == "opencode/big-pickle")
    #expect(OpenCodeKnobs.model(in: []) == "")
}

@Test func absentConfigOptionsYieldNoKnobsInsteadOfCrashing() {
    #expect(OpenCodeKnobs.parse(nil).isEmpty)
    #expect(OpenCodeKnobs.parse(.null).isEmpty)
}

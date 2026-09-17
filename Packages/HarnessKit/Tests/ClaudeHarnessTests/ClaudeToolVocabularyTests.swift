import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

@Test func theSevenMappedToolsGetTheirCanonicalVerb() {
    #expect(ClaudeToolVocabulary.canonical(for: "Read") == .read)
    #expect(ClaudeToolVocabulary.canonical(for: "Write") == .write)
    #expect(ClaudeToolVocabulary.canonical(for: "Edit") == .edit)
    #expect(ClaudeToolVocabulary.canonical(for: "NotebookEdit") == .edit)
    #expect(ClaudeToolVocabulary.canonical(for: "Bash") == .execute)
    #expect(ClaudeToolVocabulary.canonical(for: "WebSearch") == .search)
    #expect(ClaudeToolVocabulary.canonical(for: "WebFetch") == .fetch)
}

/// Spec §4.1: inventar um verbo faria o handoff mandar ao próximo harness uma
/// instrução que ninguém pediu. `nil` é a resposta honesta.
@Test func aToolWithoutAnEquivalentVerbIsNil() {
    #expect(ClaudeToolVocabulary.canonical(for: "Task") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: "Skill") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: "mcp__figma__get_file") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: "") == nil)
}

/// O casamento é exato, não por prefixo nem sem distinguir maiúsculas: o CLI
/// escreve os nomes numa grafia só, e afrouxar aqui faria uma ferramenta
/// chamada `ReadOnlyThing` virar `.read`.
@Test func theMatchIsExact() {
    #expect(ClaudeToolVocabulary.canonical(for: "read") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: "ReadFile") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: " Bash") == nil)
}

/// A tabela é derivada do array `tools` do `system/init` real. Este teste lê
/// esse array da fixture e fixa quais nomes têm verbo — se uma regravação
/// futura trouxer uma ferramenta nova, ele aponta exatamente onde decidir.
@Test func theTableAgreesWithTheRecordedToolList() throws {
    // Mesmo acesso que `ControlFramesTests.fixtureLines` já usa.
    let url = try #require(Bundle.module.url(
        forResource: "Fixtures/hello", withExtension: "ndjson"))
    let firstLine = try #require(
        String(contentsOf: url, encoding: .utf8).split(separator: "\n").first)
    let initLine = try JSONDecoder().decode(JSONValue.self, from: Data(firstLine.utf8))
    #expect(initLine["subtype"]?.stringValue == "init")

    let tools = try #require(initLine["tools"]?.arrayValue).compactMap(\.stringValue)
    #expect(tools.count == 25)

    let mapped = Set(tools.filter { ClaudeToolVocabulary.canonical(for: $0) != nil })
    #expect(mapped == ["Read", "Write", "Edit", "NotebookEdit", "Bash", "WebSearch", "WebFetch"])
}

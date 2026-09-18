import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

@Test func theNineMappedToolsGetTheirCanonicalVerb() {
    #expect(ClaudeToolVocabulary.canonical(for: "Read") == .read)
    #expect(ClaudeToolVocabulary.canonical(for: "Write") == .write)
    #expect(ClaudeToolVocabulary.canonical(for: "Edit") == .edit)
    #expect(ClaudeToolVocabulary.canonical(for: "NotebookEdit") == .edit)
    #expect(ClaudeToolVocabulary.canonical(for: "Bash") == .execute)
    #expect(ClaudeToolVocabulary.canonical(for: "WebSearch") == .search)
    #expect(ClaudeToolVocabulary.canonical(for: "Glob") == .search)
    #expect(ClaudeToolVocabulary.canonical(for: "Grep") == .search)
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

/// Este teste amostra a configuração de UMA máquina — a que gravou
/// `hello.ndjson` — não define o contrato do CLI (ver o doc comment de
/// `ClaudeToolVocabulary`). Ele fixa que o subconjunto MAPEADO dos nomes
/// daquela gravação é exatamente os sete que já existiam antes desta onda; se
/// uma regravação futura trouxer uma ferramenta nova, ele aponta exatamente
/// onde decidir. `Glob` e `Grep` são mapeados de propósito apesar de
/// ausentes desta amostra — por isso o `Set` comparado abaixo continua com
/// sete nomes, não nove.
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

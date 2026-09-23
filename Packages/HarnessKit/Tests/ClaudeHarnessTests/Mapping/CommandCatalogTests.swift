import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

@Test func oCatalogoSaiDoEventoDeInit() {
    let line: JSONValue = .object([
        "subtype": .string("init"),
        "model": .string("claude-opus-4"),
        "session_id": .string("abc"),
        "slash_commands": .array([.string("compact"), .string("clear"),
                                  .string("apple-design"),
                                  .string("mcp__ai_memory__recall"), .string("mcp")]),
        "skills": .array([.string("commit"), .string("apple-design")]),
        "mcp_servers": .array([
            .object(["name": .string("ai-memory"), "status": .string("connected")]),
            .object(["name": .string("figma"), "status": .string("needs-auth")]),
            .object(["name": .string("github"), "status": .string("failed")]),
        ]),
    ])

    let catalog = ClaudeEventMapper.catalog(from: line)

    #expect(catalog.supportsCompact)
    #expect(catalog.skills == ["apple-design", "commit"])
    #expect(catalog.servers.count == 3)
    #expect(catalog.servers[0].prompts == ["mcp__ai_memory__recall"])
    #expect(catalog.servers[1].status == .needsAuth)
    #expect(catalog.servers[2].status == .failed)
    #expect(catalog.servers[2].prompts.isEmpty)
}

@Test func umInitSemOsCamposNovosNaoQuebra() {
    let catalog = ClaudeEventMapper.catalog(from: .object(["subtype": .string("init")]))
    #expect(catalog.isEmpty)
}

@Test func oCatalogoSobreviveAoDiscoParaAbrirOMenuEmSessaoFria() throws {
    let catalog = CommandCatalog(
        skills: ["apple-design"],
        servers: [.init(name: "ai-memory", status: .connected,
                        prompts: ["mcp__ai_memory__recall"])],
        supportsCompact: true)

    let data = try JSONEncoder().encode(catalog)
    let restored = try JSONDecoder().decode(CommandCatalog.self, from: data)

    #expect(restored == catalog)
    #expect(!restored.isEmpty)
}

@Test func oCatalogoSaiDeUmInitDeVerdade() throws {
    let url = try #require(Bundle.module.url(forResource: "init-catalog",
                                             withExtension: "json",
                                             subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let line = try JSONDecoder().decode(JSONValue.self, from: data)

    let catalog = ClaudeEventMapper.catalog(from: line)

    #expect(catalog.supportsCompact)
    #expect(catalog.skills.count > 10)
    #expect(!catalog.servers.isEmpty)
    #expect(!catalog.isEmpty)
}

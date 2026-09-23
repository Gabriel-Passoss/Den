import Testing
import Foundation
import HarnessCore
@testable import DevSpace

private let catalog = CommandCatalog(
    skills: ["review", "preview"],
    servers: [
        .init(name: "context7", status: .connected, prompts: ["mcp__context7__search"]),
        .init(name: "quebrado", status: .needsAuth),
    ],
    supportsCompact: true)

@Test func queryRequiresALoneSlashToken() {
    #expect(SlashCatalog.query(in: "/comp") == "comp")
    #expect(SlashCatalog.query(in: "/") == "")
    #expect(SlashCatalog.query(in: "sem barra") == nil)
    #expect(SlashCatalog.query(in: "/duas\nlinhas") == nil)
}

@Test func rootGroupsSkillsAndServers() {
    let items = SlashCatalog.root(from: catalog)
    #expect(items.map(\.id) == ["compact", "group:skills", "group:mcp"])
    #expect(items[1].detail == "2 habilidades")
}

@Test func mcpFlattensPromptsAndKeepsBareServers() {
    let items = SlashCatalog.mcp(from: catalog)
    #expect(items.map(\.id) == ["mcp__context7__search", "mcp:quebrado"])
    #expect(items[0].title == "context7 · search")
    #expect(items[1].detail == "precisa autenticar")
}

@Test func matchesRankPrefixHitsFirst() {
    let hits = SlashCatalog.matches("rev", in: catalog, group: nil)
    #expect(hits.map(\.id) == ["review", "preview"])
}

@Test func matchesRestrictThePoolToTheOpenGroup() {
    let skills = SlashCatalog.matches("", in: catalog, group: .skills)
    #expect(skills.map(\.id) == ["review", "preview"])
    #expect(SlashCatalog.matches("context", in: catalog, group: .skills).isEmpty)
}

@Test func commandTextComesFromTheKind() {
    #expect(SlashCatalog.compact().command == "/compact")
    #expect(SlashCatalog.skills(from: catalog).first?.command == "/review")
    #expect(SlashCatalog.root(from: catalog)[1].command == nil)
}

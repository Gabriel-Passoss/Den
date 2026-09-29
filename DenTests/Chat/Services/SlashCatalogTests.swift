import Testing
import Foundation
import HarnessCore
@testable import Den

private let catalog = CommandCatalog(
    skills: ["review", "preview"],
    servers: [
        .init(name: "context7", status: .connected, prompts: ["mcp__context7__search"]),
        .init(name: "broken", status: .needsAuth),
    ],
    supportsCompact: true)

@Test func queryRequiresALoneSlashToken() {
    #expect(SlashCatalog.query(in: "/comp") == "comp")
    #expect(SlashCatalog.query(in: "/") == "")
    #expect(SlashCatalog.query(in: "no slash") == nil)
    #expect(SlashCatalog.query(in: "/two\nlines") == nil)
}

@Test func rootGroupsSkillsAndServers() throws {
    let items = SlashCatalog.root(from: catalog)
    #expect(items.map(\.id) == ["compact", "group:skills", "group:mcp"])
    #expect(try #require(items.dropFirst().first).detail == "2 habilidades")
}

@Test func mcpFlattensPromptsAndKeepsBareServers() throws {
    let items = SlashCatalog.mcp(from: catalog)
    #expect(items.map(\.id) == ["mcp__context7__search", "mcp:broken"])
    #expect(try #require(items.first).title == "context7 · search")
    #expect(try #require(items.dropFirst().first).detail == "precisa autenticar")
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

@Test func commandTextComesFromTheKind() throws {
    #expect(SlashCatalog.compact().command == "/compact")
    #expect(SlashCatalog.skills(from: catalog).first?.command == "/review")
    let group = try #require(SlashCatalog.root(from: catalog).dropFirst().first)
    #expect(group.command == nil)
}

import Testing
import Foundation
import DenMemory

private let den = ProjectIdentity(root: URL(fileURLWithPath: "/code/den"))
private let noon = dawn.addingTimeInterval(3600)

private struct Desk {
    let scratch: Scratch
    let repository: FileMemoryRepository
    let consolidator: MemoryConsolidator

    init() throws {
        scratch = try Scratch()
        repository = FileMemoryRepository(root: scratch.root)
        consolidator = MemoryConsolidator(repository: repository)
    }
}

private func fact(_ title: String, layer: MemoryLayer = .project, category: String = "convention",
                  body: String = "corpo", page: String? = nil) -> MemoryCandidate {
    MemoryCandidate(layer: layer, category: category, title: title, body: body, page: page)
}

@Test func newFactsBecomePagesInTheirLayers() throws {
    let desk = try Desk()
    defer { desk.scratch.remove() }
    let session = UUID()

    let saved = try desk.consolidator.apply(
        [fact("Commits convencionais", body: "tipo(escopo): descrição"),
         fact("Sem coautor", layer: .user, category: "rule", body: "Nunca adicionar.")],
        project: den, session: session, now: noon)

    #expect(saved.map(\.slug) == ["commits-convencionais", "sem-coautor"])
    #expect(desk.repository.pages(in: .project(den)) == [
        MemoryPage(slug: "commits-convencionais", title: "Commits convencionais", category: .convention,
                   body: "tipo(escopo): descrição", created: noon, updated: noon, sessions: [session]),
    ])
    #expect(desk.repository.pages(in: .user).map(\.category) == [.rule])
}

@Test func aFactAimedAtAnExistingPageUpdatesIt() throws {
    let desk = try Desk()
    defer { desk.scratch.remove() }
    let first = UUID()
    let second = UUID()
    try desk.repository.save(note("Commits", .convention, body: "antes", slug: "commits", sessions: [first]),
                             in: .project(den))

    _ = try desk.consolidator.apply([fact("Commits convencionais", category: "naming", body: "depois",
                                          page: "commits")],
                                    project: den, session: second, now: noon)
    _ = try desk.consolidator.apply([fact("Commits convencionais", category: "naming", body: "de novo",
                                          page: "commits")],
                                    project: den, session: second, now: noon)

    #expect(desk.repository.pages(in: .project(den)) == [
        MemoryPage(slug: "commits", title: "Commits convencionais", category: .naming, body: "de novo",
                   created: dawn, updated: noon, sessions: [first, second]),
    ])
}

@Test func aFactWithTheTitleOfAnExistingPageUpdatesItInsteadOfDuplicating() throws {
    let desk = try Desk()
    defer { desk.scratch.remove() }
    try desk.repository.save(note("Sem coautor", .rule, body: "antes"), in: .user)

    _ = try desk.consolidator.apply([fact("Sem coautor", layer: .user, category: "rule", body: "depois",
                                          page: "pagina-que-nao-existe")],
                                    project: nil, session: UUID(), now: noon)

    #expect(desk.repository.pages(in: .user).map(\.body) == ["depois"])
    #expect(desk.repository.pages(in: .user).map(\.created) == [dawn])

    let again = try desk.consolidator.apply([fact("SEM COAUTOR", layer: .user, body: "em maiúsculas")],
                                            project: nil, session: UUID(), now: noon)
    #expect(again.map(\.slug) == ["sem-coautor"])
    #expect(desk.repository.pages(in: .user).map(\.body) == ["em maiúsculas"])
}

@Test func aProjectFactOutsideARepositoryIsDropped() throws {
    let desk = try Desk()
    defer { desk.scratch.remove() }

    let saved = try desk.consolidator.apply(
        [fact("Só faz sentido num repositório"), fact("Vale sempre", layer: .user, category: "workflow")],
        project: nil, session: UUID(), now: noon)

    #expect(saved.map(\.title) == ["Vale sempre"])
    #expect(desk.repository.pages(in: .user).map(\.category) == [.workflow])
}

@Test func aCategoryFromTheWrongLayerBecomesANote() throws {
    let desk = try Desk()
    defer { desk.scratch.remove() }

    _ = try desk.consolidator.apply([fact("Estilo", category: "code-style"), fact("Livre", category: "??")],
                                    project: den, session: UUID(), now: noon)

    #expect(desk.repository.pages(in: .project(den)).map(\.category) == [.note, .note])
}

@Test func aPagePointerThatWouldLeaveTheFolderIsIgnored() throws {
    let desk = try Desk()
    defer { desk.scratch.remove() }

    let saved = try desk.consolidator.apply([fact("Título são", page: "../../fora")],
                                            project: den, session: UUID(), now: noon)

    #expect(saved.map(\.slug) == ["titulo-sao"])
}

@Test func twoDifferentFactsNeverShareAFile() throws {
    let desk = try Desk()
    defer { desk.scratch.remove() }
    let long = String(repeating: "palavra ", count: 12)

    let saved = try desk.consolidator.apply(
        [fact("日本語のタイトル", body: "um"), fact("別のタイトル", body: "dois"), fact("もう一つ", body: "três"),
         fact(long + "primeiro", body: "quatro"), fact(long + "segundo", body: "cinco")],
        project: den, session: UUID(), now: noon)

    #expect(saved.map(\.slug).prefix(3) == ["memoria", "memoria-2", "memoria-3"])
    #expect(Set(saved.map(\.slug)).count == 5)
    #expect(desk.repository.pages(in: .project(den)).map(\.body).sorted() == ["cinco", "dois", "quatro", "três", "um"])
}

@Test func aFactCalledIndexDoesNotTakeTheWikisFrontPage() throws {
    let desk = try Desk()
    defer { desk.scratch.remove() }

    let saved = try desk.consolidator.apply([fact("Index", body: "sobre índices do banco")],
                                            project: den, session: UUID(), now: noon)

    #expect(saved.map(\.slug) == ["index-2"])
    #expect(desk.repository.pages(in: .project(den)).map(\.body) == ["sobre índices do banco"])
    #expect(try desk.scratch.read("projects/\(den.slug)/index.md").hasPrefix("# Memória do projeto den"))
}

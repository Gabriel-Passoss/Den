import Testing
import Foundation
import DenMemory

private let den = ProjectIdentity(root: URL(fileURLWithPath: "/code/den"))
private let other = ProjectIdentity(root: URL(fileURLWithPath: "/code/other"))

private struct Wiki {
    let scratch: Scratch
    let repository: FileMemoryRepository

    init() throws {
        scratch = try Scratch()
        repository = FileMemoryRepository(root: scratch.root.appending(path: "memory"))
    }
}

@Test func aWikiThatDoesNotExistYetIsEmpty() throws {
    let wiki = try Wiki()
    defer { wiki.scratch.remove() }

    #expect(wiki.repository.pages(in: .user).isEmpty)
    #expect(wiki.repository.pages(in: .project(den)).isEmpty)
}

@Test func savedPagesComeBackGroupedByCategoryThenByTitle() throws {
    let wiki = try Wiki()
    defer { wiki.scratch.remove() }
    let pages = [note("zebra", .convention), note("Abelha", .pitfall), note("abacate", .convention),
                 note("Solta"), note("Camadas", .architecture)]

    for page in pages { try wiki.repository.save(page, in: .project(den)) }

    #expect(wiki.repository.pages(in: .project(den)).map(\.title)
        == ["abacate", "zebra", "Camadas", "Abelha", "Solta"])
    #expect(wiki.repository.pages(in: .project(den)).first == note("abacate", .convention))
}

@Test func pagesWithTheSameTitleKeepAStableOrder() throws {
    let wiki = try Wiki()
    defer { wiki.scratch.remove() }
    try wiki.repository.save(note("Igual", slug: "b"), in: .user)
    try wiki.repository.save(note("igual", slug: "a"), in: .user)

    #expect(wiki.repository.pages(in: .user).map(\.slug) == ["a", "b"])
}

@Test func layersAndProjectsNeverMix() throws {
    let wiki = try Wiki()
    defer { wiki.scratch.remove() }
    try wiki.repository.save(note("do usuário", .rule), in: .user)
    try wiki.repository.save(note("do den", .convention), in: .project(den))
    try wiki.repository.save(note("do outro", .convention), in: .project(other))

    #expect(wiki.repository.pages(in: .user).map(\.title) == ["do usuário"])
    #expect(wiki.repository.pages(in: .project(den)).map(\.title) == ["do den"])
    #expect(wiki.repository.pages(in: .project(other)).map(\.title) == ["do outro"])
    #expect(wiki.repository.directory(of: .user).lastPathComponent == "user")
    #expect(wiki.repository.directory(of: .project(den)).path.hasSuffix("projects/" + den.slug))
    #expect(wiki.repository.file(for: "do-den", in: .project(den)).lastPathComponent == "do-den.md")
}

@Test func savingAgainReplacesThePage() throws {
    let wiki = try Wiki()
    defer { wiki.scratch.remove() }
    try wiki.repository.save(note("Regra", .rule, body: "antes"), in: .user)

    try wiki.repository.save(note("Regra", .rule, body: "depois"), in: .user)

    #expect(wiki.repository.pages(in: .user).map(\.body) == ["depois"])
}

@Test func theIndexIsTheWikisFrontPageAndNotAPage() throws {
    let wiki = try Wiki()
    defer { wiki.scratch.remove() }
    try wiki.repository.save(note("Commits convencionais", .convention), in: .project(den))
    try wiki.repository.save(note("Camadas", .architecture), in: .project(den))
    try wiki.repository.save(note("Feita à mão", slug: "Feita à mão"), in: .project(den))

    let index = try wiki.scratch.read("memory/projects/\(den.slug)/index.md")

    #expect(index == """
        # Memória do projeto den

        ## Convenções

        - [Commits convencionais](commits-convencionais.md)

        ## Arquitetura e decisões

        - [Camadas](camadas.md)

        ## Notas

        - [Feita à mão](Feita%20%C3%A0%20m%C3%A3o.md)

        """)
    #expect(wiki.repository.pages(in: .project(den)).count == 3)
    try wiki.repository.save(note("Regra", .rule), in: .user)
    #expect(try wiki.scratch.read("memory/user/index.md").hasPrefix("# Memória do usuário\n\n## Regras\n"))
}

@Test func deletingAPageRemovesItFromTheFolderAndTheIndex() throws {
    let wiki = try Wiki()
    defer { wiki.scratch.remove() }
    try wiki.repository.save(note("Fica", .rule), in: .user)
    try wiki.repository.save(note("Vai", .rule), in: .user)

    try wiki.repository.delete("vai", in: .user)
    try wiki.repository.delete("nunca-existiu", in: .user)

    #expect(wiki.repository.pages(in: .user).map(\.title) == ["Fica"])
    #expect(try !wiki.scratch.read("memory/user/index.md").contains("Vai"))

    try wiki.repository.delete("fica", in: .user)
    #expect(try wiki.scratch.read("memory/user/index.md") == "# Memória do usuário\n\n_Nenhuma memória ainda._\n")
}

@Test func strangeFilesInTheFolderNeverBreakTheList() throws {
    let wiki = try Wiki()
    defer { wiki.scratch.remove() }
    try wiki.repository.save(note("Boa", .rule), in: .user)
    try wiki.scratch.write("sem cabeçalho nenhum", to: "memory/user/Escrita à mão.md")
    try wiki.scratch.write("não é markdown", to: "memory/user/planilha.csv")
    _ = try wiki.scratch.folder("memory/user/uma-pasta.md")

    let pages = wiki.repository.pages(in: .user)

    #expect(pages.map(\.title) == ["Boa", "Escrita à mão"])
    #expect(pages.last?.category == .note)
    #expect(pages.last?.body == "sem cabeçalho nenhum")
}

@Test func aNameThatWouldLeaveTheFolderIsRefused() throws {
    let wiki = try Wiki()
    defer { wiki.scratch.remove() }

    for name in ["../fora", "sub/pasta", "..", ".", ""] {
        #expect(throws: MemoryRepositoryError.unsafeName(name)) {
            try wiki.repository.save(note("x", slug: name), in: .user)
        }
        #expect(throws: MemoryRepositoryError.unsafeName(name)) {
            try wiki.repository.delete(name, in: .user)
        }
    }
    #expect(!FileManager.default.fileExists(atPath: wiki.scratch.root.appending(path: "memory/fora.md").path))
}

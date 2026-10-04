import Testing
import Foundation
import DenMemory

private let created = Date(timeIntervalSince1970: 1_700_000_000)
private let updated = Date(timeIntervalSince1970: 1_700_086_400)
private let later = Date(timeIntervalSince1970: 1_800_000_000)
private let firstSession = UUID()
private let secondSession = UUID()

private func page(_ title: String = "Commits seguem Conventional Commits",
                  category: MemoryCategory = .convention,
                  body: String = "As mensagens usam `tipo(escopo): descrição`.") -> MemoryPage {
    MemoryPage(slug: "commits", title: title, category: category, body: body,
               created: created, updated: updated, sessions: [firstSession, secondSession])
}

private func read(_ text: String, layer: MemoryLayer = .project) -> MemoryPage {
    MemoryPageFile.parse(text, slug: "nota-solta", layer: layer, fallbackDate: later)
}

@Test func aPageSurvivesBeingWrittenAndReadBack() {
    let original = page()

    let text = MemoryPageFile.render(original)

    #expect(MemoryPageFile.parse(text, slug: "commits", layer: .project, fallbackDate: later) == original)
    #expect(text.hasPrefix("---\ntitle: Commits seguem Conventional Commits\ncategory: convention\n"))
    #expect(text.hasSuffix("As mensagens usam `tipo(escopo): descrição`.\n"))
}

@Test func aTitleWithAColonOrALineBreakStaysOneHeaderLine() {
    let awkward = page("Regra: nunca\nquebrar o título")

    let reread = MemoryPageFile.parse(MemoryPageFile.render(awkward), slug: "commits", layer: .project,
                                      fallbackDate: later)

    #expect(reread.title == "Regra: nunca quebrar o título")
    #expect(reread.body == awkward.body)
}

@Test func aRuleInTheBodyIsNotMistakenForTheHeader() {
    let ruled = page(body: "Antes\n\n---\n\nDepois\ncategory: naming")

    let reread = MemoryPageFile.parse(MemoryPageFile.render(ruled), slug: "commits", layer: .project,
                                      fallbackDate: later)

    #expect(reread == ruled)
}

@Test func aFileWrittenByHandWithoutAHeaderIsANote() {
    let loose = read("# Só um lembrete\n\nNada de cabeçalho aqui.\n")

    #expect(loose.title == "Nota solta")
    #expect(loose.category == .note)
    #expect(loose.body == "# Só um lembrete\n\nNada de cabeçalho aqui.")
    #expect(loose.created == later)
    #expect(loose.updated == later)
    #expect(loose.sessions.isEmpty)
}

@Test func aHeaderThatNeverClosesIsReadAsBody() {
    let open = read("---\ntitle: Pela metade\n\nO corpo começa sem fechar o cabeçalho.")

    #expect(open.title == "Nota solta")
    #expect(open.body.hasPrefix("---\ntitle: Pela metade"))
}

@Test func anEmptyFileIsAnEmptyNote() {
    let empty = read("")

    #expect(empty.title == "Nota solta")
    #expect(empty.body.isEmpty)
    #expect(empty.category == .note)
}

@Test func aHeaderWithGapsFallsBackFieldByField() {
    let partial = read("""
        ---
        Title:   Pela metade
        category: nao-existe
        created: ontem
        sessions: \(firstSession.uuidString), lixo, \(secondSession.uuidString)
        autor: alguém
        linha sem dois pontos
        ---
        Corpo.
        """)

    #expect(partial.title == "Pela metade")
    #expect(partial.category == .note)
    #expect(partial.created == later)
    #expect(partial.updated == later)
    #expect(partial.sessions == [firstSession, secondSession])
    #expect(partial.body == "Corpo.")
}

@Test func aCategoryOnlyCountsInItsOwnLayer() {
    #expect(MemoryCategory.parse("convention", in: .project) == .convention)
    #expect(MemoryCategory.parse(" Business-Rule ", in: .project) == .businessRule)
    #expect(MemoryCategory.parse("convention", in: .user) == .note)
    #expect(MemoryCategory.parse("rule", in: .user) == .rule)
    #expect(MemoryCategory.parse("rule", in: .project) == .note)
    #expect(MemoryCategory.parse("note", in: .user) == .note)
    #expect(MemoryCategory.parse("qualquer coisa", in: .project) == .note)
    #expect(read("---\ncategory: code-style\n---\nx", layer: .user).category == .codeStyle)
}

@Test func everyCategoryBelongsSomewhereAndHasAName() {
    #expect(MemoryCategory.known(in: .project) == [.convention, .naming, .architecture, .businessRule,
                                                   .glossary, .pitfall, .command, .note])
    #expect(MemoryCategory.known(in: .user) == [.codeStyle, .rule, .workflow, .communication,
                                                .environment, .note])
    #expect(Set(MemoryCategory.allCases.map(\.label)).count == MemoryCategory.allCases.count)
    #expect(MemoryCategory.businessRule.label == "Regras de negócio")
    #expect(MemoryCategory.note.label == "Notas")
}

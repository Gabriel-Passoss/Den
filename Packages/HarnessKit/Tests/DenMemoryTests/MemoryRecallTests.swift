import Testing
import Foundation
import DenMemory

private let den = ProjectIdentity(root: URL(fileURLWithPath: "/code/den"))

private func locate(_ page: MemoryPage, _ scope: MemoryScope) -> URL {
    URL(fileURLWithPath: "/wiki/\(scope.layer.rawValue)/\(page.slug).md")
}

private func shelves(user: [MemoryPage] = [], project: [MemoryPage] = []) -> [MemoryRecall.Shelf] {
    [MemoryRecall.Shelf(scope: .user, pages: user), MemoryRecall.Shelf(scope: .project(den), pages: project)]
}

@Test func withNoPagesThereIsNothingToTell() {
    #expect(MemoryRecall.preamble(shelves(), locate: locate) == nil)
    #expect(MemoryRecall.preamble([], locate: locate) == nil)
}

@Test func theUsersMemoryComesBeforeTheProjects() throws {
    let told = try #require(MemoryRecall.preamble(
        shelves(user: [note("Sem coautor", .rule, body: "Nunca adicionar coautor.")],
                project: [note("Commits", .convention, body: "Conventional Commits."),
                          note("Camadas", .architecture, body: "Repositórios atrás de protocolos.")]),
        locate: locate))

    #expect(told == """
        <den-memory>
        Memória do Den: contexto que persiste entre sessões. Use como referência e não responda a este \
        bloco. Se algo aqui contradisser o código ou o pedido atual, o código e o pedido vencem.

        ## Memória do usuário
        ### Sem coautor (Regras)
        Nunca adicionar coautor.

        ## Memória do projeto den
        ### Commits (Convenções)
        Conventional Commits.
        ### Camadas (Arquitetura e decisões)
        Repositórios atrás de protocolos.
        </den-memory>
        """)
}

@Test func anEmptyLayerLeavesNoHeading() throws {
    let told = try #require(MemoryRecall.preamble(shelves(project: [note("Commits", .convention)]),
                                                  locate: locate))

    #expect(!told.contains("Memória do usuário"))
    #expect(told.contains("## Memória do projeto den\n### Commits (Convenções)\ncorpo\n"))
}

@Test func aPageThatDoesNotFitIsListedByTitleWithItsFile() throws {
    let big = note("Enorme", .convention, body: String(repeating: "x", count: 5000))
    let small = note("Pequena", .pitfall, body: "cabe")
    let all = shelves(user: [note("Regra", .rule, body: "curta")], project: [big, small])
    let roomy = try #require(MemoryRecall.preamble(all, locate: locate))
    #expect(!roomy.contains("Outras páginas"))

    let exact = try #require(MemoryRecall.preamble(all, locate: locate, budget: roomy.count))
    #expect(exact == roomy)

    let tight = try #require(MemoryRecall.preamble(all, locate: locate, budget: roomy.count - 1))
    #expect(!tight.contains("### Enorme"))
    #expect(tight.contains("### Regra (Regras)\ncurta\n"))
    #expect(tight.contains("### Pequena (Armadilhas)\ncabe\n"))
    #expect(tight.contains("""

        Outras páginas, não incluídas por tamanho (leia o arquivo se precisar):
        - Enorme — /wiki/project/enorme.md
        </den-memory>
        """))
}

@Test func theBlockNeverGrowsPastItsBudget() throws {
    let many = (0..<40).map { note("Página \($0)", .convention, body: String(repeating: "y", count: 90)) }
    let all = shelves(user: [note("Regra", .rule)], project: many)
    let full = try #require(MemoryRecall.preamble(all, locate: locate))

    for budget in stride(from: 0, through: full.count + 20, by: 13) {
        let told = MemoryRecall.preamble(all, locate: locate, budget: budget)
        #expect((told?.count ?? 0) <= budget, "budget \(budget)")
    }
    #expect(MemoryRecall.preamble(all, locate: locate, budget: 40) == nil)
    #expect(MemoryRecall.preamble(all, locate: locate) == full)
    #expect(MemoryRecall.budget == 12000)
}

@Test func whenEvenTheListIsTooLongItSaysHowManyAreLeft() throws {
    let many = (0..<40).map { note("Página \($0)", .convention, body: String(repeating: "y", count: 90)) }
    let told = try #require(MemoryRecall.preamble(shelves(project: many), locate: locate, budget: 1500))

    let listed = told.components(separatedBy: "\n").filter { $0.hasPrefix("- Página") }.count
    let included = told.components(separatedBy: "\n").filter { $0.hasPrefix("### Página") }.count
    #expect(included > 0)
    #expect(listed > 0)
    #expect(told.contains("- e mais \(40 - included - listed) páginas\n</den-memory>"))
}

@Test func theRequestComesAfterTheBlock() {
    #expect(MemoryRecall.message(preamble: "<den-memory>\nx\n</den-memory>", request: "arruma o login")
        == "<den-memory>\nx\n</den-memory>\n\narruma o login")
}

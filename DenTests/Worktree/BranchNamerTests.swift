import Testing
import Foundation
@testable import Den

@Test func aTicketKeyLeadsAndKeepsItsCase() {
    #expect(BranchNamer.name(for: "NS-1472 melhorias nos seletores de data", prefix: "den/")
            == "den/NS-1472-melhorias-nos-seletores-de-data")
}

@Test func aTicketKeyInTheMiddleMovesToTheFront() {
    #expect(BranchNamer.name(for: "corrige o bug NS-38 no importador", prefix: "den/")
            == "den/NS-38-corrige-o-bug-no-importador")
}

@Test func accentsAreFoldedAndOnlyFiveWordsKept() {
    #expect(BranchNamer.name(for: "Corrige a validação do formulário de cadastro", prefix: "den/")
            == "den/corrige-a-validacao-do-formulario")
}

@Test func mentionsCommandsAndLinksAreLeftOut() {
    #expect(BranchNamer.name(
        for: "/review @src/app.ts veja https://example.com/a e conserte o login", prefix: "den/")
            == "den/veja-e-conserte-o-login")
}

@Test func theNameStopsAtAWordBoundaryWithinTheLimit() {
    let name = BranchNamer.name(
        for: "implementa a sincronização bidirecional extremamente complicada", prefix: "den/")
    #expect(name == "den/implementa-a-sincronizacao-bidirecional")
}

@Test func aSingleHugeWordIsCutAtTheLimit() {
    let stem = BranchNamer.stem(for: String(repeating: "a", count: 60))
    #expect(stem == String(repeating: "a", count: BranchNamer.limit))
}

@Test func aMessageWithNothingUsableFallsBackToTarefa() {
    #expect(BranchNamer.name(for: "@src/app.ts 🚀", prefix: "den/", fallback: "1a2b") == "den/tarefa-1a2b")
    #expect(BranchNamer.name(for: "/compact", prefix: "den/", fallback: "1a2b") == "den/tarefa-1a2b")
    let random = BranchNamer.name(for: "   ", prefix: "den/")
    #expect(random.wholeMatch(of: #/den\/tarefa-[0-9a-f]{4}/#) != nil)
}

@Test func aTakenNameGetsTheNextFreeSuffix() {
    let taken: Set<String> = ["den/fix-login", "den/fix-login-2"]
    #expect(BranchNamer.name(for: "fix login", prefix: "den/", taken: { taken.contains($0) })
            == "den/fix-login-3")
}

@Test func anEmptyPrefixLeavesTheStemAlone() {
    #expect(BranchNamer.name(for: "fix login", prefix: "") == "fix-login")
}

@Test func aLowercaseKeyIsJustWords() {
    #expect(BranchNamer.name(for: "ns-1472 algo", prefix: "den/") == "den/ns-1472-algo")
}

@Test func theFolderTurnsSlashesIntoDashes() {
    #expect(BranchNamer.folder(for: "feat/NS-1-x") == "feat-NS-1-x")
    #expect(BranchNamer.folder(for: "feat/a/b") == "feat-a-b")
}

@Test func aGivenStemGetsThePrefixAndTheNextFreeSuffix() {
    #expect(BranchNamer.name(stem: "fix-login", prefix: "den/") == "den/fix-login")
    #expect(BranchNamer.name(stem: "fix-login", prefix: "den/", taken: { $0 == "den/fix-login" })
            == "den/fix-login-2")
}

@Test func theTicketKeyOfAMessageIsFound() {
    #expect(BranchNamer.ticketKey(in: "corrige o bug NS-38 no importador") == "NS-38")
    #expect(BranchNamer.ticketKey(in: "corrige o bug no importador") == nil)
}

@Test func theTypeOfAMessageIsGuessedFromItsWords() {
    #expect(BranchNamer.type(for: "corrige o redirecionamento do login") == "fix")
    #expect(BranchNamer.type(for: "Bug no importador de CSV") == "fix")
    #expect(BranchNamer.type(for: "refatora o módulo de sessões") == "refactor")
    #expect(BranchNamer.type(for: "adiciona testes ao importador") == "test")
    #expect(BranchNamer.type(for: "documenta a API de pagamentos") == "docs")
    #expect(BranchNamer.type(for: "exporta os relatórios em CSV") == "feat")
}

import Testing
@testable import Den

@Test func aReplyEndingInAQuestionIsAsking() {
    #expect(ReplySuggestion.isAsking("Posso usar rsync.\n\nQuer que eu inclua a rotação?"))
}

@Test func aQuestionFollowedByAShortCloserIsStillAsking() {
    #expect(ReplySuggestion.isAsking(
        "Terminei a primeira parte.\n\nQuer que eu continue?\nÉ só avisar."))
}

@Test func aBoldQuestionIsAsking() {
    #expect(ReplySuggestion.isAsking("Pronto.\n\n**Quer que eu rode os testes?**"))
}

@Test func aQuestionInParenthesesIsAsking() {
    #expect(ReplySuggestion.isAsking("Vou seguir com o rsync (ou prefere outro?)."))
}

@Test func aQuestionMarkInsideACodeBlockIsNotAsking() {
    let reply = "Use assim:\n\n```swift\nlet name = user?.name ?? \"?\"\n```\n\nIsso resolve."
    #expect(!ReplySuggestion.isAsking(reply))
}

@Test func aQuestionMarkInInlineCodeIsNotAsking() {
    #expect(!ReplySuggestion.isAsking("Troquei para `user?.name` no fim."))
}

@Test func aQuestionMarkInAURLIsNotAsking() {
    #expect(!ReplySuggestion.isAsking("A documentação está em https://example.com/search?q=rsync"))
}

@Test func aQuestionEarlyInALongReplyIsNotAsking() {
    let reply = "Por que isso quebrou? Explico abaixo.\n\nPrimeiro, o cache.\n"
        + "Depois, o índice.\nPor fim, o lock.\nTudo corrigido."
    #expect(!ReplySuggestion.isAsking(reply))
}

@Test func aReplyWithoutQuestionsIsNotAsking() {
    #expect(!ReplySuggestion.isAsking("Feito. Os testes passaram."))
}

@Test func theInstructionCarriesTheRequestTheReplyAndTheNoneMarker() {
    let text = ReplySuggestion.instruction(request: "crie o backup", reply: "Quer rotação?")
    #expect(text.contains("Pedido do usuário: crie o backup"))
    #expect(text.contains("Última mensagem do assistente: Quer rotação?"))
    #expect(text.contains(ReplySuggestion.noQuestion))
}

@Test func theInstructionKeepsTheStartOfTheRequestAndTheEndOfTheReply() {
    let request = String(repeating: "a", count: 600) + "CORTADO"
    let reply = "INÍCIO" + String(repeating: "b", count: 1_500)
    let text = ReplySuggestion.instruction(request: request, reply: reply)
    #expect(!text.contains("CORTADO"))
    #expect(!text.contains("INÍCIO"))
    #expect(text.hasSuffix(String(repeating: "b", count: 1_500)))
}

@Test func parseKeepsAPlainReply() {
    #expect(ReplySuggestion.parse("Sim, inclua a rotação.\n") == "Sim, inclua a rotação.")
}

@Test(arguments: ["NENHUMA", "nenhuma.", "Nenhuma", "  NENHUMA  \n"])
func parseTurnsTheNoneMarkerIntoNil(_ output: String) {
    #expect(ReplySuggestion.parse(output) == nil)
}

@Test func parseStripsQuotesAroundTheReply() {
    #expect(ReplySuggestion.parse("“Sim, pode seguir.”") == "Sim, pode seguir.")
    #expect(ReplySuggestion.parse("\"Pode.\"") == "Pode.")
}

@Test func parseRejectsMoreThanOneLine() {
    #expect(ReplySuggestion.parse("Sim.\nE rode os testes.") == nil)
}

@Test func parseRejectsAnOverlongReply() {
    #expect(ReplySuggestion.parse(String(repeating: "a", count: 201)) == nil)
    #expect(ReplySuggestion.parse(String(repeating: "a", count: 200)) != nil)
}

@Test func parseRejectsAnEmptyOutput() {
    #expect(ReplySuggestion.parse("  \n ") == nil)
}

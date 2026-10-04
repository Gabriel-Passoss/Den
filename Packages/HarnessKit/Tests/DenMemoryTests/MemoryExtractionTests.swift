import Testing
import Foundation
import HarnessCore
import DenMemory

private let den = ProjectIdentity(root: URL(fileURLWithPath: "/code/den"))

private func said(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: dawn, kind: .userMessage(text: text, attachments: []), raw: .null)
}

private func answered(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: dawn, kind: .assistantText(text), raw: .null)
}

private func ran(_ command: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: dawn, kind: .toolCall(ToolCall(
        id: UUID().uuidString, rawName: "Bash", canonical: .execute,
        input: .object(["command": .string(command)]))), raw: .null)
}

private func item(layer: String = "project", category: String = "convention", title: String = "Commits",
                  body: String = "Conventional Commits.", page: String = "") -> String {
    """
    {"layer": "\(layer)", "category": "\(category)", "title": "\(title)", "body": "\(body)", "page": "\(page)"}
    """
}

private func reply(_ items: String...) -> String {
    "{\"memories\": [\(items.joined(separator: ", "))]}"
}

@Test func theInstructionCarriesTheRulesTheKnownPagesAndTheConversation() throws {
    let shelves = [
        MemoryRecall.Shelf(scope: .user, pages: [note("Sem coautor", .rule)]),
        MemoryRecall.Shelf(scope: .project(den), pages: [note("Commits convencionais", .convention)]),
    ]

    let instruction = try #require(MemoryExtraction.instruction(
        entries: [said("neste projeto os commits seguem Conventional Commits"), ran("git log"),
                  answered("Anotado.")],
        shelves: shelves))

    #expect(instruction.contains("Responda somente com JSON"))
    #expect(instruction.contains("{\"memories\": []}"))
    #expect(instruction.contains("convention, naming, architecture, business-rule, glossary, pitfall, command, note"))
    #expect(instruction.contains("code-style, rule, workflow, communication, environment, note"))
    #expect(instruction.contains("- [user] sem-coautor: Sem coautor\n"))
    #expect(instruction.contains("- [project] commits-convencionais: Commits convencionais\n"))
    #expect(instruction.hasSuffix("""
        Conversa:
        **Você:** neste projeto os commits seguem Conventional Commits

        _(usou Bash: git log)_

        **Assistente:** Anotado.
        """))
}

@Test func withoutAProjectTheInstructionAsksOnlyForTheUsersLayer() throws {
    let instruction = try #require(MemoryExtraction.instruction(
        entries: [said("prefiro respostas curtas")],
        shelves: [MemoryRecall.Shelf(scope: .user, pages: [])]))

    #expect(instruction.contains("Esta conversa não está num repositório: use somente a camada \"user\"."))
    #expect(instruction.contains("Páginas existentes:\n(nenhuma)\n"))
}

@Test func aConversationWithNothingSaidHasNoInstruction() {
    let thinking = TranscriptEntry(timestamp: dawn, kind: .assistantThinking("hum"), raw: .null)

    #expect(MemoryExtraction.instruction(entries: [], shelves: []) == nil)
    #expect(MemoryExtraction.instruction(entries: [thinking], shelves: []) == nil)
}

@Test func aLongConversationKeepsItsEnd() throws {
    let filler = (0..<400).map { said("mensagem número \($0) " + String(repeating: "z", count: 60)) }

    let instruction = try #require(MemoryExtraction.instruction(
        entries: filler + [said("a última coisa dita")], shelves: []))
    let conversation = try #require(instruction.components(separatedBy: "Conversa:\n").last)

    #expect(conversation.count <= MemoryExtraction.excerptLimit + 40)
    #expect(conversation.hasPrefix("[início da conversa omitido]\n"))
    #expect(conversation.hasSuffix("**Você:** a última coisa dita"))
    #expect(!conversation.contains("mensagem número 0 "))
    #expect(MemoryExtraction.excerptLimit == 16000)
}

@Test func onlyWhatTheUserTypedCountsAsATurn() {
    let entries = [said("primeira"), answered("ok"), said("  "), said("/compact"),
                   said("<local-command-stdout>saída</local-command-stdout>"), said("segunda")]

    #expect(MemoryExtraction.userTurns(in: entries) == 2)
    #expect(MemoryExtraction.userTurns(in: []) == 0)
}

@Test func aReplyIsReadEvenWhenTheModelWrapsIt() throws {
    let wrapped = "Claro! Aqui está:\n```json\n" + reply(item(), item(layer: "user", category: "rule",
                                                                    title: "Sem coautor",
                                                                    body: "Nunca.", page: "sem-coautor"))
        + "\n```\nEspero ter ajudado."

    let candidates = try #require(MemoryExtraction.candidates(from: wrapped))

    #expect(candidates == [
        MemoryCandidate(layer: .project, category: "convention", title: "Commits",
                        body: "Conventional Commits.", page: nil),
        MemoryCandidate(layer: .user, category: "rule", title: "Sem coautor", body: "Nunca.",
                        page: "sem-coautor"),
    ])
}

@Test func anEmptyListMeansNothingNewAndNoJSONMeansUnreadable() {
    #expect(MemoryExtraction.candidates(from: "{\"memories\": []}") == [])
    #expect(MemoryExtraction.candidates(from: "não achei nada para guardar") == nil)
    #expect(MemoryExtraction.candidates(from: "} fora de ordem {") == nil)
    #expect(MemoryExtraction.candidates(from: "{\"memories\": \"nenhuma\"}") == nil)
    #expect(MemoryExtraction.candidates(from: "{\"outra\": []}") == nil)
    #expect(MemoryExtraction.candidates(from: "{isto não fecha") == nil)
}

@Test func itemsThatBreakTheRulesAreDroppedOneByOne() throws {
    let long = String(repeating: "t", count: 121)
    let huge = String(repeating: "b", count: 2001)
    let output = reply(
        item(title: "Boa"),
        item(layer: "team"),
        item(title: "   "),
        item(body: ""),
        item(title: long),
        item(body: huge),
        "{\"layer\": \"project\", \"title\": 7, \"body\": \"x\"}",
        "\"nem é objeto\"",
        "{\"layer\": \" USER \", \"title\": \" Enxuta \", \"body\": \" corpo \"}",
        item(title: String(repeating: "t", count: 120), body: String(repeating: "b", count: 2000)))

    let candidates = try #require(MemoryExtraction.candidates(from: output))

    #expect(candidates.map(\.title) == ["Boa", "Enxuta", String(repeating: "t", count: 120)])
    #expect(candidates[1] == MemoryCandidate(layer: .user, category: "note", title: "Enxuta",
                                             body: "corpo", page: nil))
}

@Test func noMoreThanFiveMemoriesComeOutOfOneReply() throws {
    let output = reply((1...9).map { item(title: "Fato \($0)") }.joined(separator: ", "))

    let candidates = try #require(MemoryExtraction.candidates(from: output))

    #expect(candidates.map(\.title) == ["Fato 1", "Fato 2", "Fato 3", "Fato 4", "Fato 5"])
    #expect(MemoryExtraction.maximum == 5)
}

@Test func anythingThatLooksLikeASecretIsLeftOut() throws {
    let token = "ghp_" + String(repeating: "a1B2", count: 9)
    let key = "sk-" + String(repeating: "Z9y8", count: 6)
    let cloud = "AKIA" + String(repeating: "Q", count: 16)
    let chat = "xoxb-" + String(repeating: "1", count: 12)
    let pem = "-----BEGIN " + "RSA PRIVATE KEY-----"
    let output = reply(item(title: "Token", body: "use \(token)"), item(title: "Chave", body: key),
                       item(title: cloud, body: "na AWS"), item(title: "Slack", body: chat),
                       item(title: "PEM", body: pem), item(title: "Limpa", body: "o token fica no cofre"))

    let candidates = try #require(MemoryExtraction.candidates(from: output))

    #expect(candidates.map(\.title) == ["Limpa"])
}

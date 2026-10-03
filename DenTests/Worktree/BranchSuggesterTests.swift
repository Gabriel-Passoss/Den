import Testing
import Foundation
import HarnessCore
@testable import Den

private nonisolated func outcome(_ text: String, status: Int32 = 0) -> ProcessOutcome {
    ProcessOutcome(status: status, stdout: Data(text.utf8), stderr: Data())
}

private func asking() -> FakeHarness {
    var harness = FakeHarness()
    harness.oneShotArguments = ["-p", "--model", "haiku"]
    return harness
}

@Test func theInstructionAsksForAConventionalNameForTheRequest() {
    let instruction = BranchSuggester.instruction(for: "ajusta o login do paciente")
    #expect(instruction.contains("ajusta o login do paciente"))
    #expect(instruction.contains("Conventional"))
    #expect(instruction.contains("em inglês"))
    for type in BranchNamer.types { #expect(instruction.contains(type)) }
}

@Test func aConventionalAnswerGivesTheTypeAndTheStem() async {
    var suggester = BranchSuggester()
    suggester.run = { _, _, _ in outcome("fix/patient-login\n") }
    #expect(await suggester.suggest(for: "ajusta o login do paciente", harness: asking())
            == BranchSuggestion(type: "fix", stem: "patient-login"))
}

@Test func quotesBackticksAndExtraLinesAreDropped() {
    #expect(BranchSuggester.suggestion(from: "`Refactor/Session-Store`\nexplicação que não pedi", message: "x")
            == BranchSuggestion(type: "refactor", stem: "session-store"))
    #expect(BranchSuggester.suggestion(from: "\"docs: guia de instalação\"", message: "x")
            == BranchSuggestion(type: "docs", stem: "guia-de-instalacao"))
}

@Test func anAnswerWithoutAKnownTypeTakesTheTypeFromTheMessage() {
    #expect(BranchSuggester.suggestion(from: "login-redirect", message: "corrige o login")
            == BranchSuggestion(type: "fix", stem: "login-redirect"))
    #expect(BranchSuggester.suggestion(from: "wip/login-redirect", message: "exporta relatórios")
            == BranchSuggestion(type: "feat", stem: "wip-login-redirect"))
}

@Test func theTicketOfTheMessageLeadsTheStem() {
    #expect(BranchSuggester.suggestion(from: "fix/login", message: "NS-7 ajusta o login")
            == BranchSuggestion(type: "fix", stem: "NS-7-login"))
    #expect(BranchSuggester.suggestion(from: "fix/NS-7-login", message: "NS-7 ajusta o login")
            == BranchSuggestion(type: "fix", stem: "NS-7-login"))
}

@Test func anEmptyOrRamblingAnswerIsNoSuggestion() {
    #expect(BranchSuggester.suggestion(from: "   ", message: "x") == nil)
    #expect(BranchSuggester.suggestion(from: "fix/", message: "x") == nil)
    #expect(BranchSuggester.suggestion(from: String(repeating: "palavra ", count: 40), message: "x") == nil)
}

@Test func aHarnessThatCannotAskGivesNoSuggestion() async {
    var suggester = BranchSuggester()
    suggester.run = { _, _, _ in
        Issue.record("nothing should run")
        return outcome("ignored")
    }
    #expect(await suggester.suggest(for: "ajusta o login", harness: FakeHarness()) == nil)
}

@Test func aFailedOrSilentRunGivesNoSuggestion() async {
    var failing = BranchSuggester()
    failing.run = { _, _, _ in outcome("fix/login", status: 1) }
    var silent = BranchSuggester()
    silent.run = { _, _, _ in nil }
    #expect(await failing.suggest(for: "ajusta o login", harness: asking()) == nil)
    #expect(await silent.suggest(for: "ajusta o login", harness: asking()) == nil)
}

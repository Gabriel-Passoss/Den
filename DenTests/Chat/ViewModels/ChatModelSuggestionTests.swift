import Testing
import Foundation
import HarnessCore
@testable import Den

@Test func theTitleComesFromTheHarnessQuickPrompt() async throws {
    let runner = FakeCommandRunner()
    await runner.answer(with: "Backup dos projetos")
    try await withLiveChat(configure: { $0.quickPrompt = ["one-shot"] }, runner: runner) { live in
        await live.chat.send(text: "crie um script de backup")

        await settle { live.chat.title == "Backup dos projetos" }
        let call = try #require(await runner.calls.first)
        #expect(call.executable == "/fake/bin/harness")
        #expect(call.arguments.first == "one-shot")
        #expect(call.arguments.last?.contains("crie um script de backup") == true)
    }
}

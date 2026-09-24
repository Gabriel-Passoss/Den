import Testing
import Foundation
import HarnessCore
@testable import DevSpace

private let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)

@Test func matchesRequireALiveSlashPrompt() {
    let controller = SlashController()
    #expect(controller.matches(prompt: "no slash", catalog: catalog).isEmpty)
    #expect(controller.matches(prompt: "/rev", catalog: catalog).map(\.id) == ["review"])
    #expect(controller.matches(prompt: "/", catalog: .empty).isEmpty)

    controller.dismissed = true
    #expect(controller.matches(prompt: "/rev", catalog: catalog).isEmpty)
}

@Test func runEntersAGroupWithoutSending() {
    let chat = inertChat()
    let controller = SlashController()
    controller.selection = 3

    let group = SlashCommand(id: "group:skills", title: "Habilidades", detail: "",
                             kind: .group(.skills, count: 2))
    #expect(controller.run(group, in: chat) == false)
    #expect(controller.group == .skills)
    #expect(controller.selection == 0)
    #expect(chat.prompt == "/")
}

@Test func runSendsARealCommandAndDismisses() {
    let chat = inertChat()
    let controller = SlashController()

    let skill = SlashCommand(id: "review", title: "review", detail: "Skill", kind: .skill)
    #expect(controller.run(skill, in: chat) == true)
    #expect(chat.prompt.isEmpty)
    #expect(controller.dismissed)
}

@Test func runIgnoresServerRows() {
    let chat = inertChat()
    chat.prompt = "/bro"
    let controller = SlashController()

    let server = SlashCommand(id: "mcp:broken", title: "broken", detail: "",
                              kind: .mcpServer(status: .needsAuth))
    #expect(controller.run(server, in: chat) == false)
    #expect(chat.prompt == "/bro")
    #expect(!controller.dismissed)
}

@Test func leaveGroupResetsThePrompt() {
    let chat = inertChat()
    let controller = SlashController()
    controller.group = .skills
    controller.selection = 2

    controller.leaveGroup(in: chat)
    #expect(controller.group == nil)
    #expect(controller.selection == 0)
    #expect(chat.prompt == "/")
}

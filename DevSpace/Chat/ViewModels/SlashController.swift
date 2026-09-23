import Foundation
import Observation
import HarnessCore

@Observable final class SlashController {
    var selection = 0
    var dismissed = false
    var group: SlashGroup?

    func matches(prompt: String, catalog: CommandCatalog) -> [SlashCommand] {
        guard !dismissed, !catalog.isEmpty,
              let query = SlashCatalog.query(in: prompt) else { return [] }
        return SlashCatalog.matches(query, in: catalog, group: group)
    }

    @discardableResult
    func run(_ command: SlashCommand, in chat: ChatModel) -> Bool {
        if let group = command.group {
            self.group = group
            selection = 0
            chat.prompt = "/"
            return false
        }
        guard let text = command.command else { return false }
        chat.prompt = ""
        group = nil
        dismissed = true
        Task { await chat.run(command: text) }
        return true
    }

    func leaveGroup(in chat: ChatModel) {
        group = nil
        selection = 0
        chat.prompt = "/"
    }
}

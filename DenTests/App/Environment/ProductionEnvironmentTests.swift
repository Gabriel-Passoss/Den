import Testing
import Foundation
@testable import Den

@Test func productionUsesTheRealPlaces() {
    let environment = ProductionEnvironment()

    #expect(environment.defaults == .standard)
    #expect(environment.databaseFile
            == URL.applicationSupportDirectory.appending(path: "Den/den.sqlite"))
    #expect(environment.attachmentsRoot == ChatModel.standardAttachmentsRoot)
    #expect(environment.runConfigurationsFile
            == URL.applicationSupportDirectory.appending(path: "Den/run-configurations.json"))
    #expect(environment.worktreesRoot.path == NSHomeDirectory() + "/.den/worktrees")
    #expect(environment.worktreesFile
            == URL.applicationSupportDirectory.appending(path: "Den/task-worktrees.json"))
    #expect(environment.workingDirectory.path == NSHomeDirectory())
    #expect(environment.registry.ids == HarnessRegistry.standard.ids)
    #expect(environment.ghOverride == nil)
}

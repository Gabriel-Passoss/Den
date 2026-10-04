import Testing
import Foundation
@testable import Den

@Test func devKeepsItsFilesApartFromProduction() {
    let environment = DevEnvironment()
    let support = URL.applicationSupportDirectory.appending(path: "Den Dev")

    #expect(environment.databaseFile == support.appending(path: "den.sqlite"))
    #expect(environment.attachmentsRoot == support.appending(path: "attachments"))
    #expect(environment.runConfigurationsFile
            == support.appending(path: "run-configurations.json"))
    #expect(environment.worktreesRoot.path == NSHomeDirectory() + "/.den-dev/worktrees")
    #expect(environment.worktreesFile == support.appending(path: "task-worktrees.json"))
    #expect(environment.workingDirectory.path == NSHomeDirectory())
    #expect(environment.registry.ids == HarnessRegistry.standard.ids)
}

@Test func devPreferencesNeverReachProduction() {
    let environment = DevEnvironment()
    let key = "DenTests.devIsolation." + UUID().uuidString
    defer { environment.defaults.removeObject(forKey: key) }

    environment.defaults.set("dev", forKey: key)

    #expect(environment.defaults != .standard)
    #expect(environment.defaults.string(forKey: key) == "dev")
    #expect(UserDefaults.standard.object(forKey: key) == nil)
}

@Test func devHandsOutOneDefaultsObject() {
    let environment = DevEnvironment()
    let first = environment.defaults

    #expect(environment.defaults === first)
}

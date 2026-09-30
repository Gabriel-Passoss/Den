import Foundation
@testable import Den

struct TestEnvironment: AppEnvironment {
    let sessionsRoot: URL
    let attachmentsRoot: URL
    let runConfigurationsFile: URL
    let defaults: UserDefaults
    let registry: HarnessRegistry
    let workingDirectory: URL

    init(root: URL, defaults: UserDefaults, registry: HarnessRegistry = .standard) {
        sessionsRoot = root.appending(path: "sessions")
        attachmentsRoot = root.appending(path: "attachments")
        runConfigurationsFile = root.appending(path: "run-configurations.json")
        workingDirectory = root.appending(path: "project")
        self.defaults = defaults
        self.registry = registry
    }
}

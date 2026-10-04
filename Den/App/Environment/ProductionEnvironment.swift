import Foundation

struct ProductionEnvironment: AppEnvironment {
    private let support = URL.applicationSupportDirectory.appending(path: "Den")

    var databaseFile: URL { support.appending(path: "den.sqlite") }
    var attachmentsRoot: URL { support.appending(path: "attachments") }
    var runConfigurationsFile: URL { support.appending(path: "run-configurations.json") }
    var worktreesRoot: URL { URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".den/worktrees") }
    var defaults: UserDefaults { .standard }
    var registry: HarnessRegistry { .standard }
    var workingDirectory: URL { URL(fileURLWithPath: NSHomeDirectory()) }
}

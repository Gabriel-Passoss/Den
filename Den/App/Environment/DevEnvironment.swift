import Foundation

struct DevEnvironment: AppEnvironment {
    static let defaultsSuite = "Den.Dev"

    private let support = URL.applicationSupportDirectory.appending(path: "Den Dev")

    let defaults = UserDefaults(suiteName: DevEnvironment.defaultsSuite)!

    var databaseFile: URL { support.appending(path: "den.sqlite") }
    var attachmentsRoot: URL { support.appending(path: "attachments") }
    var runConfigurationsFile: URL { support.appending(path: "run-configurations.json") }
    var worktreesRoot: URL { URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".den-dev/worktrees") }
    var registry: HarnessRegistry { .standard }
    var workingDirectory: URL { URL(fileURLWithPath: NSHomeDirectory()) }
}

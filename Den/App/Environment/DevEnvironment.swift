import Foundation

struct DevEnvironment: AppEnvironment {
    static let defaultsSuite = "Den.Dev"

    private let support = URL.applicationSupportDirectory.appending(path: "Den Dev")

    let defaults = UserDefaults(suiteName: DevEnvironment.defaultsSuite)!

    var sessionsRoot: URL { support.appending(path: "sessions") }
    var attachmentsRoot: URL { support.appending(path: "attachments") }
    var runConfigurationsFile: URL { support.appending(path: "run-configurations.json") }
    var registry: HarnessRegistry { .standard }
    var workingDirectory: URL { URL(fileURLWithPath: NSHomeDirectory()) }
}

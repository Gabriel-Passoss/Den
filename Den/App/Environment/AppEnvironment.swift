import Foundation

protocol AppEnvironment {
    var databaseFile: URL { get }
    var memoryRoot: URL { get }
    var attachmentsRoot: URL { get }
    var runConfigurationsFile: URL { get }
    var worktreesRoot: URL { get }
    var ghOverride: String? { get }
    var defaults: UserDefaults { get }
    var registry: HarnessRegistry { get }
    var workingDirectory: URL { get }
}

extension AppEnvironment {
    var ghOverride: String? { nil }
}

protocol RootedEnvironment: AppEnvironment {
    var root: URL { get }
}

extension RootedEnvironment {
    var databaseFile: URL { root.appending(path: "den.sqlite") }
    var memoryRoot: URL { root.appending(path: "memory") }
    var attachmentsRoot: URL { root.appending(path: "attachments") }
    var runConfigurationsFile: URL { root.appending(path: "run-configurations.json") }
    var worktreesRoot: URL { root.appending(path: "worktrees") }
    var workingDirectory: URL { root.appending(path: "project") }
}

#if DEBUG
let isDebugBuild = true
#else
let isDebugBuild = false
#endif

func resolveEnvironment(_ variables: [String: String],
                        debugBuild: Bool = isDebugBuild) -> any AppEnvironment {
    guard debugBuild else { return ProductionEnvironment() }
    return UITestEnvironment(variables) ?? DevEnvironment()
}

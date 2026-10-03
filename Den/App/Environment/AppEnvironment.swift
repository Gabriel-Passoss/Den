import Foundation

protocol AppEnvironment {
    var sessionsRoot: URL { get }
    var attachmentsRoot: URL { get }
    var runConfigurationsFile: URL { get }
    var worktreesRoot: URL { get }
    var worktreesFile: URL { get }
    var ghOverride: String? { get }
    var defaults: UserDefaults { get }
    var registry: HarnessRegistry { get }
    var workingDirectory: URL { get }
}

extension AppEnvironment {
    var ghOverride: String? { nil }
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

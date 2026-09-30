import Foundation

protocol AppEnvironment {
    var sessionsRoot: URL { get }
    var attachmentsRoot: URL { get }
    var runConfigurationsFile: URL { get }
    var defaults: UserDefaults { get }
    var registry: HarnessRegistry { get }
    var workingDirectory: URL { get }
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

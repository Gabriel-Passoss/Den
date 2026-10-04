import Foundation
import HarnessCore

struct UITestEnvironment: RootedEnvironment {
    static let rootKey = "DEN_UI_TEST_ROOT"
    static let cliKeyPrefix = "DEN_CLI_"
    static let projectSetupKey = "DEN_PROJECT_SETUP"
    static let defaultsSuite = "Den.UITests"
    static let ghKey = "DEN_GH"

    let root: URL
    let defaults: UserDefaults
    let registry: HarnessRegistry
    let ghOverride: String?

    init?(_ variables: [String: String]) {
        guard let rootPath = variables[Self.rootKey] else { return nil }
        root = URL(fileURLWithPath: rootPath)
        ghOverride = variables[Self.ghKey]

        let pinned = Dictionary(uniqueKeysWithValues: HarnessRegistry.standard.ids.compactMap { id in
            variables[Self.cliKeyPrefix + id.rawValue].map { (id, $0) }
        })
        registry = HarnessRegistry.standard.pinning(pinned)

        defaults = UserDefaults(suiteName: Self.defaultsSuite) ?? .standard
        if !FileManager.default.fileExists(atPath: databaseFile.path) {
            defaults.removePersistentDomain(forName: Self.defaultsSuite)
        }

        let isNewProject = !FileManager.default.fileExists(atPath: workingDirectory.path)
        try? FileManager.default.createDirectory(at: workingDirectory,
                                                 withIntermediateDirectories: true)
        if isNewProject, let setup = variables[Self.projectSetupKey] {
            Self.run(setup, in: workingDirectory)
        }
    }

    private static func run(_ script: String, in directory: URL) {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", script]
        shell.currentDirectoryURL = directory
        let finished = DispatchSemaphore(value: 0)
        shell.terminationHandler = { _ in finished.signal() }
        guard (try? shell.run()) != nil else { return }
        finished.wait()
    }
}

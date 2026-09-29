import Foundation
import HarnessCore

/// Where the app keeps its state and which CLIs it runs. A normal launch gets
/// the real places. In Debug builds, UI tests set `DEN_UI_TEST_ROOT` so a
/// run touches none of the user's sessions, attachments or preferences, and
/// under that root `DEN_CLI_<harness id>` runs a fake CLI in place of the
/// real one. This file is the app's only test hook.
struct LaunchEnvironment {
    static let rootKey = "DEN_UI_TEST_ROOT"
    static let cliKeyPrefix = "DEN_CLI_"
    static let projectSetupKey = "DEN_PROJECT_SETUP"
    static let testDefaultsSuite = "Den.UITests"

    let sessionsRoot: URL
    let attachmentsRoot: URL
    let runConfigurationsFile: URL
    let defaults: UserDefaults
    let registry: HarnessRegistry
    let workingDirectory: URL

    static let current = LaunchEnvironment(ProcessInfo.processInfo.environment)

    init(_ environment: [String: String]) {
        #if DEBUG
        let rootPath = environment[Self.rootKey]
        #else
        let rootPath: String? = nil
        #endif

        guard let rootPath else {
            let support = URL.applicationSupportDirectory.appending(path: "Den")
            sessionsRoot = support.appending(path: "sessions")
            attachmentsRoot = ChatModel.standardAttachmentsRoot
            runConfigurationsFile = support.appending(path: "run-configurations.json")
            defaults = .standard
            registry = .standard
            workingDirectory = URL(fileURLWithPath: NSHomeDirectory())
            return
        }
        let root = URL(fileURLWithPath: rootPath)
        sessionsRoot = root.appending(path: "sessions")
        attachmentsRoot = root.appending(path: "attachments")
        runConfigurationsFile = root.appending(path: "run-configurations.json")
        workingDirectory = root.appending(path: "project")

        let pinned = Dictionary(uniqueKeysWithValues: HarnessRegistry.standard.ids.compactMap { id in
            environment[Self.cliKeyPrefix + id.rawValue].map { (id, $0) }
        })
        registry = HarnessRegistry.standard.pinning(pinned)

        // One suite for every UI test, emptied when a test starts from a fresh
        // root and kept when it relaunches the app on the same one.
        defaults = UserDefaults(suiteName: Self.testDefaultsSuite) ?? .standard
        if !FileManager.default.fileExists(atPath: sessionsRoot.path) {
            defaults.removePersistentDomain(forName: Self.testDefaultsSuite)
        }

        let isNewProject = !FileManager.default.fileExists(atPath: workingDirectory.path)
        try? FileManager.default.createDirectory(at: workingDirectory,
                                                 withIntermediateDirectories: true)
        if isNewProject, let setup = environment[Self.projectSetupKey] {
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

/// A harness whose CLI sits at a fixed path instead of being looked up on the
/// machine. Launch arguments, protocol and knobs still come from the real
/// harness it wraps, so only the executable changes.
nonisolated struct PinnedHarness: Harness {
    let base: any Harness
    let executable: String

    var id: HarnessID { base.id }
    var displayName: String { base.displayName }

    func discover() async throws -> HarnessInstallation {
        HarnessInstallation(executable: executable, version: "0.0.0")
    }

    func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities {
        base.capabilities(for: installation)
    }

    func knobs(for installation: HarnessInstallation,
               workingDirectory: URL) -> [HarnessKnob] {
        base.knobs(for: installation, workingDirectory: workingDirectory)
    }

    func makeSession(installation: HarnessInstallation, workingDirectory: URL,
                     settings: [String: String]) -> any HarnessSession {
        base.makeSession(installation: installation, workingDirectory: workingDirectory,
                         settings: settings)
    }

    func titleArguments(for instruction: String) -> [String]? {
        base.titleArguments(for: instruction)
    }
}

extension HarnessRegistry {
    /// The same harnesses, with the listed ones pointed at a fixed executable.
    func pinning(_ executables: [HarnessID: String]) -> HarnessRegistry {
        HarnessRegistry(harnesses: harnesses.map { harness in
            guard let path = executables[harness.id] else { return harness }
            return PinnedHarness(base: harness, executable: path)
        })
    }
}

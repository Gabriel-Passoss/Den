import Testing
import Foundation
import HarnessCore
@testable import Den

@Test func aNormalLaunchUsesTheRealPlaces() {
    let environment = LaunchEnvironment([:])

    #expect(environment.defaults == .standard)
    #expect(environment.sessionsRoot
            == URL.applicationSupportDirectory.appending(path: "Den/sessions"))
    #expect(environment.attachmentsRoot == ChatModel.standardAttachmentsRoot)
    #expect(environment.workingDirectory.path == NSHomeDirectory())
    #expect(environment.runConfigurationsFile
            == URL.applicationSupportDirectory.appending(path: "Den/run-configurations.json"))
    #expect(environment.registry.ids == HarnessRegistry.standard.ids)
}

@Test func aUITestRootKeepsEveryFileAndPreferenceInsideIt() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let environment = LaunchEnvironment([LaunchEnvironment.rootKey: root.path])

    #expect(environment.sessionsRoot.path.hasPrefix(root.path))
    #expect(environment.attachmentsRoot.path.hasPrefix(root.path))
    #expect(environment.workingDirectory.path.hasPrefix(root.path))
    #expect(environment.runConfigurationsFile.path.hasPrefix(root.path))
    #expect(FileManager.default.fileExists(atPath: environment.workingDirectory.path))
    #expect(environment.defaults != .standard)
}

@Test func aProjectSetupFillsTheProjectOnlyTheFirstTime() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let launch = [
        LaunchEnvironment.rootKey: root.path,
        LaunchEnvironment.projectSetupKey: "mkdir -p backend && echo run >> backend/pom.xml",
    ]

    let environment = LaunchEnvironment(launch)
    _ = LaunchEnvironment(launch)

    let seeded = environment.workingDirectory.appending(path: "backend/pom.xml")
    #expect(try String(contentsOf: seeded, encoding: .utf8) == "run\n")
}

@MainActor
@Test func aProjectSetupWaitsWithoutServingTheMainRunLoop() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    final class Probe { var served = false }
    let probe = Probe()

    RunLoop.main.perform(inModes: [.default]) { probe.served = true }
    _ = LaunchEnvironment([
        LaunchEnvironment.rootKey: root.path,
        LaunchEnvironment.projectSetupKey: "sleep 0.2",
    ])

    #expect(!probe.served)
}

@Test func aProjectSetupIsIgnoredOutsideAUITestRoot() throws {
    let marker = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: marker) }

    _ = LaunchEnvironment([LaunchEnvironment.projectSetupKey: "touch '\(marker.path)'"])

    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func aPinnedCLIReplacesDiscoveryAndNothingElse() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let environment = LaunchEnvironment([
        LaunchEnvironment.rootKey: root.path,
        LaunchEnvironment.cliKeyPrefix + claudeCodeID.rawValue: "/fake/claude",
    ])

    let claude = try #require(environment.registry.harness(for: claudeCodeID))
    #expect(try await claude.discover().executable == "/fake/claude")
    #expect(claude.displayName == "Claude Code")
    #expect(claude.titleArguments(for: "x") != nil)
    #expect(environment.registry.harness(for: openCodeID) is PinnedHarness == false)
}

@Test func aPinnedCLIIsIgnoredOutsideAUITestRoot() async throws {
    let environment = LaunchEnvironment([
        LaunchEnvironment.cliKeyPrefix + claudeCodeID.rawValue: "/fake/claude",
    ])

    #expect(environment.registry.harness(for: claudeCodeID) is PinnedHarness == false)
}

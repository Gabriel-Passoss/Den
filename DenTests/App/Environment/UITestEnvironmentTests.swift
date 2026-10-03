import Testing
import Foundation
import HarnessCore
@testable import Den

private func scratchRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "DenTests-" + UUID().uuidString)
}

@Test func withoutARootThereIsNoUITestEnvironment() {
    #expect(UITestEnvironment([:]) == nil)
    #expect(UITestEnvironment([
        UITestEnvironment.cliKeyPrefix + claudeCodeID.rawValue: "/fake/claude",
        UITestEnvironment.projectSetupKey: "true",
    ]) == nil)
}

@Test func aUITestRootKeepsEveryFileAndPreferenceInsideIt() throws {
    let root = scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let environment = try #require(UITestEnvironment([UITestEnvironment.rootKey: root.path]))

    #expect(environment.sessionsRoot.path.hasPrefix(root.path))
    #expect(environment.attachmentsRoot.path.hasPrefix(root.path))
    #expect(environment.workingDirectory.path.hasPrefix(root.path))
    #expect(environment.runConfigurationsFile.path.hasPrefix(root.path))
    #expect(environment.worktreesRoot.path.hasPrefix(root.path))
    #expect(environment.worktreesFile.path.hasPrefix(root.path))
    #expect(FileManager.default.fileExists(atPath: environment.workingDirectory.path))
    #expect(environment.defaults != .standard)
}

@MainActor
@Test func aRelaunchOnTheSameRootKeepsThePreferences() throws {
    let root = scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let launch = [UITestEnvironment.rootKey: root.path]
    let first = try #require(UITestEnvironment(launch))
    defer { first.defaults.removeObject(forKey: "DenTests.relaunch") }
    try FileManager.default.createDirectory(at: first.sessionsRoot,
                                            withIntermediateDirectories: true)
    first.defaults.set("kept", forKey: "DenTests.relaunch")

    let relaunched = try #require(UITestEnvironment(launch))

    #expect(relaunched.defaults.string(forKey: "DenTests.relaunch") == "kept")
}

@MainActor
@Test func aFreshRootStartsWithNoPreferences() throws {
    let used = scratchRoot()
    let fresh = scratchRoot()
    defer {
        try? FileManager.default.removeItem(at: used)
        try? FileManager.default.removeItem(at: fresh)
    }
    let first = try #require(UITestEnvironment([UITestEnvironment.rootKey: used.path]))
    first.defaults.set("stale", forKey: "DenTests.freshRoot")

    let next = try #require(UITestEnvironment([UITestEnvironment.rootKey: fresh.path]))

    #expect(next.defaults.object(forKey: "DenTests.freshRoot") == nil)
}

@Test func aProjectSetupFillsTheProjectOnlyTheFirstTime() throws {
    let root = scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let launch = [
        UITestEnvironment.rootKey: root.path,
        UITestEnvironment.projectSetupKey: "mkdir -p backend && echo run >> backend/pom.xml",
    ]

    let environment = try #require(UITestEnvironment(launch))
    _ = UITestEnvironment(launch)

    let seeded = environment.workingDirectory.appending(path: "backend/pom.xml")
    #expect(try String(contentsOf: seeded, encoding: .utf8) == "run\n")
}

@MainActor
@Test func aProjectSetupWaitsWithoutServingTheMainRunLoop() throws {
    let root = scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    final class Probe { var served = false }
    let probe = Probe()

    RunLoop.main.perform(inModes: [.default]) { probe.served = true }
    _ = UITestEnvironment([
        UITestEnvironment.rootKey: root.path,
        UITestEnvironment.projectSetupKey: "sleep 0.2",
    ])

    #expect(!probe.served)
}

@Test func aPinnedCLIReplacesDiscoveryAndNothingElse() async throws {
    let root = scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let environment = try #require(UITestEnvironment([
        UITestEnvironment.rootKey: root.path,
        UITestEnvironment.cliKeyPrefix + claudeCodeID.rawValue: "/fake/claude",
    ]))

    let claude = try #require(environment.registry.harness(for: claudeCodeID))
    #expect(try await claude.discover().executable == "/fake/claude")
    #expect(claude.displayName == "Claude Code")
    #expect(claude.titleArguments(for: "x") != nil)
    #expect(environment.registry.harness(for: openCodeID) is PinnedHarness == false)
}

@Test func aPinnedGhIsHandedOverOnlyInUITests() throws {
    let root = scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let pinned = try #require(UITestEnvironment([
        UITestEnvironment.rootKey: root.path,
        UITestEnvironment.ghKey: "/fake/gh",
    ]))
    let plain = try #require(UITestEnvironment([UITestEnvironment.rootKey: root.path]))

    #expect(pinned.ghOverride == "/fake/gh")
    #expect(plain.ghOverride == nil)
}

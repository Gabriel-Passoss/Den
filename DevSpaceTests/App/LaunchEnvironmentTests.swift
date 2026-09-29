import Testing
import Foundation
import HarnessCore
@testable import DevSpace

@Test func aNormalLaunchUsesTheRealPlaces() {
    let environment = LaunchEnvironment([:])

    #expect(environment.defaults == .standard)
    #expect(environment.sessionsRoot
            == URL.applicationSupportDirectory.appending(path: "DevSpace/sessions"))
    #expect(environment.attachmentsRoot == ChatModel.standardAttachmentsRoot)
    #expect(environment.workingDirectory.path == NSHomeDirectory())
    #expect(environment.registry.ids == HarnessRegistry.standard.ids)
}

@Test func aUITestRootKeepsEveryFileAndPreferenceInsideIt() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let environment = LaunchEnvironment([LaunchEnvironment.rootKey: root.path])

    #expect(environment.sessionsRoot.path.hasPrefix(root.path))
    #expect(environment.attachmentsRoot.path.hasPrefix(root.path))
    #expect(environment.workingDirectory.path.hasPrefix(root.path))
    #expect(FileManager.default.fileExists(atPath: environment.workingDirectory.path))
    #expect(environment.defaults != .standard)
}

@Test func aPinnedCLIReplacesDiscoveryAndNothingElse() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
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

import Testing
import Foundation
import HarnessCore
@testable import Den

private func scratchURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "DenTests-" + UUID().uuidString)
}

@Test func aReleaseBuildIsProductionWhateverTheVariablesSay() {
    let root = scratchURL()
    let marker = scratchURL()
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: marker)
    }

    let environment = resolveEnvironment([
        UITestEnvironment.rootKey: root.path,
        UITestEnvironment.cliKeyPrefix + claudeCodeID.rawValue: "/fake/claude",
        UITestEnvironment.projectSetupKey: "touch '\(marker.path)'",
    ], debugBuild: false)

    #expect(environment is ProductionEnvironment)
    #expect(!FileManager.default.fileExists(atPath: root.path))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func aDebugBuildWithoutARootIsDev() {
    #expect(resolveEnvironment([:], debugBuild: true) is DevEnvironment)
}

@Test func aDebugBuildWithoutARootIgnoresTheOtherTestVariables() {
    let marker = scratchURL()
    defer { try? FileManager.default.removeItem(at: marker) }

    let environment = resolveEnvironment([
        UITestEnvironment.cliKeyPrefix + claudeCodeID.rawValue: "/fake/claude",
        UITestEnvironment.projectSetupKey: "touch '\(marker.path)'",
    ], debugBuild: true)

    #expect(environment is DevEnvironment)
    #expect(environment.registry.harness(for: claudeCodeID) is PinnedHarness == false)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func aDebugBuildWithARootIsTheUITestEnvironment() {
    let root = scratchURL()
    defer { try? FileManager.default.removeItem(at: root) }

    let environment = resolveEnvironment([UITestEnvironment.rootKey: root.path],
                                         debugBuild: true)

    #expect(environment is UITestEnvironment)
    #expect(environment.databaseFile.path.hasPrefix(root.path))
}

@Test func theDefaultFollowsTheBuildTheTestsRunIn() {
    #expect(isDebugBuild)
    #expect(resolveEnvironment([:]) is DevEnvironment)
}

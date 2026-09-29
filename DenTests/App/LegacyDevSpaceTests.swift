import Testing
import Foundation
@testable import Den

private func isLink(_ url: URL) -> Bool {
    (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
}

private func scratchSupport() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
}

@Test func theOldFolderMovesToTheNewNameAndLeavesALinkBehind() throws {
    let root = scratchSupport()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appending(path: "DevSpace")
    let support = root.appending(path: "Den")
    try FileManager.default.createDirectory(at: legacy.appending(path: "sessions"),
                                            withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: legacy.appending(path: "run-configurations.json"))

    LegacyDevSpace.moveFolder(from: legacy, to: support)

    #expect(FileManager.default.fileExists(atPath: support.appending(path: "sessions").path))
    #expect(FileManager.default.fileExists(atPath: support.appending(path: "run-configurations.json").path))
    #expect(isLink(legacy))
    #expect(FileManager.default.fileExists(atPath: legacy.appending(path: "run-configurations.json").path))
}

@Test func anExistingNewFolderIsLeftAlone() throws {
    let root = scratchSupport()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appending(path: "DevSpace")
    let support = root.appending(path: "Den")
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

    LegacyDevSpace.moveFolder(from: legacy, to: support)

    #expect(!isLink(legacy))
}

@Test func aLeftoverLinkIsNeverMovedAgain() throws {
    let root = scratchSupport()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appending(path: "DevSpace")
    let support = root.appending(path: "Den")
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    LegacyDevSpace.moveFolder(from: legacy, to: support)
    try FileManager.default.removeItem(at: support)

    LegacyDevSpace.moveFolder(from: legacy, to: support)

    #expect(!FileManager.default.fileExists(atPath: support.path))
}

@Test func missingOldDataIsANoOp() {
    let root = scratchSupport()
    defer { try? FileManager.default.removeItem(at: root) }

    LegacyDevSpace.moveFolder(from: root.appending(path: "DevSpace"), to: root.appending(path: "Den"))

    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Den").path))
}

@Test func oldPreferencesComeAcrossUnderTheNewPrefix() {
    withTemporaryDefaults { defaults in
        LegacyDevSpace.importPreferences([
            "DevSpace.defaultHarness": "opencode",
            "DevSpace.sessionOrder": ["a", "b"],
            "NSWindow Frame Main": "0 0 100 100",
        ], into: defaults)

        #expect(defaults.string(forKey: "Den.defaultHarness") == "opencode")
        #expect(defaults.stringArray(forKey: "Den.sessionOrder") == ["a", "b"])
        #expect(defaults.object(forKey: "NSWindow Frame Main") == nil)
    }
}

@Test func newPreferencesWinOverOldOnes() {
    withTemporaryDefaults { defaults in
        defaults.set("claude-code", forKey: "Den.defaultHarness")

        LegacyDevSpace.importPreferences(["DevSpace.defaultHarness": "opencode"], into: defaults)

        #expect(defaults.string(forKey: "Den.defaultHarness") == "claude-code")
    }
}

@Test func oldPreferencesComeAcrossOnlyOnce() {
    withTemporaryDefaults { defaults in
        LegacyDevSpace.importPreferences(["DevSpace.gitInspector": true], into: defaults)
        defaults.removeObject(forKey: "Den.gitInspector")

        LegacyDevSpace.importPreferences(["DevSpace.gitInspector": true], into: defaults)

        #expect(defaults.object(forKey: "Den.gitInspector") == nil)
    }
}

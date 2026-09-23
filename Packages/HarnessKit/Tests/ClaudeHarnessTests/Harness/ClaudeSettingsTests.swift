import Testing
import Foundation
@testable import ClaudeHarness

private func makeTree() throws -> (root: URL, project: URL, home: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("claude-settings-\(UUID().uuidString)")
    let project = root.appendingPathComponent("project")
    let home = root.appendingPathComponent("home")
    for directory in [project.appendingPathComponent(".claude"),
                      home.appendingPathComponent(".claude")] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return (root, project, home)
}

private func write(_ json: String, to base: URL, file: String) throws {
    try Data(json.utf8).write(to: base.appendingPathComponent(".claude/\(file)"))
}

@Test func theUserSettingsProvideTheEffort() throws {
    let (root, project, home) = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(#"{"effortLevel":"xhigh"}"#, to: home, file: "settings.json")
    #expect(ClaudeSettings.effortLevel(forWorkingDirectory: project, home: home) == .xhigh)
}

@Test func theProjectSettingsWinOverTheUserOnes() throws {
    let (root, project, home) = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(#"{"effortLevel":"xhigh"}"#, to: home, file: "settings.json")
    try write(#"{"effortLevel":"low"}"#, to: project, file: "settings.json")
    try write(#"{"effortLevel":"medium"}"#, to: project, file: "settings.local.json")
    #expect(ClaudeSettings.effortLevel(forWorkingDirectory: project, home: home) == .medium)
}

@Test func aFileWithoutTheKeyFallsThrough() throws {
    let (root, project, home) = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(#"{"model":"opus"}"#, to: project, file: "settings.json")
    try write(#"{"effortLevel":"high"}"#, to: home, file: "settings.json")
    #expect(ClaudeSettings.effortLevel(forWorkingDirectory: project, home: home) == .high)
}

@Test func anUnknownLevelOrNoFilesYieldNil() throws {
    let (root, project, home) = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(ClaudeSettings.effortLevel(forWorkingDirectory: project, home: home) == nil)
    try write(#"{"effortLevel":"turbo"}"#, to: home, file: "settings.json")
    #expect(ClaudeSettings.effortLevel(forWorkingDirectory: project, home: home) == nil)
}

@Test func theUserSettingsProvideThePermissionMode() throws {
    let (root, project, home) = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(#"{"permissions":{"defaultMode":"auto"}}"#, to: home, file: "settings.json")
    #expect(ClaudeSettings.permissionMode(forWorkingDirectory: project, home: home) == .auto)
}

@Test func theSpellingDefaultMeansManual() throws {
    let (root, project, home) = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(#"{"permissions":{"defaultMode":"default"}}"#, to: home, file: "settings.json")
    #expect(ClaudeSettings.permissionMode(forWorkingDirectory: project, home: home) == .manual)
}

@Test func theProjectModeWinsAndAbsenceYieldsNil() throws {
    let (root, project, home) = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(ClaudeSettings.permissionMode(forWorkingDirectory: project, home: home) == nil)
    try write(#"{"permissions":{"defaultMode":"auto"}}"#, to: home, file: "settings.json")
    try write(#"{"permissions":{"defaultMode":"plan"}}"#, to: project, file: "settings.json")
    #expect(ClaudeSettings.permissionMode(forWorkingDirectory: project, home: home) == .plan)
}

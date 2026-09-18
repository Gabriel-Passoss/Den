import Testing
import Foundation
import HarnessCore

@Test func theGenericTypesLiveInHarnessCore() async throws {
    let transport = ProcessTransport()
    let stream = try await transport.start(ProcessTransport.Launch(
        executable: "/bin/sh",
        arguments: ["-c", #"printf '{"a":1}\n'"#],
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
    ))
    var lines: [String] = []
    for try await line in stream { lines.append(String(decoding: line, as: UTF8.self)) }
    #expect(lines == [#"{"a":1}"#])

    let install = HarnessInstallation(executable: "/usr/bin/true", version: "1.0.0")
    #expect(install.executable == "/usr/bin/true")

    let failure = CommandFailure(exitCode: 3, stderr: "boom")
    #expect(failure.exitCode == 3)
}

@Test func theNeutralPermissionTypesLiveInHarnessCore() throws {
    let request = PermissionRequest(
        id: "r-1",
        toolName: "Bash",
        input: .object(["command": .string("ls")]),
        suggestions: [PermissionSuggestion(type: "setMode", mode: "acceptEdits")]
    )
    #expect(request.toolName == "Bash")
    #expect(request.suggestions.first?.mode == "acceptEdits")

    let decision = PermissionDecision.allow(updatedInput: nil)
    #expect(decision == .allow(updatedInput: nil))

    #expect(PermissionMode.allCases.count == 6)
    #expect(PermissionMode(rawValue: "acceptEdits") == .acceptEdits)

    #expect(PermissionMode(rawValue: "acceptEdit") == nil)
}

@Test func theEphemeralStreamTypesLiveInHarnessCore() {
    let output = MappedOutput(
        events: [.sessionInitialized(model: "m", harnessSessionID: "s"),
                 .notice(subtype: "status", text: "pensando")],
        entries: []
    )
    #expect(output.events.count == 2)
    #expect(output.entries.isEmpty)
}

@Test func harnessCoreNeverNamesASpecificHarness() throws {
    let core = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/HarnessCore")

    let files = try #require(
        FileManager.default.enumerator(at: core, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    )
    #expect(!files.isEmpty, "a varredura não achou fonte nenhuma — o caminho mudou")

    let forbidden = ["claude", "codex", "opencode"]
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8).lowercased()
        for name in forbidden where text.contains(name) {
            Issue.record("\(file.lastPathComponent) menciona \"\(name)\" — spec §7.1")
        }
    }
}

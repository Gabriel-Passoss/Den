import Testing
import Foundation
@testable import Den

@Test func aFinishedProcessHandsBackItsOutputAndStatus() async throws {
    let outcome = try #require(await TimedProcess.run(
        "/bin/sh", ["-c", "echo out; echo first >&2; echo last >&2; exit 3"],
        timeout: .seconds(10)))
    #expect(outcome.status == 3)
    #expect(!outcome.succeeded)
    #expect(outcome.output == "out")
    #expect(outcome.errorLine == "last")
}

@Test func theDirectoryAndEnvironmentReachTheProcess() async throws {
    let parent = try makeTree(["Área de trabalho"])
    defer { try? FileManager.default.removeItem(at: parent) }
    let folder = parent.appending(path: "Área de trabalho")

    let outcome = try #require(await TimedProcess.run(
        "/bin/sh", ["-c", "pwd; echo \"$DEN_PROBE\""], in: folder,
        environment: ["DEN_PROBE": "a=b c", "PATH": "/usr/bin:/bin"],
        timeout: .seconds(10)))

    let lines = outcome.output.split(separator: "\n").map(String.init)
    #expect(URL(fileURLWithPath: lines.first ?? "").resolvingSymlinksInPath().path
            == folder.resolvingSymlinksInPath().path)
    #expect(lines.last == "a=b c")
}

@Test func aHungProcessIsKilledAtTheDeadline() async {
    #expect(await TimedProcess.run("/bin/sleep", ["30"], timeout: .milliseconds(200)) == nil)
}

@Test func aMissingExecutableGivesNil() async {
    #expect(await TimedProcess.run("/nonexistent/den-tool", [], timeout: .seconds(1)) == nil)
}

@Test func plentyOfOutputOnBothStreamsNeverStalls() async throws {
    let outcome = try #require(await TimedProcess.run(
        "/bin/sh",
        ["-c", "i=0; while [ $i -lt 20000 ]; do echo line$i; echo err$i >&2; i=$((i+1)); done"],
        timeout: .seconds(30)))
    #expect(outcome.succeeded)
    #expect(outcome.output.hasSuffix("line19999"))
    #expect(outcome.errorLine == "err19999")
}

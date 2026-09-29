import Testing
import Foundation
@testable import Den

private func output(_ text: String) -> Data { Data(text.utf8) }

nonisolated private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@Test func parseReadsOnlyWhatFollowsTheMarker() {
    let data = output("Welcome to fish\n__DEN_ENV__\nPATH=/x:/y\u{0}HOME=/h\u{0}")
    #expect(ShellEnvironment.parse(data) == ["PATH": "/x:/y", "HOME": "/h"])
}

@Test func parseKeepsEverythingAfterTheFirstEquals() {
    let data = output("__DEN_ENV__\nDATABASE_URL=postgres://u:p@h/db?a=b\u{0}")
    #expect(ShellEnvironment.parse(data)?["DATABASE_URL"] == "postgres://u:p@h/db?a=b")
}

@Test func parseDropsShellBookkeepingVariables() {
    let data = output("__DEN_ENV__\nPATH=/x\u{0}PWD=/home\u{0}OLDPWD=/\u{0}SHLVL=2\u{0}_=/usr/bin/env\u{0}")
    #expect(ShellEnvironment.parse(data) == ["PATH": "/x"])
}

@Test func parseWithoutTheMarkerIsNil() {
    #expect(ShellEnvironment.parse(output("PATH=/x\u{0}")) == nil)
}

@Test func fallbackPrependsHomebrewPathsOnce() {
    let result = ShellEnvironment.fallback(from: ["PATH": "/usr/bin:/usr/local/bin", "PWD": "/"])
    #expect(result["PATH"] == "/opt/homebrew/bin:/usr/bin:/usr/local/bin")
    #expect(result["PWD"] == nil)
}

@Test func resolveUsesTheProbeOnceAndCaches() async {
    let calls = CallCounter()
    let environment = ShellEnvironment(shell: "/bin/zsh", base: [:]) { shell, arguments, _ in
        calls.bump()
        #expect(shell == "/bin/zsh")
        #expect(arguments == ["-l", "-i", "-c", "echo __DEN_ENV__; /usr/bin/env -0"])
        return Data("__DEN_ENV__\nPATH=/nvm/bin\u{0}".utf8)
    }
    let first = await environment.resolve()
    let second = await environment.resolve()
    #expect(first == ShellEnvironment.Resolved(shell: "/bin/zsh", variables: ["PATH": "/nvm/bin"], warning: nil))
    #expect(second == first)
    #expect(calls.count == 1)
}

@Test func aFailedProbeFallsBackWithAWarning() async {
    let environment = ShellEnvironment(shell: "/bin/zsh", base: ["PATH": "/usr/bin"]) { _, _, _ in nil }
    let resolved = await environment.resolve()
    #expect(resolved.warning == ShellEnvironment.fallbackWarning)
    #expect(resolved.variables["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin")
}

@Test func anOutputWithoutPathAlsoFallsBack() async {
    let environment = ShellEnvironment(shell: "/bin/zsh", base: [:]) { _, _, _ in
        Data("__DEN_ENV__\nHOME=/h\u{0}".utf8)
    }
    #expect(await environment.resolve().warning == ShellEnvironment.fallbackWarning)
}

@Test func theLiveProbeReadsARealShell() async throws {
    let data = try #require(await ShellProbe.run(
        shell: "/bin/sh", arguments: ["-c", "echo __DEN_ENV__; /usr/bin/env -0"],
        timeout: .seconds(10)))
    #expect(ShellEnvironment.parse(data)?["PATH"] != nil)
}

@Test func theLiveProbeGivesUpOnAHungShell() async {
    let data = await ShellProbe.run(shell: "/bin/sh", arguments: ["-c", "sleep 30"],
                                    timeout: .milliseconds(300))
    #expect(data == nil)
}

private func resolved(_ variables: [String: String]) -> ShellEnvironment.Resolved {
    ShellEnvironment.Resolved(shell: "/bin/zsh", variables: variables, warning: nil)
}

@Test func theProcessEnvironmentAddsTerminalVariablesAndLetsTheConfigurationWin() {
    let environment = resolved(["PATH": "/bin", "TERM": "dumb"]).processEnvironment(
        overrides: [EnvVar(key: "PORT", value: "3000"), EnvVar(key: " ", value: "x"),
                    EnvVar(key: "A=B", value: "y")],
        locale: "pt_BR.UTF-8")
    #expect(environment["PATH"] == "/bin")
    #expect(environment["TERM"] == "xterm-256color")
    #expect(environment["COLORTERM"] == "truecolor")
    #expect(environment["PORT"] == "3000")
    #expect(environment[" "] == nil)
    #expect(environment["A=B"] == nil)
}

@Test func aMissingLocaleDefaultsToUTF8() {
    func lang(_ variables: [String: String]) -> String? {
        resolved(variables).processEnvironment(overrides: [], locale: "pt_BR.UTF-8")["LANG"]
    }
    #expect(lang(["PATH": "/bin"]) == "pt_BR.UTF-8")
    #expect(lang(["LANG": "C.UTF-8"]) == "C.UTF-8")
    #expect(lang(["LC_ALL": "en_US.UTF-8"]) == nil)
    #expect(lang(["LC_CTYPE": "UTF-8"]) == nil)
    #expect(resolved([:]).processEnvironment(overrides: [EnvVar(key: "LANG", value: "C")],
                                             locale: "pt_BR.UTF-8")["LANG"] == "C")
}

@Test func theDefaultLocaleFollowsTheSystemWhenItExists() {
    let installed: Set<String> = ["pt_BR.UTF-8", "en_US.UTF-8"]
    #expect(ShellEnvironment.defaultLocale(identifier: "pt_BR", isInstalled: installed.contains) == "pt_BR.UTF-8")
    #expect(ShellEnvironment.defaultLocale(identifier: "pt_BR@rg=uszzzz", isInstalled: installed.contains) == "pt_BR.UTF-8")
    #expect(ShellEnvironment.defaultLocale(identifier: "en_BR", isInstalled: installed.contains) == "en_US.UTF-8")
}

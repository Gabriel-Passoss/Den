import Testing
import Foundation
@testable import Den

private func install(_ body: String, at file: URL) throws {
    try ("#!/bin/sh\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
}

private func fakeGh(_ body: String) throws -> URL {
    let file = try makeTree(["bin"]).appending(path: "bin/gh")
    try install(body, at: file)
    return file
}

private func cleanUp(_ gh: URL) {
    try? FileManager.default.removeItem(at: gh.deletingLastPathComponent().deletingLastPathComponent())
}

private let healthy = """
    case "$1" in
      --version) echo "gh version 9.9.9 (2026-01-01)"; echo "https://github.com/cli/cli/releases/tag/v9.9.9" ;;
      auth) exit 0 ;;
      pr) echo '[]' ;;
      probe-env) echo "$GH_PROMPT_DISABLED|$GH_NO_UPDATE_NOTIFIER|$NO_COLOR" ;;
      probe-pwd) pwd ;;
    esac
    """

private func shell(path: String) -> ShellEnvironment {
    ShellEnvironment(shell: "/bin/sh", base: [:]) { _, _, _ in
        Data("\(ShellEnvironment.marker)\nPATH=\(path)\u{0}HOME=/tmp\u{0}".utf8)
    }
}

private let plainPath = "/usr/bin:/bin"

private let loggedOut = healthy.replacingOccurrences(of: "auth) exit 0", with: "auth) exit 1")

private func configured(_ gh: URL) -> GitHubCLI {
    GitHubCLI(configured: gh.path, shell: shell(path: plainPath), candidates: [])
}

private func isReady(_ cli: GitHubCLI, at gh: URL) async -> Bool {
    await cli.status(hosts: ["github.com"]).state == .ready(path: gh.path, version: "9.9.9")
}

@Test func withoutAnyGhTheStateIsMissing() async {
    let cli = GitHubCLI(shell: shell(path: plainPath), candidates: [])
    #expect(await cli.status(hosts: ["github.com"]) == GitHubCLIStatus(state: .missing, hosts: []))
}

@Test func aConfiguredGhIsFoundAndItsVersionRead() async throws {
    let gh = try fakeGh(healthy)
    defer { cleanUp(gh) }
    let cli = GitHubCLI(configured: gh.path, shell: shell(path: plainPath), candidates: [])

    let status = await cli.status(hosts: ["github.com"])

    #expect(status == GitHubCLIStatus(state: .ready(path: gh.path, version: "9.9.9"), hosts: ["github.com"]))
}

@Test func ghOnTheShellPathIsFound() async throws {
    let gh = try fakeGh(healthy)
    defer { cleanUp(gh) }
    let cli = GitHubCLI(shell: shell(path: gh.deletingLastPathComponent().path + ":" + plainPath),
                        candidates: [])
    #expect(await cli.status(hosts: []).state == .ready(path: gh.path, version: "9.9.9"))
}

@Test func theOverrideWinsOverTheConfiguredPath() async throws {
    let pinned = try fakeGh(healthy)
    let configured = try fakeGh(healthy)
    defer { cleanUp(pinned); cleanUp(configured) }
    let cli = GitHubCLI(override: pinned.path, configured: configured.path,
                        shell: shell(path: plainPath), candidates: [])
    #expect(await cli.status(hosts: []).state == .ready(path: pinned.path, version: "9.9.9"))
}

@Test func aMissingLoginIsReportedForGitHub() async throws {
    let gh = try fakeGh(loggedOut)
    defer { cleanUp(gh) }
    #expect(await configured(gh).status(hosts: ["github.com"]).state == .notLoggedIn(host: "github.com"))
}

@Test func anEnterpriseHostWithoutLoginIsLeftOut() async throws {
    let gh = try fakeGh(healthy.replacingOccurrences(of: "auth) exit 0", with: "auth) [ \"$4\" = github.com ]"))
    defer { cleanUp(gh) }
    let cli = GitHubCLI(configured: gh.path, shell: shell(path: plainPath), candidates: [])

    let status = await cli.status(hosts: ["github.com", "git.acme.com"])

    #expect(status.state == .ready(path: gh.path, version: "9.9.9"))
    #expect(status.hosts == ["github.com"])
}

@Test func commandsRunQuietlyInTheirFolder() async throws {
    let gh = try fakeGh(healthy)
    defer { cleanUp(gh) }
    let folder = gh.deletingLastPathComponent()
    let cli = GitHubCLI(configured: gh.path, shell: shell(path: plainPath), candidates: [])

    #expect(await cli.run(["probe-env"], in: nil)?.output == "1|1|1")
    let pwd = await cli.run(["probe-pwd"], in: folder)?.output ?? ""
    #expect(URL(fileURLWithPath: pwd).resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path)
}

@Test func anEmptyListIsNoPullRequest() async throws {
    let gh = try fakeGh(healthy)
    defer { cleanUp(gh) }
    let cli = GitHubCLI(configured: gh.path, shell: shell(path: plainPath), candidates: [])
    #expect(await cli.pullRequest(branch: "den/x", in: gh.deletingLastPathComponent()) == .found(nil))
}

@Test func aRateLimitIsRecognized() async throws {
    let gh = try fakeGh(healthy.replacingOccurrences(
        of: "pr) echo '[]' ;;",
        with: "pr) echo 'GraphQL: API rate limit exceeded for user ID 1.' >&2; exit 1 ;;"))
    defer { cleanUp(gh) }
    let cli = GitHubCLI(configured: gh.path, shell: shell(path: plainPath), candidates: [])
    #expect(await cli.pullRequest(branch: "den/x", in: gh.deletingLastPathComponent())
            == .failed(rateLimited: true))
}

@Test func aHungGhIsGivenUpOn() async throws {
    let gh = try fakeGh(healthy.replacingOccurrences(of: "pr) echo '[]' ;;", with: "pr) sleep 30 ;;"))
    defer { cleanUp(gh) }
    let cli = GitHubCLI(configured: gh.path, shell: shell(path: plainPath), candidates: [],
                        timeout: .milliseconds(500))
    #expect(await cli.pullRequest(branch: "den/x", in: gh.deletingLastPathComponent())
            == .failed(rateLimited: false))
}

@Test func configuringANewPathForgetsTheOldSearch() async throws {
    let gh = try fakeGh(healthy)
    defer { cleanUp(gh) }
    let cli = GitHubCLI(shell: shell(path: plainPath), candidates: [])
    #expect(await cli.status(hosts: []).state == .missing)

    await cli.configure(path: gh.path)

    #expect(await cli.status(hosts: []).state == .ready(path: gh.path, version: "9.9.9"))
}

@Test func aChosenFileIsCheckedForAVersion() async throws {
    let gh = try fakeGh(healthy)
    defer { cleanUp(gh) }
    #expect(await GitHubCLI.version(at: gh.path) == "9.9.9")
    #expect(await GitHubCLI.version(at: "/nonexistent/gh") == nil)
}

@Test func aRefreshFindsAGhInstalledAfterTheFirstSearch() async throws {
    let folder = try makeTree(["bin"])
    defer { try? FileManager.default.removeItem(at: folder) }
    let gh = folder.appending(path: "bin/gh")
    let cli = GitHubCLI(shell: shell(path: plainPath), candidates: [gh.path])
    #expect(await cli.status(hosts: ["github.com"]).state == .missing)

    try install(healthy, at: gh)
    await cli.refresh()

    #expect(await isReady(cli, at: gh))
}

@Test func aRefreshNoticesALoginMadeMeanwhile() async throws {
    let gh = try fakeGh(loggedOut)
    defer { cleanUp(gh) }
    let cli = configured(gh)
    #expect(await cli.status(hosts: ["github.com"]).state == .notLoggedIn(host: "github.com"))

    try install(healthy, at: gh)
    await cli.refresh()

    #expect(await isReady(cli, at: gh))
}

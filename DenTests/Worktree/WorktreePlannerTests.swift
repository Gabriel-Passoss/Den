import Testing
import Foundation
@testable import Den

private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

private let root = url("/wt")
private let api = RepoCandidate(toplevel: url("/code/api"), main: url("/code/api"))

@Test func aSingleRepoGetsItsWorktreeUnderTheRepoName() {
    let plan = WorktreePlanner.plan(layout: .single(api), sessionDirectory: url("/code/api"),
                                    chosen: [], branch: "den/NS-1-fix", prefix: "den/",
                                    root: root, entries: [])

    #expect(plan.entries == [.init(name: "api", main: url("/code/api"), worktree: url("/wt/api/NS-1-fix"))])
    #expect(plan.sessionDirectory.path == "/wt/api/NS-1-fix")
    #expect(plan.mirrorRoot == nil)
    #expect(plan.links.isEmpty)
    #expect(plan.branch == "den/NS-1-fix")
}

@Test func aSubfolderSessionStaysInTheSameSubfolder() {
    let plan = WorktreePlanner.plan(layout: .single(api), sessionDirectory: url("/code/api/apps/web"),
                                    chosen: [], branch: "den/NS-1-fix", prefix: "den/",
                                    root: root, entries: [])
    #expect(plan.sessionDirectory.path == "/wt/api/NS-1-fix/apps/web")
}

@Test func aSessionInsideADenWorktreeGroupsUnderTheMainRepo() {
    let inside = RepoCandidate(toplevel: url("/wt/api/old"), main: url("/code/api"))
    let plan = WorktreePlanner.plan(layout: .single(inside), sessionDirectory: url("/wt/api/old/apps"),
                                    chosen: [], branch: "den/NS-2-new", prefix: "den/",
                                    root: root, entries: [])
    #expect(plan.entries.map(\.worktree.path) == ["/wt/api/NS-2-new"])
    #expect(plan.entries.map(\.main.path) == ["/code/api"])
    #expect(plan.sessionDirectory.path == "/wt/api/NS-2-new/apps")
}

private let scalemed = url("/code/scalemed")
private let backend = RepoCandidate(toplevel: url("/code/scalemed/backend"), main: url("/code/scalemed/backend"))
private let frontend = RepoCandidate(toplevel: url("/code/scalemed/apps/frontend"),
                                     main: url("/code/scalemed/apps/frontend"))
private let infra = RepoCandidate(toplevel: url("/code/scalemed/infra"), main: url("/code/scalemed/infra"))
private let several = WorktreeLayout.multiple(folder: scalemed, repos: [backend, frontend, infra])

@Test func severalReposAreMirroredWithTheirRelativePaths() {
    let plan = WorktreePlanner.plan(layout: several, sessionDirectory: scalemed,
                                    chosen: [backend.id, frontend.id], branch: "den/NS-1-fix",
                                    prefix: "den/", root: root, entries: [])

    #expect(plan.mirrorRoot?.path == "/wt/scalemed/NS-1-fix")
    #expect(plan.sessionDirectory.path == "/wt/scalemed/NS-1-fix")
    #expect(plan.entries.map(\.worktree.path)
            == ["/wt/scalemed/NS-1-fix/backend", "/wt/scalemed/NS-1-fix/apps/frontend"])
    #expect(plan.entries.map(\.name) == ["backend", "frontend"])
}

@Test func looseEntriesBecomeLinksButNeverReposOrTheirParents() {
    let entries = ["CLAUDE.md", ".mcp.json", "docs", "backend", "apps", "infra",
                   "node_modules", ".DS_Store"].map { scalemed.appending(path: $0) }

    let plan = WorktreePlanner.plan(layout: several, sessionDirectory: scalemed,
                                    chosen: [backend.id, frontend.id], branch: "den/NS-1-fix",
                                    prefix: "den/", root: root, entries: entries)

    #expect(plan.links.map(\.destination.lastPathComponent) == ["CLAUDE.md", ".mcp.json", "docs"])
    #expect(plan.links.first?.source.path == "/code/scalemed/CLAUDE.md")
    #expect(plan.links.first?.destination.path == "/wt/scalemed/NS-1-fix/CLAUDE.md")
}

@Test func unchosenReposGetNoWorktree() {
    let plan = WorktreePlanner.plan(layout: several, sessionDirectory: scalemed,
                                    chosen: [backend.id], branch: "den/x", prefix: "den/",
                                    root: root, entries: [])
    #expect(plan.entries.map(\.name) == ["backend"])
}

@Test func aMirrorInsideTheRootKeepsItsGroup() {
    #expect(WorktreePlanner.group(for: url("/wt/scalemed/old"), root: root) == "scalemed")
    #expect(WorktreePlanner.group(for: scalemed, root: root) == "scalemed")
}

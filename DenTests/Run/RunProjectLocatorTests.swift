import Testing
import Foundation
@testable import Den

@Test func toplevelClimbsToTheEnclosingRepo() throws {
    let root = try makeTree([".git", "api/src"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(GitRepository.toplevel(containing: root.appending(path: "api/src"))?.path == root.path)
}

@Test func toplevelIsNilOutsideAnyRepo() throws {
    let root = try makeTree(["plain/folder"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(GitRepository.toplevel(containing: root.appending(path: "plain/folder")) == nil)
}

@Test func aKnownAncestorWinsOverTheRepoRoot() throws {
    let root = try makeTree([".git", "api/src"])
    defer { try? FileManager.default.removeItem(at: root) }
    let api = root.appending(path: "api")
    let found = RunProjectLocator.root(for: root.appending(path: "api/src"),
                                       knownRoots: [ProjectRoot(api)])
    #expect(found.path == api.path)
}

@Test func theDirectoryItselfCanBeTheKnownRoot() throws {
    let root = try makeTree([".git", "api"])
    defer { try? FileManager.default.removeItem(at: root) }
    let api = root.appending(path: "api")
    #expect(RunProjectLocator.root(for: api, knownRoots: [ProjectRoot(api)]).path == api.path)
}

@Test func withoutKnownRootsTheRepoRootIsTheProject() throws {
    let root = try makeTree([".git", "api/src"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(RunProjectLocator.root(for: root.appending(path: "api/src"), knownRoots: []).path == root.path)
}

@Test func withoutRepoOrKnownRootsTheDirectoryIsTheProject() throws {
    let root = try makeTree(["loose/folder"])
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appending(path: "loose/folder")
    #expect(RunProjectLocator.root(for: folder, knownRoots: []).path == folder.path)
}

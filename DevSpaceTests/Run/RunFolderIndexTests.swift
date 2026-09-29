import Testing
import Foundation
@testable import DevSpace

@Test func foldersListOnlyDirectoriesInTreeOrder() throws {
    let root = try makeTree(["apps/web", "apps/api", "docs"], files: ["README.md", "apps/notes.txt"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(RunFolderIndex.folders(under: root).map(\.path) == ["apps", "apps/api", "apps/web", "docs"])
}

@Test func hiddenAndHeavyFoldersAreSkipped() throws {
    let root = try makeTree(["node_modules/pkg", ".git/objects", ".cache", "dist", "src"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(RunFolderIndex.folders(under: root).map(\.path) == ["src"])
}

@Test func depthIsLimited() throws {
    let root = try makeTree(["a/b/c/d/e"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(RunFolderIndex.folders(under: root, maxDepth: 3).map(\.path) == ["a", "a/b", "a/b/c"])
}

@Test func theListStopsAtTheLimit() throws {
    let root = try makeTree(["a", "b", "c", "d"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(RunFolderIndex.folders(under: root, limit: 2).map(\.path) == ["a", "b"])
}

@Test func projectFoldersCarryTheirMarker() throws {
    let root = try makeTree(["docs"], files: ["apps/web/package.json", "apps/api/Makefile",
                                              "apps/api/package.json", "tools/Makefile"])
    defer { try? FileManager.default.removeItem(at: root) }
    let markers = Dictionary(uniqueKeysWithValues: RunFolderIndex.folders(under: root).map { ($0.path, $0.marker) })
    #expect(markers["apps"] == .some(nil))
    #expect(markers["apps/web"] == "package.json")
    #expect(markers["apps/api"] == "package.json")
    #expect(markers["tools"] == "Makefile")
    #expect(markers["docs"] == .some(nil))
    #expect(RunFolderIndex.marker(in: root.appending(path: "apps/web")) == "package.json")
}

@Test func filterMatchesAnyPartOfThePath() {
    let folders = ["apps", "apps/api", "apps/web", "web-legacy"].map { RunFolder(path: $0, marker: nil) }
    #expect(RunFolderIndex.filter(folders, query: "WEB").map(\.path) == ["apps/web", "web-legacy"])
    #expect(RunFolderIndex.filter(folders, query: "  ").map(\.path) == ["apps", "apps/api", "apps/web", "web-legacy"])
}

@Test func aSelectionOutsideTheListIsPinned() {
    let folders = [RunFolder(path: "apps", marker: nil)]
    #expect(RunFolderIndex.pinnedSelection("", in: folders) == nil)
    #expect(RunFolderIndex.pinnedSelection("apps", in: folders) == nil)
    #expect(RunFolderIndex.pinnedSelection("/elsewhere", in: folders) == "/elsewhere")
    #expect(RunFolderIndex.pinnedSelection("apps/deleted", in: folders) == "apps/deleted")
}

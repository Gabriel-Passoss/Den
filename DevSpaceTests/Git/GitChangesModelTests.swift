import Testing
import Foundation
@testable import DevSpace

private func names(_ roots: [URL], under base: URL) -> [String] {
    roots.map { String($0.path.dropFirst(base.standardizedFileURL.path.count)
        .drop(while: { $0 == "/" })) }
}

@Test func discoverFindsTheRepoAtTheDirectoryItself() throws {
    let root = try makeTree([".git"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(names(GitChangesModel.discoverRepoRoots(under: root), under: root) == [""])
}

@Test func discoverReachesChildrenAndGrandchildren() throws {
    let root = try makeTree([
        "child/.git",
        "middle/grandchild/.git",
        "middle/other/great-grandchild/.git",
    ])
    defer { try? FileManager.default.removeItem(at: root) }

    let found = names(GitChangesModel.discoverRepoRoots(under: root), under: root)
    #expect(found.contains("child"))
    #expect(found.contains("middle/grandchild"))
    #expect(!found.contains("middle/other/great-grandchild"))
}

@Test func discoverSkipsVendoredFolders() throws {
    let root = try makeTree(["node_modules/package/.git", "Pods/lib/.git", "tracked/.git"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(names(GitChangesModel.discoverRepoRoots(under: root), under: root) == ["tracked"])
}

@Test func discoverClimbsToTheEnclosingRepo() throws {
    let root = try makeTree([".git", "package/inner"])
    defer { try? FileManager.default.removeItem(at: root) }

    let inner = root.appending(path: "package/inner")
    let found = GitChangesModel.discoverRepoRoots(under: inner)
    #expect(found.map(\.path) == [root.standardizedFileURL.path])
}

@Test func discoverReturnsNothingOutsideAnyRepo() throws {
    let root = try makeTree(["empty/with/nothing"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(GitChangesModel.discoverRepoRoots(under: root).isEmpty)
}

@Test func untrackedLinesNumberEveryLineAsAdded() throws {
    let root = try makeTree([])
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "new.txt")
    try "one\ntwo\nthree".write(to: file, atomically: true, encoding: .utf8)

    let lines = GitChangesModel.untrackedLines(of: file)
    #expect(lines.map(\.text) == ["one", "two", "three"])
    #expect(lines.allSatisfy { $0.kind == .added })
    #expect(lines.map(\.number) == [1, 2, 3])
}

@Test func untrackedLinesStopAtTheCap() throws {
    let root = try makeTree([])
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "long.txt")
    try (0..<50).map(String.init).joined(separator: "\n")
        .write(to: file, atomically: true, encoding: .utf8)

    #expect(GitChangesModel.untrackedLines(of: file, cap: 10).count == 10)
}

@Test func untrackedLinesFlagBinaryFiles() throws {
    let root = try makeTree([])
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "bin.dat")
    try Data([0x41, 0x00, 0x42]).write(to: file)

    #expect(GitChangesModel.untrackedLines(of: file).map(\.text) == ["Arquivo binário"])
}

@Test func untrackedLinesOfAMissingFileAreEmpty() {
    let missing = FileManager.default.temporaryDirectory
        .appending(path: "missing-" + UUID().uuidString)
    #expect(GitChangesModel.untrackedLines(of: missing).isEmpty)
}

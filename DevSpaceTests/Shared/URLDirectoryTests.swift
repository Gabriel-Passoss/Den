import Testing
import Foundation
@testable import DevSpace

@Test func isExistingDirectoryTellsFoldersFromFilesAndGaps() throws {
    let root = try makeTree(["folder"], files: ["file.txt"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(root.appending(path: "folder").isExistingDirectory)
    #expect(!root.appending(path: "file.txt").isExistingDirectory)
    #expect(!root.appending(path: "missing").isExistingDirectory)
}

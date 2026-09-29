import Testing
import Foundation
@testable import Den

@Test func statusEntriesParsePorcelainStates() {
    let output = " M Sources/App.swift\u{0}A  Added.swift\u{0}?? New.swift\u{0}"
        + " D Deleted.swift\u{0}UU Conflict.swift\u{0}!! Ignored.swift\u{0}"
    let entries = GitParsing.statusEntries(fromPorcelain: output)
    #expect(entries == [
        GitStatusEntry(path: "Sources/App.swift", state: .modified),
        GitStatusEntry(path: "Added.swift", state: .added),
        GitStatusEntry(path: "New.swift", state: .untracked),
        GitStatusEntry(path: "Deleted.swift", state: .deleted),
        GitStatusEntry(path: "Conflict.swift", state: .conflicted),
    ])
}

@Test func statusEntriesSkipTheRenameOrigin() {
    let output = "R  New.swift\u{0}Old.swift\u{0} M Other.swift\u{0}"
    let entries = GitParsing.statusEntries(fromPorcelain: output)
    #expect(entries == [
        GitStatusEntry(path: "New.swift", state: .renamed),
        GitStatusEntry(path: "Other.swift", state: .modified),
    ])
}

@Test func statusEntriesFlagDirectories() {
    let entries = GitParsing.statusEntries(fromPorcelain: "?? NewFolder/\u{0}")
    #expect(entries.count == 1)
    #expect(entries.first?.isDirectory == true)
}

@Test func fileDiffsNumberLinesFromTheHunkHeader() throws {
    let output = """
    diff --git a/Sources/App.swift b/Sources/App.swift
    index 1111111..2222222 100644
    --- a/Sources/App.swift
    +++ b/Sources/App.swift
    @@ -1,3 +2,4 @@ func main()
     context
    -removed
    +new one
    +new two
    """
    let diffs = GitParsing.fileDiffs(fromUnified: output)
    let lines = try #require(diffs["Sources/App.swift"])
    #expect(lines.map(\.kind) == [.hunk, .context, .removed, .added, .added])
    #expect(lines.map(\.number) == [nil, 2, 2, 3, 4])
    #expect(lines.map(\.text) == ["func main()", "context", "removed", "new one", "new two"])
}

@Test func fileDiffsSplitFilesAndMarkBinaries() throws {
    let output = """
    diff --git a/one.txt b/one.txt
    @@ -1 +1 @@
    -old
    +new
    diff --git a/img.png b/img.png
    Binary files a/img.png and b/img.png differ
    """
    let diffs = GitParsing.fileDiffs(fromUnified: output)
    #expect(diffs.count == 2)
    let text = try #require(diffs["one.txt"])
    #expect(text.map(\.kind) == [.hunk, .removed, .added])
    let binary = try #require(diffs["img.png"])
    #expect(binary.map(\.text) == ["Arquivo binário"])
}

@Test func fingerprintIsStableAndOrderSensitive() {
    #expect(GitParsing.fingerprint(of: ["a", "b"]) == GitParsing.fingerprint(of: ["a", "b"]))
    #expect(GitParsing.fingerprint(of: ["a", "b"]) != GitParsing.fingerprint(of: ["ab"]))
    #expect(GitParsing.fingerprint(of: ["a", "b"]) != GitParsing.fingerprint(of: ["b", "a"]))
}

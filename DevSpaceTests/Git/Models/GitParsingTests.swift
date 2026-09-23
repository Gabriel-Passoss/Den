import Testing
import Foundation
@testable import DevSpace

@Test func statusEntriesParsePorcelainStates() {
    let output = " M Sources/App.swift\u{0}A  Adicionado.swift\u{0}?? Novo.swift\u{0}"
        + " D Apagado.swift\u{0}UU Conflito.swift\u{0}!! Ignorado.swift\u{0}"
    let entries = GitParsing.statusEntries(fromPorcelain: output)
    #expect(entries == [
        GitStatusEntry(path: "Sources/App.swift", state: .modified),
        GitStatusEntry(path: "Adicionado.swift", state: .added),
        GitStatusEntry(path: "Novo.swift", state: .untracked),
        GitStatusEntry(path: "Apagado.swift", state: .deleted),
        GitStatusEntry(path: "Conflito.swift", state: .conflicted),
    ])
}

@Test func statusEntriesSkipTheRenameOrigin() {
    let output = "R  Novo.swift\u{0}Velho.swift\u{0} M Outro.swift\u{0}"
    let entries = GitParsing.statusEntries(fromPorcelain: output)
    #expect(entries == [
        GitStatusEntry(path: "Novo.swift", state: .renamed),
        GitStatusEntry(path: "Outro.swift", state: .modified),
    ])
}

@Test func statusEntriesFlagDirectories() {
    let entries = GitParsing.statusEntries(fromPorcelain: "?? Nova/\u{0}")
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
     contexto
    -removida
    +nova um
    +nova dois
    """
    let diffs = GitParsing.fileDiffs(fromUnified: output)
    let lines = try #require(diffs["Sources/App.swift"])
    #expect(lines.map(\.kind) == [.hunk, .context, .removed, .added, .added])
    #expect(lines.map(\.number) == [nil, 2, 2, 3, 4])
    #expect(lines.map(\.text) == ["func main()", "contexto", "removida", "nova um", "nova dois"])
}

@Test func fileDiffsSplitFilesAndMarkBinaries() throws {
    let output = """
    diff --git a/um.txt b/um.txt
    @@ -1 +1 @@
    -velho
    +novo
    diff --git a/img.png b/img.png
    Binary files a/img.png and b/img.png differ
    """
    let diffs = GitParsing.fileDiffs(fromUnified: output)
    #expect(diffs.count == 2)
    let text = try #require(diffs["um.txt"])
    #expect(text.map(\.kind) == [.hunk, .removed, .added])
    let binary = try #require(diffs["img.png"])
    #expect(binary.map(\.text) == ["Arquivo binário"])
}

@Test func fingerprintIsStableAndOrderSensitive() {
    #expect(GitParsing.fingerprint(of: ["a", "b"]) == GitParsing.fingerprint(of: ["a", "b"]))
    #expect(GitParsing.fingerprint(of: ["a", "b"]) != GitParsing.fingerprint(of: ["ab"]))
    #expect(GitParsing.fingerprint(of: ["a", "b"]) != GitParsing.fingerprint(of: ["b", "a"]))
}

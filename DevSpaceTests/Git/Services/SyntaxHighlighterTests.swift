import Testing
import Foundation
@testable import DevSpace

@Test func languageFromHintCoversTheCommonAliases() {
    #expect(SyntaxHighlighter.language(forHint: "swift") == .swift)
    #expect(SyntaxHighlighter.language(forHint: "TypeScript") == .cFamily)
    #expect(SyntaxHighlighter.language(forHint: "py") == .python)
    #expect(SyntaxHighlighter.language(forHint: "bash") == .shell)
    #expect(SyntaxHighlighter.language(forHint: "json") == .json)
    #expect(SyntaxHighlighter.language(forHint: "markdown") == .plain)
}

@Test func languageFromHintFallsBackForTheUnknown() {
    #expect(SyntaxHighlighter.language(forHint: nil) == .plain)
    #expect(SyntaxHighlighter.language(forHint: "") == .plain)
    #expect(SyntaxHighlighter.language(forHint: "brainfuck") == .generic)
}

@Test func languageFromFileReadsTheExtension() {
    #expect(SyntaxHighlighter.language(forFile: "App.swift") == .swift)
    #expect(SyntaxHighlighter.language(forFile: "Sources/index.tsx") == .cFamily)
    #expect(SyntaxHighlighter.language(forFile: "deploy.sh") == .shell)
    #expect(SyntaxHighlighter.language(forFile: "package.json") == .json)
    #expect(SyntaxHighlighter.language(forFile: "LEIAME.md") == .plain)
    #expect(SyntaxHighlighter.language(forFile: "Makefile") == .plain)
    #expect(SyntaxHighlighter.language(forFile: "script.lua") == .generic)
}

@Test func highlightPreservesTheLineText() {
    let source = #"let x = "hi" // comment"#
    let highlighted = SyntaxHighlighter.highlight(source, language: .swift)
    #expect(String(highlighted.characters) == source)
}

@Test func highlightOfAnEmptyLineStaysEmpty() {
    #expect(String(SyntaxHighlighter.highlight("", language: .swift).characters) == "")
}

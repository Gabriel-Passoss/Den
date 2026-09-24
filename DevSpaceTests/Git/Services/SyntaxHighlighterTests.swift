import Testing
import Foundation
import SwiftUI
@testable import DevSpace

private func shade(_ color: Color?) -> String {
    guard let color else { return "plain" }
    if color == .pink { return "keyword" }
    if color == .orange { return "string" }
    if color == .purple { return "number" }
    if color == .teal { return "type" }
    if color == .secondary { return "comment" }
    if color == .indigo { return "attribute" }
    return "unknown"
}

private func shades(_ text: AttributedString) -> [String] {
    text.runs.map { shade($0.foregroundColor) + ":" + String(text[$0.range].characters) }
}

private func tokens(_ line: String, _ language: SyntaxHighlighter.Language) -> [String] {
    shades(SyntaxHighlighter.highlight(line, language: language))
}

// MARK: - Language detection

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

// MARK: - Strings

@Test func highlightPreservesTheLineText() {
    let source = #"let x = "hi" // comment"#
    let highlighted = SyntaxHighlighter.highlight(source, language: .swift)
    #expect(String(highlighted.characters) == source)
}

@Test func highlightOfAnEmptyLineStaysEmpty() {
    #expect(String(SyntaxHighlighter.highlight("", language: .swift).characters) == "")
}

@Test func aStringSurvivesItsEscapedQuotes() {
    #expect(tokens(#"x = "a\"b" + y"#, .cFamily)
            == ["plain:x = ", #"string:"a\"b""#, "plain: + y"])
}

@Test func anUnterminatedStringRunsToTheEndOfTheLine() {
    #expect(tokens(#"x = "oops"#, .cFamily) == ["plain:x = ", #"string:"oops"#])
}

@Test func anEscapeAtTheEndOfTheLineDoesNotOverrun() {
    #expect(tokens(#"x = "a\"#, .cFamily) == ["plain:x = ", #"string:"a\"#])
}

@Test func singleQuotesAreStringsEverywhereExceptSwift() {
    #expect(tokens("s = 'a'", .python) == ["plain:s = ", "string:'a'"])
    #expect(tokens("s = 'a'", .swift) == ["plain:s = 'a'"])
}

// MARK: - JSON

@Test func jsonSeparatesKeysFromValues() {
    #expect(tokens(#"{"name": "value"}"#, .json)
            == ["plain:{", #"type:"name""#, "plain:: ", #"string:"value""#, "plain:}"])
}

@Test func jsonNeverReadsACapitalisedWordAsAType() {
    #expect(tokens(#"{"True": True}"#, .json)
            == ["plain:{", #"type:"True""#, "plain:: True}"])
}

// MARK: - Numbers

@Test func anIdentifierSwallowsItsTrailingDigits() {
    #expect(tokens("x1 = 42", .cFamily) == ["plain:x1 = ", "number:42"])
}

@Test func numberLiteralsKeepTheirRadixAndSeparators() {
    #expect(tokens("n = 0xFF + 1_000", .swift)
            == ["plain:n = ", "number:0xFF", "plain: + ", "number:1_000"])
    #expect(tokens("n = 0o777 + 0b1010", .swift)
            == ["plain:n = ", "number:0o777", "plain: + ", "number:0b1010"])
}

@Test func aNumberGreedilyEatsATrailingDot() {
    // Known quirk: the scan accepts "." so member access on a literal splits oddly.
    #expect(tokens("value = 3.toString()", .cFamily)
            == ["plain:value = ", "number:3.", "plain:toString()"])
}

// MARK: - Identifiers, attributes and keywords

@Test func capitalisedWordsReadAsTypes() {
    #expect(tokens("let x: Int = 0", .swift)
            == ["keyword:let", "plain: x: ", "type:Int", "plain: = ", "number:0"])
}

@Test func attributesAndPoundKeywordsGetTheirOwnShades() {
    #expect(tokens("@main struct App", .swift)
            == ["attribute:@main", "plain: ", "keyword:struct", "plain: ", "type:App"])
    #expect(tokens("if #available(macOS 15, *)", .swift)
            == ["keyword:if", "plain: ", "keyword:#available",
                "plain:(macOS ", "number:15", "plain:, *)"])
}

@Test func aLoneAtSignIsJustText() {
    #expect(tokens("a @ b", .swift) == ["plain:a @ b"])
}

@Test func theGenericLanguageHasNoKeywords() {
    #expect(tokens("func main", .generic) == ["plain:func main"])
    #expect(tokens("func main", .swift) == ["keyword:func", "plain: main"])
}

// MARK: - Comments

@Test func aCommentSwallowsTheRestOfTheLine() {
    #expect(tokens(#"let x = 1 // note "quoted""#, .swift)
            == ["keyword:let", "plain: x = ", "number:1", "plain: ",
                #"comment:// note "quoted""#])
}

@Test func commentMarkersDifferByLanguage() {
    #expect(tokens("x = 1  # note", .python)
            == ["plain:x = ", "number:1", "plain:  ", "comment:# note"])
    #expect(tokens("x = 1  # note", .cFamily)
            == ["plain:x = ", "number:1", "plain:  # note"])
}

@Test func theGenericLanguageAcceptsBothCommentMarkers() {
    #expect(tokens("a // note", .generic) == ["plain:a ", "comment:// note"])
    #expect(tokens("a # note", .generic) == ["plain:a ", "comment:# note"])
}

@Test func jsonHasNoComments() {
    #expect(tokens("a // note", .json) == ["plain:a // note"])
}

// MARK: - Rendering diff lines

private func line(_ kind: GitDiffLine.Kind, _ text: String) -> GitDiffLine {
    GitDiffLine(id: 1, kind: kind, number: 1, text: text)
}

@Test func renderLeavesHunkHeadersAlone() throws {
    let rendered = try #require(
        SyntaxHighlighter.render([line(.hunk, "func main()")], language: .swift).first)
    #expect(shades(rendered.text) == ["plain:func main()"])
}

@Test func renderNeverHighlightsPlainText() throws {
    // The text has to be something highlight() would colour without a keyword
    // table, or the assertion cannot tell the bypass from an inert input.
    let rendered = try #require(
        SyntaxHighlighter.render([line(.added, "let n = 42")], language: .plain).first)
    #expect(shades(rendered.text) == ["plain:let n = 42"])
}

@Test func renderHighlightsEveryOtherKind() throws {
    let rendered = try #require(
        SyntaxHighlighter.render([line(.added, "func main()")], language: .swift).first)
    #expect(shades(rendered.text) == ["keyword:func", "plain: main()"])
}

@Test func renderTurnsAnEmptyLineIntoASpace() throws {
    let rendered = try #require(
        SyntaxHighlighter.render([line(.context, "")], language: .swift).first)
    #expect(String(rendered.text.characters) == " ")
}

@Test func renderCarriesTheLineIdentityThrough() throws {
    let source = [GitDiffLine(id: 7, kind: .removed, number: 42, text: "old")]
    let rendered = try #require(SyntaxHighlighter.render(source, language: .swift).first)
    #expect(rendered.id == 7)
    #expect(rendered.kind == .removed)
    #expect(rendered.number == 42)
}

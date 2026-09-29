import Testing
import Foundation
@testable import Den

private func codeBlocks(in markdown: String) -> [(code: String, language: String?)] {
    MarkdownText.parse(markdown).compactMap { block in
        guard case .code(let code, let language) = block.kind else { return nil }
        return (code, language)
    }
}

@Test func codeBlocksDropTheFencesAndKeepTheLanguage() throws {
    let markdown = #"""
    See:

    ```swift
    func main() {
        print("oi")
    }
    ```
    """#
    let blocks = codeBlocks(in: markdown)
    #expect(blocks.count == 1)
    let block = try #require(blocks.first)
    #expect(block.code == "func main() {\n    print(\"oi\")\n}")
    #expect(block.language == "swift")
}

@Test func codeBlocksKeepInnerBlankLinesAndIndentation() throws {
    let markdown = #"""
    ```
        indented

        after do vazio
    ```
    """#
    let block = try #require(codeBlocks(in: markdown).first)
    #expect(block.code == "    indented\n\n    after do vazio")
    #expect(block.language == nil)
}

@Test func separateFencesStaySeparateBlocks() {
    let markdown = #"""
    ```bash
    npm install
    ```

    Depois:

    ```bash
    npm test
    ```
    """#
    let blocks = codeBlocks(in: markdown)
    #expect(blocks.map(\.code) == ["npm install", "npm test"])
    #expect(blocks.map(\.language) == ["bash", "bash"])
}

private func plain(_ blocks: [MarkdownText.Block]) -> [String] {
    blocks.map { block in
        switch block.kind {
        case .paragraph(let content): "p:" + String(content.characters)
        case .heading(let level, let content): "h\(level):" + String(content.characters)
        case .code(let code, _): "code:" + code
        case .listItem(let marker, let depth, let content):
            "li\(depth)[\(marker)]:" + String(content.characters)
        case .quote(let content): "quote:" + String(content.characters)
        case .divider: "hr"
        case .table: "table"
        }
    }
}

@Test func headingsKeepTheirLevel() {
    let blocks = MarkdownText.parse("# One\n\n## Two\n\n### Three")
    #expect(plain(blocks) == ["h1:One", "h2:Two", "h3:Three"])
}

@Test func unorderedListsNumberTheirDepth() {
    let markdown = """
    - root
      - child
        - grandchild
    """
    #expect(plain(MarkdownText.parse(markdown))
            == ["li1[•]:root", "li2[•]:child", "li3[•]:grandchild"])
}

@Test func orderedListsCarryTheOrdinal() {
    let markdown = """
    1. first
    2. second
    3. third
    """
    #expect(plain(MarkdownText.parse(markdown))
            == ["li1[1.]:first", "li1[2.]:second", "li1[3.]:third"])
}

@Test func quotesAndDividersBecomeTheirOwnBlocks() {
    let markdown = """
    > quoted

    ---

    after
    """
    #expect(plain(MarkdownText.parse(markdown)) == ["quote:quoted", "hr", "p:after"])
}

@Test func tablesCollapseIntoASingleBlock() throws {
    let markdown = """
    | Nome | Tipo |
    | --- | ---: |
    | a | Int |
    | b | String |
    """
    let blocks = MarkdownText.parse(markdown)
    #expect(plain(blocks) == ["table"])

    guard case .table(let table) = try #require(blocks.first).kind else {
        Issue.record("expected a table")
        return
    }
    #expect(table.header.map { String($0.characters) } == ["Nome", "Tipo"])
    #expect(table.rows.map { $0.map { String($0.characters) } }
            == [["a", "Int"], ["b", "String"]])
    #expect(table.alignments.count == 2)
}

@Test func twoTablesNeverMergeIntoOne() {
    let markdown = """
    | a |
    | --- |
    | 1 |

    between

    | b |
    | --- |
    | 2 |
    """
    #expect(plain(MarkdownText.parse(markdown)) == ["table", "p:between", "table"])
}

@Test func emptyAndBlankInputProduceNoBlocks() {
    #expect(MarkdownText.parse("").isEmpty)
    #expect(MarkdownText.parse("   \n\n  ").isEmpty)
}

@Test func blocksAreCachedByText() {
    let markdown = "# cached title\n\nbody"
    let first = MarkdownText.blocks(for: markdown)
    let second = MarkdownText.blocks(for: markdown)
    #expect(plain(first) == plain(second))
    #expect(first.map(\.id) == second.map(\.id))
}

import Testing
import Foundation
@testable import DevSpace

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

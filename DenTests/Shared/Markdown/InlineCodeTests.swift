import Testing
import SwiftUI
@testable import Den

private func paragraph(_ markdown: String) throws -> AttributedString {
    let block = try #require(MarkdownText.parse(markdown).first)
    guard case .paragraph(let content) = block.kind else {
        Issue.record("expected a paragraph")
        return AttributedString()
    }
    return content
}

private func fonts(_ text: AttributedString) -> Set<Font?> {
    Set(text.runs.map { $0[AttributeScopes.SwiftUIAttributes.FontAttribute.self] })
}

private func colors(_ text: AttributedString) -> Set<Color?> {
    Set(text.runs.map { $0[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] })
}

private func kerns(_ text: AttributedString) -> [CGFloat?] {
    text.characters.indices.map { index in
        text[index..<text.characters.index(after: index)]
            .runs.first?[AttributeScopes.SwiftUIAttributes.KerningAttribute.self]
    }
}

@Test func textWithoutCodeStaysASingleSegment() throws {
    let segments = InlineCode.segments(of: try paragraph("plain **bold** text"), size: 13)
    #expect(segments.map { String($0.content.characters) } == ["plain bold text"])
    #expect(segments.map(\.isCode) == [false])
}

@Test func codeSpansBecomeTheirOwnSegments() throws {
    let segments = InlineCode.segments(of: try paragraph("Use `foo` and `bar`."), size: 13)
    #expect(segments.map { String($0.content.characters) } == ["Use ", "foo", " and ", "bar", "."])
    #expect(segments.map(\.isCode) == [false, true, false, true, false])
}

@Test func codeSpansAreMonospacedOnePointSmaller() throws {
    let segments = InlineCode.segments(of: try paragraph("Use `foo`"), size: 13)
    let code = try #require(segments.last)
    #expect(fonts(code.content) == [.system(size: 12, weight: .regular, design: .monospaced)])
    #expect(colors(code.content) == [InlineCode.color])
}

@Test func boldCodeSpansStayBold() throws {
    let segments = InlineCode.segments(of: try paragraph("Use **`foo`**"), size: 13)
    let code = try #require(segments.last)
    #expect(fonts(code.content) == [.system(size: 12, weight: .semibold, design: .monospaced)])
}

@Test func codeSpansKeepTheWeightOfTheirSurroundings() throws {
    let segments = InlineCode.segments(of: try paragraph("Use `foo`"), size: 17, weight: .semibold)
    #expect(fonts(segments[1].content) == [.system(size: 16, weight: .semibold, design: .monospaced)])
}

@Test func italicCodeSpansStayItalic() throws {
    let segments = InlineCode.segments(of: try paragraph("Use *`foo`*"), size: 13)
    #expect(fonts(segments[1].content)
            == [.system(size: 12, weight: .regular, design: .monospaced).italic()])
}

@Test func touchingCodeSpansArePaddedOnlyAtTheEnd() throws {
    let segments = InlineCode.segments(of: try paragraph("Use `a`*`b`*"), size: 13)
    #expect(segments.map { String($0.content.characters) } == ["Use ", "ab"])
    #expect(kerns(segments[1].content) == [nil, InlineCode.padding])
}

@Test func codeSpansMakeRoomForThePillOnBothSides() throws {
    let segments = InlineCode.segments(of: try paragraph("Use `foo` now"), size: 13)
    let pad = InlineCode.padding
    #expect(kerns(segments[0].content) == [nil, nil, nil, pad])
    #expect(kerns(segments[1].content) == [nil, nil, pad])
    #expect(kerns(segments[2].content) == [nil, nil, nil, nil])
}

@Test func touchingCodeRunsShareOnePill() {
    let line = [
        (bounds: CGRect(x: 0, y: 0, width: 30, height: 16), isCode: false),
        (bounds: CGRect(x: 30, y: 1, width: 20, height: 14), isCode: true),
        (bounds: CGRect(x: 50, y: 1, width: 6, height: 14), isCode: true),
        (bounds: CGRect(x: 56, y: 0, width: 4, height: 16), isCode: false),
        (bounds: CGRect(x: 60, y: 1, width: 12, height: 14), isCode: true),
    ]
    let pad = InlineCode.padding
    #expect(InlineCode.pills(in: line) == [
        CGRect(x: 30 - pad, y: 1, width: 26 + pad, height: 14),
        CGRect(x: 60 - pad, y: 1, width: 12 + pad, height: 14),
    ])
}

@Test func linesWithoutCodeHaveNoPills() {
    let line = [(bounds: CGRect(x: 0, y: 0, width: 30, height: 16), isCode: false)]
    #expect(InlineCode.pills(in: line).isEmpty)
}

import Testing
import AppKit
@testable import DevSpace


@Test func paletteCoversTheCubeAndTheGrayRamp() {
    #expect(LogPalette.rgb(forIndex: 16) == LogPalette.RGB(red: 0, green: 0, blue: 0))
    #expect(LogPalette.rgb(forIndex: 21) == LogPalette.RGB(red: 0, green: 0, blue: 255))
    #expect(LogPalette.rgb(forIndex: 196) == LogPalette.RGB(red: 255, green: 0, blue: 0))
    #expect(LogPalette.rgb(forIndex: 231) == LogPalette.RGB(red: 255, green: 255, blue: 255))
    #expect(LogPalette.rgb(forIndex: 232) == LogPalette.RGB(red: 8, green: 8, blue: 8))
    #expect(LogPalette.rgb(forIndex: 255) == LogPalette.RGB(red: 238, green: 238, blue: 238))
}

@Test func documentMirrorsTheBufferThroughEveryChange() {
    var buffer = LogBuffer(capacity: 3)
    let storage = NSMutableAttributedString()
    let document = LogDocument(storage: storage)
    let batches: [[ANSIParser.Event]] = [
        [.text("a", plainStyle), .newline, .text("b", plainStyle)],
        [.carriageReturn, .text("B", plainStyle)],
        [.newline, .text("c", plainStyle), .newline, .text("d", plainStyle)],
        [.newline, .newline, .newline, .newline, .text("flood", plainStyle)],
        [.eraseLine],
    ]
    for batch in batches {
        document.apply(buffer.apply(batch))
        #expect(storage.string == buffer.plainText)
    }
    document.apply(buffer.clear())
    #expect(storage.string == "")
}

@Test func reloadRendersEveryLine() {
    let storage = NSMutableAttributedString(string: "stale")
    LogDocument(storage: storage).reload([plainLine("a"), plainLine(""), plainLine("b")])
    #expect(storage.string == "a\n\nb")
}

@Test func stylesBecomeAttributes() {
    let style = LogStyle(foreground: .rgb(255, 0, 0), underline: true)
    let rendered = LogRenderer().render(LogLine(spans: [LogSpan(text: "x", style: style)]))
    let attributes = rendered.attributes(at: 0, effectiveRange: nil)
    let color = attributes[.foregroundColor] as? NSColor
    #expect(color?.usingColorSpace(.sRGB)?.redComponent == 1)
    #expect(attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
}

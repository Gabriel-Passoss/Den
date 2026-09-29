import Testing
import AppKit
@testable import DevSpace

@Test func errorsAreRecognizedAcrossTools() {
    let lines = [
        "npm ERR! code ELIFECYCLE",
        "npm error code 1",
        "✘ [ERROR] Could not resolve \"react\"",
        "FAIL src/app.test.ts",
        "TypeError: Cannot read properties of undefined",
        "Traceback (most recent call last):",
        "Exception in thread \"main\" java.lang.NullPointerException",
        "src/app.ts(3,5): error TS2322: Type 'string' is not assignable",
        "error[E0308]: mismatched types",
        "x.c:3:5: error: expected ';'",
        "[vite] Internal server error: Failed to resolve import",
        "panic: runtime error: index out of range",
        "Error: listen EADDRINUSE: address already in use :::3000",
        "2026-09-28 12:01:07 ERROR Connection refused",
    ]
    for line in lines {
        #expect(LogHighlighter.level(of: line) == .error, "\(line)")
    }
}

@Test func warningsAreRecognized() {
    let lines = [
        "npm warn deprecated inflight@1.0.6",
        "npm WARN old lockfile",
        "warning: unused variable `x`",
        "(node:42) [DEP0040] DeprecationWarning: The `punycode` module is deprecated",
        "12:01:05 WARN Slow query 812ms",
        "Warning: React does not recognize the prop",
    ]
    for line in lines {
        #expect(LogHighlighter.level(of: line) == .warning, "\(line)")
    }
}

@Test func debugAndInfoAreRecognized() {
    #expect(LogHighlighter.level(of: "DEBUG cache miss for /users") == .debug)
    #expect(LogHighlighter.level(of: "TRACE entering handler") == .debug)
    #expect(LogHighlighter.level(of: "INFO Server listening on 3000") == .info)
}

@Test func ordinaryLinesHaveNoLevel() {
    let lines = [
        "  VITE v5.2.0  ready in 312 ms",
        "Error handling improved in this release",
        "Found 0 errors, 0 warnings",
        "Tests: 1 failed, 2 passed",
        "information retrieval",
        "GET /api/users 200 12ms",
        "",
    ]
    for line in lines {
        #expect(LogHighlighter.level(of: line) == nil, "\(line)")
    }
}

@Test func errorOutranksWarning() {
    #expect(LogHighlighter.level(of: "WARN retrying after error: timeout") == .error)
}

private func color(_ rendered: NSAttributedString, at offset: Int) -> NSColor? {
    rendered.attributes(at: offset, effectiveRange: nil)[.foregroundColor] as? NSColor
}

@Test func anErrorLinePaintsOnlyTheUncoloredSpans() {
    let line = LogLine(spans: [
        LogSpan(text: "built ", style: LogStyle(foreground: .palette(2))),
        LogSpan(text: "ERROR boom", style: LogStyle()),
    ])
    let rendered = LogRenderer().render(line)
    #expect(color(rendered, at: 0) == LogRenderer.color(.palette(2)))
    #expect(color(rendered, at: 6) == LogRenderer.color(.palette(1)))
    #expect(color(rendered, at: rendered.length - 1) == LogRenderer.color(.palette(1)))
}

@Test func aWarningLinePaintsTheWholeLine() {
    let rendered = LogRenderer().render(LogLine(spans: [LogSpan(text: "npm warn deprecated", style: LogStyle())]))
    #expect(color(rendered, at: 0) == LogRenderer.color(.palette(3)))
    #expect(color(rendered, at: rendered.length - 1) == LogRenderer.color(.palette(3)))
}

@Test func debugLinesAreDimmed() {
    let rendered = LogRenderer().render(LogLine(spans: [LogSpan(text: "DEBUG cache miss", style: LogStyle())]))
    #expect(color(rendered, at: 0) == .secondaryLabelColor)
    #expect(color(rendered, at: rendered.length - 1) == .secondaryLabelColor)
}

@Test func infoDimsOnlyTheKeyword() {
    let rendered = LogRenderer().render(LogLine(spans: [LogSpan(text: "12:00 INFO Server listening", style: LogStyle())]))
    #expect(color(rendered, at: 0) == .textColor)
    #expect(color(rendered, at: 6) == .secondaryLabelColor)
    #expect(color(rendered, at: 9) == .secondaryLabelColor)
    #expect(color(rendered, at: 11) == .textColor)
}

@Test func plainLinesKeepTheDefaultColor() {
    let rendered = LogRenderer().render(LogLine(spans: [LogSpan(text: "GET /api 200", style: LogStyle())]))
    #expect(color(rendered, at: 0) == .textColor)
}

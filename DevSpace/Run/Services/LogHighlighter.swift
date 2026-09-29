import Foundation

nonisolated enum LogLevel: Equatable, Sendable {
    case error
    case warning
    case debug
    case info
}

nonisolated enum LogHighlighter {
    private static let rules: [(LogLevel, NSRegularExpression)] = [
        (.error, pattern(#"\b(ERROR|FATAL|FAIL|FAILED|PANIC)\b|\bERR!|\bnpm error\b|\b[A-Z]\w*(Error|Exception)\b|\bError:|\b(error|fatal|panic)(:|\[)|\berror TS\d+|^Traceback \(most recent call last\)"#)),
        (.warning, pattern(#"\b(WARN|WARNING|Warning|warning|warn)\b|\b[A-Z]\w*Warning\b"#)),
        (.debug, pattern(#"\b(DEBUG|TRACE)\b"#)),
        (.info, infoKeyword),
    ]

    private static let infoKeyword = pattern(#"\bINFO\b"#)

    static func level(of text: String) -> LogLevel? {
        let range = NSRange(text.startIndex..., in: text)
        return rules.first { $0.1.firstMatch(in: text, range: range) != nil }?.0
    }

    static func infoRanges(in text: String) -> [NSRange] {
        infoKeyword.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
    }

    private static func pattern(_ source: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: source, options: [.anchorsMatchLines])
    }
}

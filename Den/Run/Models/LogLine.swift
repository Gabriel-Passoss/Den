import Foundation

nonisolated enum LogColor: Hashable, Sendable {
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

nonisolated struct LogStyle: Hashable, Sendable {
    var foreground: LogColor?
    var background: LogColor?
    var bold = false
    var dim = false
    var italic = false
    var underline = false
    var inverse = false

    static let notice = LogStyle(foreground: .palette(3))
}

nonisolated struct LogSpan: Equatable, Sendable {
    var text: String
    var style: LogStyle
}

nonisolated struct LogLine: Equatable, Sendable {
    var spans: [LogSpan] = []

    var text: String { spans.map(\.text).joined() }

    mutating func append(_ text: String, style: LogStyle) {
        guard !text.isEmpty else { return }
        if let last = spans.indices.last, spans[last].style == style {
            spans[last].text += text
        } else {
            spans.append(LogSpan(text: text, style: style))
        }
    }
}

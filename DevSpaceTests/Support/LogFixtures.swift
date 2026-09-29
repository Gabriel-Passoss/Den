@testable import DevSpace

let plainStyle = LogStyle()

func plainLine(_ text: String) -> LogLine {
    LogLine(spans: text.isEmpty ? [] : [LogSpan(text: text, style: plainStyle)])
}

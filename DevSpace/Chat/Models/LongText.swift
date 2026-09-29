import Foundation

enum LongText {
    static let minimumLines = 5
    static let minimumCharacters = 200
    static let alwaysLongCharacters = 1_500
    static let previewLines = 4

    static func isLong(_ text: String) -> Bool {
        guard text.utf8.count >= minimumCharacters else { return false }
        let characters = text.count
        return characters >= alwaysLongCharacters
            || (characters >= minimumCharacters && lineCount(text) >= minimumLines)
    }

    static func lineCount(_ text: String) -> Int {
        let body = text.trimmingCharacters(in: .newlines)
        guard !body.isEmpty else { return 0 }
        return body.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
    }

    static func lineLabel(_ count: Int) -> String {
        count == 1 ? "1 linha" : "\(count) linhas"
    }

    static func preview(_ text: String, lines: Int = previewLines, limit: Int = 400) -> String {
        let head = text
            .split(maxSplits: lines, omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .prefix(lines)
            .joined(separator: "\n")
        return String(head.prefix(limit))
    }
}

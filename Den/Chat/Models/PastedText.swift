import Foundation

struct PastedText: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let headline: String
    let lineCount: Int

    init(text: String) {
        self.text = text
        let firstLine = text.split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        headline = String(firstLine.trimmingCharacters(in: .whitespaces).prefix(120))
        lineCount = LongText.lineCount(text)
    }
}

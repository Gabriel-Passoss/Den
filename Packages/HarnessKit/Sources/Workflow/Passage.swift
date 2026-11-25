import Foundation

public struct Passage: Sendable, Equatable {
    public let text: String

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = trimmed
    }
}

import Foundation

nonisolated enum QuickPrompt {
    static let requestLimit = 600

    static func oneLine(_ output: String, maxLength: Int) -> String? {
        let cleaned = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned.count <= maxLength,
              !cleaned.contains(where: \.isNewline) else { return nil }
        return cleaned
    }
}

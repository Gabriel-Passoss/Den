import Foundation

nonisolated enum BranchNamer {
    static let limit = 48
    static let fallbackStem = "tarefa"

    static func name(for message: String, prefix: String, fallback: String? = nil,
                     taken: (String) -> Bool = { _ in false }) -> String {
        let stem = stem(for: message) ?? "\(fallbackStem)-\(fallback ?? randomSuffix())"
        let first = prefix + stem
        guard taken(first) else { return first }
        var counter = 2
        while taken("\(first)-\(counter)") { counter += 1 }
        return "\(first)-\(counter)"
    }

    static func stem(for message: String) -> String? {
        var text = message
        text = text.replacing(#/https?://\S+/#, with: " ")
        text = text.replacing(#/(?m)^\s*/\S+/#, with: " ")
        text = text.replacing(#/@\S+/#, with: " ")
        var parts: [String] = []
        if let key = text.firstMatch(of: #/\b[A-Z][A-Z0-9]{1,9}-[0-9]+\b/#) {
            parts.append(String(key.output))
            text.removeSubrange(key.range)
        }
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        let words = folded
            .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
            .prefix(5)
            .map(String.init)
        for word in words {
            if (parts + [word]).joined(separator: "-").count <= limit {
                parts.append(word)
            } else {
                if parts.isEmpty { parts.append(String(word.prefix(limit))) }
                break
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "-")
    }

    static func folder(for branch: String, prefix: String) -> String {
        let bare = !prefix.isEmpty && branch.hasPrefix(prefix)
            ? String(branch.dropFirst(prefix.count)) : branch
        return bare.replacingOccurrences(of: "/", with: "-")
    }

    static func randomSuffix() -> String {
        String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(4))
    }
}

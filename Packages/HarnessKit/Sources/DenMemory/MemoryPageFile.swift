import Foundation

public enum MemoryPageFile {
    private static let fence = "---"

    public static func render(_ page: MemoryPage) -> String {
        let header = [
            fence,
            "title: \(oneLine(page.title))",
            "category: \(page.category.rawValue)",
            "created: \(stamp(page.created))",
            "updated: \(stamp(page.updated))",
            "sessions: \(page.sessions.map(\.uuidString).joined(separator: ", "))",
            fence,
        ]
        return header.joined(separator: "\n") + "\n\n" + trimmed(page.body) + "\n"
    }

    public static func parse(_ text: String, slug: String, layer: MemoryLayer,
                             fallbackDate: Date) -> MemoryPage {
        let (fields, body) = split(text)
        let title = fields["title"].flatMap { $0.isEmpty ? nil : $0 } ?? title(from: slug)
        let created = fields["created"].flatMap(date(from:)) ?? fallbackDate
        return MemoryPage(
            slug: slug, title: title,
            category: MemoryCategory.parse(fields["category"] ?? "", in: layer),
            body: trimmed(body),
            created: created,
            updated: fields["updated"].flatMap(date(from:)) ?? created,
            sessions: (fields["sessions"] ?? "").split(separator: ",").compactMap {
                UUID(uuidString: $0.trimmingCharacters(in: .whitespaces))
            })
    }

    static func title(from slug: String) -> String {
        let words = slug.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private static func split(_ text: String) -> (fields: [String: String], body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == fence,
              let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == fence })
        else { return ([:], text) }
        var fields: [String: String] = [:]
        for line in lines[1..<close] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return (fields, lines[(close + 1)...].joined(separator: "\n"))
    }

    private static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }
}

import Foundation

nonisolated struct MentionCandidate: Identifiable {
    let path: String
    let isDirectory: Bool
    var id: String { path }

    /// The path as `searchable` spells it, in UTF-8, and where its file name
    /// starts: worked out once, so a keystroke only compares bytes.
    private let key: [UInt8]
    private let nameStart: Int

    init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
        key = Array(Self.searchable(path).utf8)
        nameStart = key.lastIndex(of: UInt8(ascii: "/")).map { $0 + 1 } ?? 0
    }

    /// Lowercased and composed, since a name on disk is often decomposed while
    /// the keyboard types composed accents.
    static func searchable(_ text: String) -> String {
        text.lowercased().precomposedStringWithCanonicalMapping
    }

    /// 0 when the file name starts with `query`, 1 when the name holds it, 2
    /// when only the path does.
    func rank(for query: [UInt8]) -> Int? {
        if let hit = offset(of: query, from: nameStart) { return hit == nameStart ? 0 : 1 }
        return offset(of: query, from: 0) == nil ? nil : 2
    }

    private func offset(of query: [UInt8], from start: Int) -> Int? {
        key.withUnsafeBytes { key in
            query.withUnsafeBytes { query in
                guard let base = key.baseAddress, let needle = query.baseAddress,
                      key.count - start >= query.count,
                      let hit = memmem(base + start, key.count - start, needle, query.count)
                else { return nil }
                return base.distance(to: UnsafeRawPointer(hit))
            }
        }
    }
}

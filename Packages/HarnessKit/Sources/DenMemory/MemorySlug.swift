import Foundation

public enum MemorySlug {
    public static let fallback = "memoria"
    static let limit = 60

    public static func make(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let pieces = folded.unicodeScalars
            .split { !isPlain($0) }
            .map { String(String.UnicodeScalarView($0)) }
        let joined = pieces.joined(separator: "-")
        let cut = String(joined.prefix(limit)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cut.isEmpty ? fallback : cut
    }

    private static func isPlain(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}

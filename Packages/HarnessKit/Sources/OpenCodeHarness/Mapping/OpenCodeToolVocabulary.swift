import HarnessCore

enum OpenCodeToolVocabulary {

    static func canonical(for kind: String) -> CanonicalTool? {
        switch kind {
        case "read": return .read
        case "edit": return .edit
        case "delete", "move": return .write
        case "search": return .search
        case "execute": return .execute
        case "fetch": return .fetch
        default: return nil
        }
    }
}

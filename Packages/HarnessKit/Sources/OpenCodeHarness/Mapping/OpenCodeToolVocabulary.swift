import HarnessCore

enum OpenCodeToolVocabulary {

    static func canonical(for kind: String) -> CanonicalTool? {
        switch kind {
        case "read": .read
        case "edit": .edit
        case "delete", "move": .write
        case "search": .search
        case "execute": .execute
        case "fetch": .fetch
        default: nil
        }
    }
}

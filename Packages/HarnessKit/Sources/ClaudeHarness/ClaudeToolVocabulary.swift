import HarnessCore

enum ClaudeToolVocabulary {
    static func canonical(for rawName: String) -> CanonicalTool? {
        switch rawName {
        case "Read": return .read
        case "Write": return .write
        case "Edit", "NotebookEdit": return .edit
        case "Bash": return .execute
        case "WebSearch", "Glob", "Grep": return .search
        case "WebFetch": return .fetch
        default: return nil
        }
    }
}

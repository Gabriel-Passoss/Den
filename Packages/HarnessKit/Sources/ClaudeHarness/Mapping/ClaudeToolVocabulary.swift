import HarnessCore

enum ClaudeToolVocabulary {
    static func canonical(for rawName: String) -> CanonicalTool? {
        switch rawName {
        case "Read": .read
        case "Write": .write
        case "Edit", "NotebookEdit": .edit
        case "Bash": .execute
        case "WebSearch", "Glob", "Grep": .search
        case "WebFetch": .fetch
        default: nil
        }
    }
}

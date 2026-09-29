import Foundation
import Observation

@Observable final class MentionController {
    var fileIndex: [MentionCandidate] = []
    var selection = 0
    var dismissed = false

    func query(in text: String) -> String? {
                guard let at = text.range(of: "@", options: .backwards) else { return nil }
        let token = text[at.upperBound...]
        guard !token.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        if at.lowerBound > text.startIndex {
            let previous = text[text.index(before: at.lowerBound)]
            guard previous.isWhitespace || previous.isNewline else { return nil }
        }
        return String(token)
    }

    func matches(prompt: String) -> [MentionCandidate] {
        guard !dismissed, let query = query(in: prompt) else { return [] }
        guard !query.isEmpty else { return Array(fileIndex.prefix(8)) }
        let lowered = query.lowercased()
        let ranked = fileIndex.compactMap { candidate -> (MentionCandidate, Int)? in
            let name = (candidate.path as NSString).lastPathComponent.lowercased()
            if name.hasPrefix(lowered) { return (candidate, 0) }
            if name.contains(lowered) { return (candidate, 1) }
            if candidate.path.lowercased().contains(lowered) { return (candidate, 2) }
            return nil
        }
        return ranked.sorted { $0.1 < $1.1 }.prefix(8).map(\.0)
    }

    func accept(_ candidate: MentionCandidate, in chat: ChatModel) {
        guard let at = chat.prompt.range(of: "@", options: .backwards) else { return }
        let prefix = String(chat.prompt[..<at.lowerBound])
        if candidate.isDirectory {
            chat.prompt = prefix + "@" + candidate.path + "/"
        } else {
            chat.prompt = prefix + "@" + candidate.path + " "
        }
    }

    func loadIndex(under root: URL) async {
        let root = root
        fileIndex = await Task.detached(priority: .utility) {
            Self.indexFiles(under: root)
        }.value
    }

    nonisolated static func indexFiles(under root: URL) -> [MentionCandidate] {
        let skip = ProjectScan.skippedFolders
        let base = canonical(root)
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var results: [MentionCandidate] = []
        for case let url as URL in enumerator {
            if results.count >= 4000 { break }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDirectory, skip.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let relative = relativePath(of: url, under: base) else { continue }
            results.append(MentionCandidate(path: relative, isDirectory: isDirectory))
        }
        return results.sorted {
            let a = $0.path.filter { $0 == "/" }.count
            let b = $1.path.filter { $0 == "/" }.count
            return a == b ? $0.path < $1.path : a < b
        }
    }

    nonisolated private static func canonical(_ root: URL) -> URL {
        let resolved = root.resolvingSymlinksInPath()
        guard let path = try? resolved.resourceValues(forKeys: [.canonicalPathKey])
            .canonicalPath else { return resolved }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    nonisolated private static func relativePath(of url: URL, under root: URL) -> String? {
        guard url.path.hasPrefix(root.path) else { return nil }
        let relative = url.path.dropFirst(root.path.count).drop(while: { $0 == "/" })
        return relative.isEmpty ? nil : String(relative)
    }
}

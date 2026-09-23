import Foundation

nonisolated enum GitFileState: Equatable {
    case modified, added, deleted, renamed, untracked, conflicted

    var badge: String {
        switch self {
        case .modified: "M"
        case .added: "+"
        case .deleted: "−"
        case .renamed: "R"
        case .untracked: "+"
        case .conflicted: "!"
        }
    }
}

nonisolated struct GitStatusEntry: Equatable {
    let path: String
    let state: GitFileState

    var isDirectory: Bool { path.hasSuffix("/") }
}

nonisolated struct GitDiffLine: Identifiable, Equatable {
    enum Kind: Equatable { case context, added, removed, hunk }
    let id: Int
    let kind: Kind
    let number: Int?
    let text: String
}

nonisolated enum GitParsing {

    static func statusEntries(fromPorcelain output: String) -> [GitStatusEntry] {
        let tokens = output.split(separator: "\0").map(String.init)
        var entries: [GitStatusEntry] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            guard token.count > 3 else { continue }
            let staged = token[token.startIndex]
            let unstaged = token[token.index(after: token.startIndex)]
            let path = String(token.dropFirst(3))

            if staged == "R" || staged == "C" || unstaged == "R" || unstaged == "C" {
                index += 1
            }

            guard let state = state(staged: staged, unstaged: unstaged) else { continue }
            entries.append(GitStatusEntry(path: path, state: state))
        }
        return entries
    }

    private static func state(staged: Character, unstaged: Character) -> GitFileState? {
        switch (staged, unstaged) {
        case ("?", _): return .untracked
        case ("!", _): return nil
        case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): return .conflicted
        case ("R", _), ("C", _), (_, "R"), (_, "C"): return .renamed
        case ("D", _), (_, "D"): return .deleted
        case ("A", _): return .added
        default: return .modified
        }
    }

    static func fileDiffs(fromUnified output: String) -> [String: [GitDiffLine]] {
        var diffs: [String: [GitDiffLine]] = [:]
        var path: String?
        var lines: [GitDiffLine] = []
        var oldLine = 0
        var newLine = 0
        var nextID = 0

        func close() {
            if let path { diffs[path] = lines }
            lines = []
        }

        for raw in output.components(separatedBy: "\n") {
            if raw.hasPrefix("diff --git ") {
                close()
                path = targetPath(fromHeader: raw)
                continue
            }
            guard path != nil else { continue }
            nextID += 1

            if raw.hasPrefix("@@") {
                let numbers = hunkStart(raw)
                oldLine = numbers.old
                newLine = numbers.new
                lines.append(GitDiffLine(id: nextID, kind: .hunk, number: nil,
                                         text: hunkContext(raw)))
            } else if raw.hasPrefix("Binary files ") {
                lines.append(GitDiffLine(id: nextID, kind: .hunk, number: nil,
                                         text: "Arquivo binário"))
            } else if raw.hasPrefix("+++") || raw.hasPrefix("---") {
                continue
            } else if raw.hasPrefix("+") {
                lines.append(GitDiffLine(id: nextID, kind: .added, number: newLine,
                                         text: String(raw.dropFirst())))
                newLine += 1
            } else if raw.hasPrefix("-") {
                lines.append(GitDiffLine(id: nextID, kind: .removed, number: oldLine,
                                         text: String(raw.dropFirst())))
                oldLine += 1
            } else if raw.hasPrefix(" ") {
                lines.append(GitDiffLine(id: nextID, kind: .context, number: newLine,
                                         text: String(raw.dropFirst())))
                oldLine += 1
                newLine += 1
            }
        }
        close()
        return diffs
    }

    private static func targetPath(fromHeader line: String) -> String {
        guard let range = line.range(of: " b/", options: .backwards) else { return line }
        var path = String(line[range.upperBound...])
        if path.hasSuffix("\"") { path.removeLast() }
        return path
    }

    private static func hunkStart(_ line: String) -> (old: Int, new: Int) {
        var old = 1
        var new = 1
        for part in line.split(separator: " ") {
            if part.hasPrefix("-") {
                old = Int(part.dropFirst().split(separator: ",").first ?? "1") ?? 1
            } else if part.hasPrefix("+") {
                new = Int(part.dropFirst().split(separator: ",").first ?? "1") ?? 1
            }
        }
        return (old, new)
    }

    private static func hunkContext(_ line: String) -> String {
        guard let range = line.range(of: "@@", options: .backwards),
              range.lowerBound > line.startIndex else { return "" }
        return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    static func fingerprint(of texts: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for text in texts {
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x100_0000_01b3
            }
            hash ^= 0x1e
            hash &*= 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

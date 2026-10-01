import SwiftUI

nonisolated struct GitDisplayLine: Identifiable {
    let id: Int
    let kind: GitDiffLine.Kind
    let number: Int?
    let text: AttributedString
}

nonisolated enum SyntaxHighlighter {
    enum Language {
        case swift, cFamily, python, shell, json, generic, plain
    }

    static func language(forHint hint: String?) -> Language {
        guard let hint = hint?.trimmingCharacters(in: .whitespaces).lowercased(),
              !hint.isEmpty else { return .plain }
        return switch hint {
        case "swift": .swift
        case "js", "jsx", "javascript", "ts", "tsx", "typescript", "java", "kotlin",
             "kt", "go", "rust", "rs", "c", "cpp", "c++", "objc", "cs", "php",
             "dart", "scala": .cFamily
        case "py", "python": .python
        case "sh", "bash", "zsh", "shell", "fish", "console", "terminal": .shell
        case "json", "jsonc": .json
        case "text", "txt", "plain", "md", "markdown", "": .plain
        default: .generic
        }
    }

    static func language(forFile name: String) -> Language {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": .swift
        case "js", "jsx", "ts", "tsx", "mjs", "cjs", "c", "h", "cpp", "hpp",
             "m", "mm", "java", "kt", "kts", "go", "rs", "cs", "php": .cFamily
        case "py": .python
        case "sh", "bash", "zsh", "fish": .shell
        case "json": .json
        case "md", "txt", "": .plain
        default: .generic
        }
    }

    static func render(_ lines: [GitDiffLine], language: Language) -> [GitDisplayLine] {
        lines.map { line in
            let text = line.text.isEmpty ? " " : line.text
            let rendered = (line.kind == .hunk || language == .plain)
                ? AttributedString(text)
                : highlight(text, language: language)
            return GitDisplayLine(id: line.id, kind: line.kind,
                                  number: line.number, text: rendered)
        }
    }

    // MARK: - Colors

    static let keywordColor = Color(hex: 0xB4A8FF)
    static let stringColor = Color(hex: 0xB5CE8A)
    static let numberColor = Color(hex: 0xF2B482)
    static let typeColor = Color(hex: 0x7FD1D9)
    static let commentColor = Color(hex: 0x6B7385)
    static let attributeColor = Color(hex: 0xE0B45F)

    static func highlight(_ line: String, language: Language) -> AttributedString {
        let chars = Array(line)
        var result = AttributedString()
        var plain = ""
        var i = 0

        func flush() {
            if !plain.isEmpty {
                result += AttributedString(plain)
                plain = ""
            }
        }
        func append(_ text: String, _ color: Color) {
            flush()
            var segment = AttributedString(text)
            segment.foregroundColor = color
            result += segment
        }

        while i < chars.count {
            let c = chars[i]

            if isCommentStart(chars, at: i, language: language) {
                append(String(chars[i...]), commentColor)
                break
            }

            if c == "\"" || (c == "'" && language != .swift) {
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == c { j += 1; break }
                    j += 1
                }
                j = min(j, chars.count)
                let text = String(chars[i..<j])
                if language == .json, nextNonSpace(chars, from: j) == ":" {
                    append(text, typeColor)
                } else {
                    append(text, stringColor)
                }
                i = j
                continue
            }

            if c.isASCII, c.isNumber, i == 0 || !isIdentifierChar(chars[i - 1]) {
                var j = i
                while j < chars.count,
                      chars[j].isHexDigit || chars[j] == "." || chars[j] == "_"
                        || chars[j] == "x" || chars[j] == "b" || chars[j] == "o" {
                    j += 1
                }
                append(String(chars[i..<j]), numberColor)
                i = j
                continue
            }

            if c == "@" || (c == "#" && language == .swift) {
                var j = i + 1
                while j < chars.count, isIdentifierChar(chars[j]) { j += 1 }
                if j > i + 1 {
                    append(String(chars[i..<j]),
                           c == "@" ? attributeColor : keywordColor)
                    i = j
                    continue
                }
            }

            if isIdentifierStart(c) {
                var j = i
                while j < chars.count, isIdentifierChar(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                if keywords(for: language).contains(word) {
                    append(word, keywordColor)
                } else if language != .json, c.isUppercase {
                    append(word, typeColor)
                } else {
                    plain += word
                }
                i = j
                continue
            }

            plain.append(c)
            i += 1
        }
        flush()
        return result
    }

    // MARK: - Lexical details

    private static func isCommentStart(_ chars: [Character], at i: Int,
                                       language: Language) -> Bool {
        func slash() -> Bool {
            chars[i] == "/" && i + 1 < chars.count
                && (chars[i + 1] == "/" || chars[i + 1] == "*")
        }
        func hash() -> Bool { chars[i] == "#" }
        return switch language {
        case .swift, .cFamily: slash()
        case .python, .shell: hash()
        case .generic: slash() || hash()
        case .json, .plain: false
        }
    }

    private static func nextNonSpace(_ chars: [Character], from index: Int) -> Character? {
        var i = index
        while i < chars.count {
            if chars[i] != " ", chars[i] != "\t" { return chars[i] }
            i += 1
        }
        return nil
    }

    private static func isIdentifierStart(_ c: Character) -> Bool {
        c.isLetter || c == "_"
    }

    private static func isIdentifierChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    private static func keywords(for language: Language) -> Set<String> {
        switch language {
        case .swift: swiftKeywords
        case .cFamily: cFamilyKeywords
        case .python: pythonKeywords
        case .shell: shellKeywords
        case .json: jsonKeywords
        case .generic, .plain: []
        }
    }

    private static let swiftKeywords: Set<String> = [
        "func", "let", "var", "if", "else", "guard", "return", "for", "while",
        "switch", "case", "default", "break", "continue", "import", "struct",
        "class", "enum", "protocol", "extension", "init", "deinit", "self",
        "Self", "super", "nil", "true", "false", "in", "do", "try", "catch",
        "throw", "throws", "rethrows", "async", "await", "actor", "static",
        "private", "public", "internal", "fileprivate", "open", "final",
        "override", "where", "as", "is", "some", "any", "lazy", "weak",
        "unowned", "mutating", "nonisolated", "defer", "typealias",
        "associatedtype", "subscript", "convenience", "required", "indirect",
        "repeat", "fallthrough", "inout", "get", "set", "willSet", "didSet",
    ]

    private static let cFamilyKeywords: Set<String> = [
        "function", "const", "let", "var", "if", "else", "return", "for",
        "while", "switch", "case", "default", "break", "continue", "import",
        "export", "from", "class", "extends", "new", "this", "null",
        "undefined", "true", "false", "in", "of", "do", "try", "catch",
        "finally", "throw", "async", "await", "static", "get", "set",
        "typeof", "instanceof", "void", "delete", "yield", "interface",
        "type", "enum", "implements", "declare", "readonly", "public",
        "private", "protected", "abstract", "namespace", "module", "require",
        "struct", "int", "char", "long", "short", "unsigned", "signed",
        "float", "double", "bool", "fn", "impl", "pub", "mut", "use", "mod",
        "match", "loop", "func", "package", "go", "chan", "defer", "range",
        "nil", "def", "self",
    ]

    private static let pythonKeywords: Set<String> = [
        "def", "return", "if", "elif", "else", "for", "while", "import",
        "from", "class", "try", "except", "finally", "raise", "with", "as",
        "pass", "break", "continue", "lambda", "global", "nonlocal", "yield",
        "async", "await", "True", "False", "None", "not", "and", "or", "in",
        "is", "del", "assert", "self",
    ]

    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "do", "done",
        "case", "esac", "function", "local", "export", "return", "echo",
        "cd", "source", "set", "unset", "readonly", "shift", "exit", "trap",
    ]

    private static let jsonKeywords: Set<String> = ["true", "false", "null"]
}

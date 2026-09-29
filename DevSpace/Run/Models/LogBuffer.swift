import Foundation

nonisolated enum LogChange: Equatable, Sendable {
    case append([LogLine])
    case replaceLast(LogLine)
    case dropFirst(Int)
    case clear
}

nonisolated struct LogBuffer: Sendable {
    let capacity: Int
    private(set) var lines: [LogLine] = []
    private var cursorAtStart = false

    init(capacity: Int = 20_000) {
        self.capacity = capacity
    }

    var plainText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    mutating func apply(_ events: [ANSIParser.Event]) -> [LogChange] {
        let initialCount = lines.count
        var changes: [LogChange] = []
        for event in events {
            switch event {
            case .text(let text, let style):
                openLineIfNeeded(&changes)
                let last = lines.count - 1
                if cursorAtStart {
                    lines[last] = LogLine()
                    cursorAtStart = false
                }
                lines[last].append(text, style: style)
                Self.record(.replaceLast(lines[last]), into: &changes)
            case .newline:
                openLineIfNeeded(&changes)
                lines.append(LogLine())
                cursorAtStart = false
                Self.record(.append([LogLine()]), into: &changes)
            case .carriageReturn:
                cursorAtStart = true
            case .eraseToEnd:
                if cursorAtStart { clearOpenLine(&changes) }
            case .eraseLine:
                clearOpenLine(&changes)
            }
        }

        let overflow = lines.count - capacity
        guard overflow > 0 else { return changes }
        lines.removeFirst(overflow)
        if overflow >= initialCount { return [.clear, .append(lines)] }
        return [.dropFirst(overflow)] + changes
    }

    mutating func clear() -> [LogChange] {
        lines = []
        cursorAtStart = false
        return [.clear]
    }

    private mutating func openLineIfNeeded(_ changes: inout [LogChange]) {
        guard lines.isEmpty else { return }
        lines.append(LogLine())
        Self.record(.append([LogLine()]), into: &changes)
    }

    private mutating func clearOpenLine(_ changes: inout [LogChange]) {
        guard let last = lines.indices.last, !lines[last].spans.isEmpty else { return }
        lines[last] = LogLine()
        Self.record(.replaceLast(LogLine()), into: &changes)
    }

    private static func record(_ change: LogChange, into changes: inout [LogChange]) {
        guard let previous = changes.last else {
            changes.append(change)
            return
        }
        switch (previous, change) {
        case (.append, .replaceLast(let line)):
            guard case .append(var lines) = changes.removeLast() else { return }
            lines[lines.count - 1] = line
            changes.append(.append(lines))
        case (.replaceLast, .replaceLast):
            changes[changes.count - 1] = change
        case (.append, .append(let more)):
            guard case .append(var lines) = changes.removeLast() else { return }
            lines.append(contentsOf: more)
            changes.append(.append(lines))
        default:
            changes.append(change)
        }
    }
}

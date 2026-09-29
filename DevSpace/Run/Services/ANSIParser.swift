import Foundation

nonisolated struct ANSIParser {
    nonisolated enum Event: Equatable, Sendable {
        case text(String, LogStyle)
        case newline
        case carriageReturn
        case eraseToEnd
        case eraseLine
    }

    private enum State {
        case ground, escape, escapeIntermediate, csi, osc, oscEscape
    }

    private(set) var style = LogStyle()
    private var state = State.ground
    private var pendingText: [UInt8] = []
    private var parameters: [UInt8] = []
    private var events: [Event] = []

    mutating func feed(_ data: Data) -> [Event] {
        for byte in data { consume(byte) }
        flushText(keepingIncomplete: true)
        return takeEvents()
    }

    mutating func finish() -> [Event] {
        flushText(keepingIncomplete: false)
        return takeEvents()
    }

    private mutating func takeEvents() -> [Event] {
        let taken = events
        events = []
        return taken
    }

    private mutating func consume(_ byte: UInt8) {
        switch state {
        case .ground:
            ground(byte)
        case .escape:
            switch byte {
            case 0x5B:
                parameters = []
                state = .csi
            case 0x5D:
                state = .osc
            case 0x20...0x2F:
                state = .escapeIntermediate
            default:
                state = .ground
            }
        case .escapeIntermediate:
            if !(0x20...0x2F).contains(byte) { state = .ground }
        case .csi:
            switch byte {
            case 0x30...0x3F:
                parameters.append(byte)
            case 0x40...0x7E:
                dispatchCSI(final: byte)
                state = .ground
            default:
                break
            }
        case .osc:
            if byte == 0x07 {
                state = .ground
            } else if byte == 0x1B {
                state = .oscEscape
            }
        case .oscEscape:
            state = byte == 0x5C ? .ground : .osc
        }
    }

    private mutating func ground(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            flushText(keepingIncomplete: false)
            state = .escape
        case 0x0A:
            flushText(keepingIncomplete: false)
            events.append(.newline)
        case 0x0D:
            flushText(keepingIncomplete: false)
            events.append(.carriageReturn)
        case 0x09:
            pendingText.append(byte)
        case 0x00..<0x20, 0x7F:
            break
        default:
            pendingText.append(byte)
        }
    }

    private mutating func dispatchCSI(final: UInt8) {
        if let first = parameters.first, (0x3C...0x3F).contains(first) { return }
        let values = parameters
            .split(omittingEmptySubsequences: false) { $0 == 0x3B || $0 == 0x3A }
            .map { Int(String(decoding: $0, as: UTF8.self)) }
        let first = values.first.flatMap { $0 }
        switch final {
        case 0x6D:
            applySGR(values.map { $0 ?? 0 })
        case 0x4B:
            events.append(first == nil || first == 0 ? .eraseToEnd : .eraseLine)
        case 0x47:
            if (first ?? 1) <= 1 { events.append(.carriageReturn) }
        default:
            break
        }
    }

    private mutating func applySGR(_ codes: [Int]) {
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = LogStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 22:
                style.bold = false
                style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .palette(UInt8(code - 30))
            case 39: style.foreground = nil
            case 40...47: style.background = .palette(UInt8(code - 40))
            case 49: style.background = nil
            case 90...97: style.foreground = .palette(UInt8(code - 90 + 8))
            case 100...107: style.background = .palette(UInt8(code - 100 + 8))
            case 38, 48:
                let (color, consumed) = Self.extendedColor(codes, after: index)
                if let color {
                    if code == 38 { style.foreground = color } else { style.background = color }
                }
                index += consumed
            default:
                break
            }
            index += 1
        }
    }

    private static func extendedColor(_ codes: [Int], after index: Int) -> (LogColor?, Int) {
        guard index + 1 < codes.count else { return (nil, 0) }
        switch codes[index + 1] {
        case 5:
            guard index + 2 < codes.count else { return (nil, 1) }
            return (.palette(clamp(codes[index + 2])), 2)
        case 2:
            guard index + 4 < codes.count else { return (nil, codes.count - index - 1) }
            return (.rgb(clamp(codes[index + 2]), clamp(codes[index + 3]), clamp(codes[index + 4])), 4)
        default:
            return (nil, 1)
        }
    }

    private static func clamp(_ value: Int) -> UInt8 {
        UInt8(max(0, min(255, value)))
    }

    private mutating func flushText(keepingIncomplete: Bool) {
        guard !pendingText.isEmpty else { return }
        let cut = keepingIncomplete ? Self.completeLength(pendingText) : pendingText.count
        guard cut > 0 else { return }
        let text = String(decoding: pendingText[..<cut], as: UTF8.self)
        pendingText.removeFirst(cut)
        if case .text(let previous, let previousStyle)? = events.last, previousStyle == style {
            events[events.count - 1] = .text(previous + text, style)
        } else {
            events.append(.text(text, style))
        }
    }

    static func completeLength(_ bytes: [UInt8]) -> Int {
        var index = bytes.count - 1
        var continuation = 0
        while index >= 0, continuation < 3, bytes[index] & 0xC0 == 0x80 {
            continuation += 1
            index -= 1
        }
        guard index >= 0 else { return bytes.count }
        let expected: Int
        switch bytes[index] {
        case 0xC0...0xDF: expected = 2
        case 0xE0...0xEF: expected = 3
        case 0xF0...0xF7: expected = 4
        default: return bytes.count
        }
        return continuation + 1 < expected ? index : bytes.count
    }
}

import AppKit

nonisolated enum LogPalette {
    struct RGB: Equatable, Sendable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
    }

    static let light: [UInt32] = [
        0x000000, 0xCD3131, 0x00BC00, 0x949800, 0x0451A5, 0xBC05BC, 0x0598BC, 0x555555,
        0x666666, 0xCD3131, 0x14CE14, 0xB5BA00, 0x0451A5, 0xBC05BC, 0x0598BC, 0xA5A5A5,
    ]

    static let dark: [UInt32] = [
        0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
        0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x3B8EEA, 0xD670D6, 0x29B8DB, 0xE5E5E5,
    ]

    static func rgb(forIndex index: UInt8) -> RGB {
        switch index {
        case 0..<16:
            return rgb(hex: light[Int(index)])
        case 16...231:
            let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
            let offset = Int(index) - 16
            return RGB(red: levels[offset / 36], green: levels[(offset / 6) % 6], blue: levels[offset % 6])
        default:
            let value = UInt8(8 + (Int(index) - 232) * 10)
            return RGB(red: value, green: value, blue: value)
        }
    }

    static func rgb(hex: UInt32) -> RGB {
        RGB(red: UInt8((hex >> 16) & 0xFF), green: UInt8((hex >> 8) & 0xFF), blue: UInt8(hex & 0xFF))
    }

    static func color(_ rgb: RGB) -> NSColor {
        NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
                blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}

struct LogRenderer {
    static let fontSize: CGFloat = 11

    private static let standard: [NSColor] = (0..<16).map { index in
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return LogPalette.color(LogPalette.rgb(hex: dark ? LogPalette.dark[index] : LogPalette.light[index]))
        }
    }

    let regular = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    let bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

    var separator: NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: regular])
    }

    func render(_ line: LogLine) -> NSAttributedString {
        let level = LogHighlighter.level(of: line.text)
        let result = NSMutableAttributedString()
        var plainRanges: [NSRange] = []
        for span in line.spans {
            let start = result.length
            result.append(NSAttributedString(string: span.text,
                                             attributes: attributes(for: span.style, level: level)))
            if span.style.foreground == nil, !span.style.inverse {
                plainRanges.append(NSRange(location: start, length: result.length - start))
            }
        }
        if level == .info {
            for keyword in LogHighlighter.infoRanges(in: result.string) {
                for plain in plainRanges {
                    let overlap = NSIntersectionRange(keyword, plain)
                    guard overlap.length > 0 else { continue }
                    result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: overlap)
                }
            }
        }
        return result
    }

    func attributes(for style: LogStyle, level: LogLevel? = nil) -> [NSAttributedString.Key: Any] {
        var font = style.bold ? bold : regular
        if style.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        let highlight = style.inverse ? nil : Self.color(for: level)
        var foreground = style.foreground.map { Self.color($0) } ?? highlight ?? .textColor
        var background = style.background.map { Self.color($0) }
        if style.inverse {
            let swapped = foreground
            foreground = background ?? .textBackgroundColor
            background = swapped
        }
        if style.dim { foreground = foreground.withAlphaComponent(0.6) }
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        if let background { attributes[.backgroundColor] = background }
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    static func color(for level: LogLevel?) -> NSColor? {
        switch level {
        case .error?: color(.palette(1))
        case .warning?: color(.palette(3))
        case .debug?: .secondaryLabelColor
        case .info?, nil: nil
        }
    }

    static func color(_ color: LogColor) -> NSColor {
        switch color {
        case .rgb(let red, let green, let blue):
            return LogPalette.color(LogPalette.RGB(red: red, green: green, blue: blue))
        case .palette(let index):
            return index < 16 ? standard[Int(index)] : LogPalette.color(LogPalette.rgb(forIndex: index))
        }
    }
}

final class LogDocument {
    private let storage: NSMutableAttributedString
    private let renderer: LogRenderer
    private var lengths: [Int] = []

    init(storage: NSMutableAttributedString, renderer: LogRenderer = LogRenderer()) {
        self.storage = storage
        self.renderer = renderer
    }

    func reload(_ lines: [LogLine]) {
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString())
        lengths = []
        append(lines)
        storage.endEditing()
    }

    func apply(_ changes: [LogChange]) {
        storage.beginEditing()
        for change in changes {
            switch change {
            case .append(let lines): append(lines)
            case .replaceLast(let line): replaceLast(line)
            case .dropFirst(let count): dropFirst(count)
            case .clear:
                storage.setAttributedString(NSAttributedString())
                lengths = []
            }
        }
        storage.endEditing()
    }

    private func append(_ lines: [LogLine]) {
        let chunk = NSMutableAttributedString()
        for line in lines {
            if !lengths.isEmpty { chunk.append(renderer.separator) }
            let rendered = renderer.render(line)
            chunk.append(rendered)
            lengths.append(rendered.length)
        }
        storage.append(chunk)
    }

    private func replaceLast(_ line: LogLine) {
        guard let last = lengths.last else {
            append([line])
            return
        }
        let rendered = renderer.render(line)
        storage.replaceCharacters(in: NSRange(location: storage.length - last, length: last), with: rendered)
        lengths[lengths.count - 1] = rendered.length
    }

    private func dropFirst(_ count: Int) {
        let count = min(count, lengths.count)
        guard count > 0 else { return }
        let separators = count < lengths.count ? count : count - 1
        let removed = lengths.prefix(count).reduce(0, +) + separators
        storage.deleteCharacters(in: NSRange(location: 0, length: removed))
        lengths.removeFirst(count)
    }
}

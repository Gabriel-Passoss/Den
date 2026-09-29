import SwiftUI

struct InlineCode: TextAttribute {
    static let padding: CGFloat = 3

    static let color = Color(.inlineCode)

    struct Segment {
        var content: AttributedString
        let isCode: Bool
    }

    static func text(_ content: AttributedString, size: CGFloat,
                     weight: Font.Weight = .regular) -> Text {
        let segments = segments(of: content, size: size, weight: weight)
        guard segments.contains(where: \.isCode) else {
            return Text(content).font(.system(size: size, weight: weight))
        }
        var interpolation = LocalizedStringKey.StringInterpolation(
            literalCapacity: 0, interpolationCount: segments.count)
        for segment in segments {
            let piece = Text(segment.content)
            interpolation.appendInterpolation(segment.isCode ? piece.customAttribute(InlineCode()) : piece)
        }
        return Text(LocalizedStringKey(stringInterpolation: interpolation))
            .font(.system(size: size, weight: weight))
    }

    static func segments(of content: AttributedString, size: CGFloat,
                         weight: Font.Weight = .regular) -> [Segment] {
        var segments: [Segment] = []
        for (intent, range) in content.runs[\.inlinePresentationIntent] {
            var slice = AttributedString(content[range])
            let isCode = intent?.contains(.code) == true
            if let intent, isCode {
                let font = Font.system(size: size - 1,
                                       weight: intent.contains(.stronglyEmphasized) ? .semibold : weight,
                                       design: .monospaced)
                slice.font = intent.contains(.emphasized) ? font.italic() : font
                slice.foregroundColor = color
            }
            if let last = segments.indices.last, segments[last].isCode == isCode {
                segments[last].content += slice
            } else {
                segments.append(Segment(content: slice, isCode: isCode))
            }
        }
        for index in segments.indices where segments[index].isCode {
            padTrailingCharacter(of: &segments[index].content)
            if index > 0 { padTrailingCharacter(of: &segments[index - 1].content) }
        }
        return segments
    }

    static func pills(in line: [(bounds: CGRect, isCode: Bool)]) -> [CGRect] {
        var pills: [CGRect] = []
        var current: CGRect?
        for run in line {
            if run.isCode {
                current = current?.union(run.bounds) ?? run.bounds
            } else if let pill = current {
                pills.append(pill)
                current = nil
            }
        }
        if let current { pills.append(current) }
        return pills.map { pill in
            CGRect(x: pill.minX - padding, y: pill.minY,
                   width: pill.width + padding, height: pill.height)
        }
    }

    private static func padTrailingCharacter(of text: inout AttributedString) {
        guard !text.characters.isEmpty else { return }
        let last = text.characters.index(before: text.endIndex)
        text[last..<text.endIndex][AttributeScopes.SwiftUIAttributes.KerningAttribute.self] = padding
    }
}

struct InlineCodeRenderer: TextRenderer {
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 1, leading: InlineCode.padding, bottom: 1, trailing: InlineCode.padding)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            let runs = line.map { (bounds: $0.typographicBounds.rect, isCode: $0[InlineCode.self] != nil) }
            for rect in InlineCode.pills(in: runs) {
                let pill = RoundedRectangle(cornerRadius: 4, style: .continuous).path(in: rect)
                context.fill(pill, with: .color(InlineCode.color.opacity(0.10)))
                context.stroke(pill, with: .color(InlineCode.color.opacity(0.25)), lineWidth: 0.5)
            }
        }
        for line in layout {
            context.draw(line)
        }
    }
}

import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Self.blocks(for: text)) { block in
                render(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block.kind {
        case .paragraph(let content):
            Text(content)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let content):
            Text(content)
                .font(.system(size: Self.headingSize(level), weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

        case .code(let code):
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

        case .listItem(let marker, let depth, let content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 14, alignment: .trailing)
                Text(content)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(max(0, depth - 1)) * 16)

        case .quote(let content):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.tertiary)
                    .frame(width: 3)
                Text(content)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .divider:
            Divider()
        }
    }

    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 17
        case 2: 15
        default: 13.5
        }
    }

    // MARK: - Parsing

    struct Block: Identifiable {
        let id: Int
        let kind: Kind

        enum Kind {
            case paragraph(AttributedString)
            case heading(Int, AttributedString)
            case code(String)
            case listItem(marker: String, depth: Int, AttributedString)
            case quote(AttributedString)
            case divider
        }
    }

    private final class Parsed {
        let blocks: [Block]
        init(_ blocks: [Block]) { self.blocks = blocks }
    }

    private static let cache: NSCache<NSString, Parsed> = {
        let cache = NSCache<NSString, Parsed>()
        cache.countLimit = 240
        return cache
    }()

    static func blocks(for text: String) -> [Block] {
        let key = text as NSString
        if let hit = cache.object(forKey: key) { return hit.blocks }
        let parsed = parse(text)
        cache.setObject(Parsed(parsed), forKey: key)
        return parsed
    }

    static func parse(_ text: String) -> [Block] {
        guard let whole = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .full,
                           failurePolicy: .returnPartiallyParsedIfPossible)
        ) else {
            return [Block(id: 0, kind: .paragraph(AttributedString(text)))]
        }

        var groups: [(intent: PresentationIntent?, content: AttributedString)] = []
        for run in whole.runs {
            let intent = run.presentationIntent
            var slice = AttributedString(whole[run.range])
            slice.presentationIntent = nil
            if !groups.isEmpty, groups[groups.count - 1].intent == intent {
                groups[groups.count - 1].content += slice
            } else {
                groups.append((intent, slice))
            }
        }

        var blocks: [Block] = []
        var seenListItems: Set<Int> = []
        for (index, group) in groups.enumerated() {
            guard let kind = kind(of: group.intent, content: group.content,
                                  seenListItems: &seenListItems) else { continue }
            blocks.append(Block(id: index, kind: kind))
        }
        return blocks
    }

    private static func kind(of intent: PresentationIntent?,
                             content: AttributedString,
                             seenListItems: inout Set<Int>) -> Block.Kind? {
        let plain = String(content.characters)
        guard let intent else {
            return plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : .paragraph(content)
        }

        var listDepth = 0
        var ordinal: Int?
        var listItemIdentity: Int?
        var isOrdered = false
        var isQuote = false

        for component in intent.components {
            switch component.kind {
            case .header(let level):
                return .heading(level, content)
            case .codeBlock:
                let trimmed = plain.trimmingCharacters(in: .newlines)
                return trimmed.isEmpty ? nil : .code(trimmed)
            case .thematicBreak:
                return .divider
            case .blockQuote:
                isQuote = true
            case .orderedList:
                listDepth += 1
                isOrdered = listDepth == 1 ? true : isOrdered
            case .unorderedList:
                listDepth += 1
            case .listItem(let number):
                if listItemIdentity == nil {
                    listItemIdentity = component.identity
                    ordinal = number
                }
            default:
                break
            }
        }

        if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if listDepth > 0 {
            let firstOfItem = listItemIdentity.map { seenListItems.insert($0).inserted } ?? true
            let marker = !firstOfItem ? "" : isOrdered ? "\(ordinal ?? 1)." : "•"
            return .listItem(marker: marker, depth: listDepth, content)
        }
        if isQuote { return .quote(content) }
        return .paragraph(content)
    }
}

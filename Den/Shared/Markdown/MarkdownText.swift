import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.blocks(for: text)) { block in
                render(block)
            }
        }
        .textRenderer(InlineCodeRenderer())
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block.kind {
        case .table(let table):
            MarkdownTableView(table: table)

        case .paragraph(let content):
            InlineCode.text(content, size: 14)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let content):
            InlineCode.text(content, size: Self.headingSize(level), weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

        case .code(let code, let language):
            CodeBlock(code: code, language: language)

        case .listItem(let marker, let depth, let content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(minWidth: 14, alignment: .trailing)
                InlineCode.text(content, size: 14)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(max(0, depth - 1)) * 16)

        case .quote(let content):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.borderControl)
                    .frame(width: 3)
                InlineCode.text(content, size: 14)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .divider:
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 19
        case 2: 16.5
        default: 14.5
        }
    }

    struct CodeLine: Identifiable {
        let id: Int
        let text: AttributedString
    }

    static func highlighted(_ code: String, language: String?) -> [CodeLine] {
        let kind = SyntaxHighlighter.language(forHint: language)
        return code.components(separatedBy: "\n").enumerated().map { index, line in
            CodeLine(id: index,
                     text: kind == .plain ? AttributedString(line)
                                          : SyntaxHighlighter.highlight(line, language: kind))
        }
    }

    // MARK: - Parsing

    struct Block: Identifiable {
        let id: Int
        let kind: Kind

        enum Kind {
            case table(Table)
            case paragraph(AttributedString)
            case heading(Int, AttributedString)
            case code(String, language: String?)
            case listItem(marker: String, depth: Int, AttributedString)
            case quote(AttributedString)
            case divider
        }
    }

    struct Table {
        var alignments: [PresentationIntent.TableColumn.Alignment]
        var header: [AttributedString]
        var rows: [[AttributedString]]
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
        var table: (identity: Int, value: Table)?

        func flushTable(at index: Int) {
            guard let pending = table else { return }
            blocks.append(Block(id: -index - 1, kind: .table(pending.value)))
            table = nil
        }

        for (index, group) in groups.enumerated() {
            if let cell = tableCell(of: group.intent) {
                if table?.identity != cell.tableIdentity {
                    flushTable(at: index)
                    table = (cell.tableIdentity,
                             Table(alignments: cell.alignments, header: [], rows: []))
                }
                if cell.isHeader {
                    table?.value.header.append(group.content)
                } else {
                    let row = cell.row
                    while (table?.value.rows.count ?? 0) <= row {
                        table?.value.rows.append([])
                    }
                    table?.value.rows[row].append(group.content)
                }
                continue
            }
            flushTable(at: index)
            guard let kind = kind(of: group.intent, content: group.content,
                                  seenListItems: &seenListItems) else { continue }
            blocks.append(Block(id: index, kind: kind))
        }
        flushTable(at: groups.count)
        return blocks
    }

    private struct TableCell {
        let tableIdentity: Int
        let alignments: [PresentationIntent.TableColumn.Alignment]
        let isHeader: Bool
        let row: Int
    }

    private static func tableCell(of intent: PresentationIntent?) -> TableCell? {
        guard let intent else { return nil }
        var identity: Int?
        var alignments: [PresentationIntent.TableColumn.Alignment] = []
        var isHeader = false
        var row = 0
        var isCell = false

        for component in intent.components {
            switch component.kind {
            case .table(let columns):
                identity = component.identity
                alignments = columns.map(\.alignment)
            case .tableHeaderRow:
                isHeader = true
            case .tableRow(let index):
                row = index
            case .tableCell:
                isCell = true
            default:
                break
            }
        }
        guard isCell, let identity else { return nil }
        return TableCell(tableIdentity: identity, alignments: alignments,
                         isHeader: isHeader, row: max(0, row - 1))
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
            case .codeBlock(let languageHint):
                let trimmed = plain.trimmingCharacters(in: .newlines)
                return trimmed.isEmpty ? nil : .code(trimmed, language: languageHint)
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

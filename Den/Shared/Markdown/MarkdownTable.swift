import SwiftUI

@MainActor
@Observable
final class TableScrollLock {
    var isLocked = false
}

struct MarkdownTableView: View {
    let table: MarkdownText.Table

    @Environment(TableScrollLock.self) private var lock: TableScrollLock?

    @State private var content: CGSize = .zero
    @State private var viewport: CGFloat = 0

    private static let maxHeight: CGFloat = 320
    private static let flexibleMin: CGFloat = 150
    private static let flexibleFixed: CGFloat = 260
    private static let compactMin: CGFloat = 70

    var body: some View {
        let columns = max(table.header.count, table.rows.map(\.count).max() ?? 0)
        let compact = Self.compactColumns(table, columns: columns)
        let needed = CGFloat(columns - compact.count) * Self.flexibleMin
            + CGFloat(compact.count) * Self.compactMin
        let sideways = viewport > 0 && needed > viewport
        let tall = content.height > Self.maxHeight
        let scrollable = tall || sideways

        return ScrollView(sideways ? [.horizontal, .vertical] : .vertical) {
            grid(columns: columns, compact: compact, fixedWidths: sideways)
                .onGeometryChange(for: CGSize.self) { proxy in
                    CGSize(width: (proxy.size.width / 4).rounded() * 4,
                           height: (proxy.size.height / 4).rounded() * 4)
                } action: { size in
                    if size != content { content = size }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: content.height > 0 ? min(content.height, Self.maxHeight) : nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.borderCard, lineWidth: 1))
        .padding(.vertical, 2)
        .onGeometryChange(for: CGFloat.self) { proxy in
            (proxy.size.width / 4).rounded() * 4
        } action: { width in
            if width != viewport { viewport = width }
        }
        .onHover { inside in
            lock?.isLocked = inside && scrollable
        }
        .onDisappear { lock?.isLocked = false }
    }

    private func grid(columns: Int, compact: Set<Int>, fixedWidths: Bool) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            if !table.header.isEmpty {
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        cell(table.header, at: column, compact: compact,
                             fixedWidths: fixedWidths, header: true)
                    }
                }
                Rectangle().fill(Theme.border).frame(height: 1).gridCellColumns(columns)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, cells in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        cell(cells, at: column, compact: compact,
                             fixedWidths: fixedWidths, header: false)
                    }
                }
                .background(index.isMultiple(of: 2)
                            ? AnyShapeStyle(.clear)
                            : AnyShapeStyle(Theme.raised))
            }
        }
    }

    @ViewBuilder
    private func cell(_ cells: [AttributedString], at column: Int, compact: Set<Int>,
                      fixedWidths: Bool, header: Bool) -> some View {
        let isCompact = compact.contains(column)
        InlineCode.text(column < cells.count ? cells[column] : AttributedString(""),
                        size: header ? 12 : 13, weight: header ? .semibold : .regular)
            .foregroundStyle(header ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .multilineTextAlignment(Self.textAlignment(table.alignments, at: column))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, header ? 6 : 7)
            .frame(width: fixedWidths && !isCompact ? Self.flexibleFixed : nil,
                   alignment: Self.alignment(table.alignments, at: column))
            .frame(maxWidth: fixedWidths || isCompact ? nil : .infinity,
                   alignment: Self.alignment(table.alignments, at: column))
    }

    private static func compactColumns(_ table: MarkdownText.Table,
                                       columns: Int) -> Set<Int> {
        var compact: Set<Int> = []
        for column in 0..<columns {
            var longest = 0
            for row in ([table.header] + table.rows) where column < row.count {
                longest = max(longest, row[column].characters.count)
            }
            if longest <= 14 { compact.insert(column) }
        }
        return compact.count == columns ? [] : compact
    }

    private static func alignment(_ alignments: [PresentationIntent.TableColumn.Alignment],
                                  at column: Int) -> Alignment {
        guard column < alignments.count else { return .leading }
        return switch alignments[column] {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }

    private static func textAlignment(_ alignments: [PresentationIntent.TableColumn.Alignment],
                                      at column: Int) -> TextAlignment {
        guard column < alignments.count else { return .leading }
        return switch alignments[column] {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }
}

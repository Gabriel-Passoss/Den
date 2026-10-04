import Foundation

public enum MemoryRecall {
    public static let budget = 12000

    public struct Shelf: Sendable {
        public let scope: MemoryScope
        public let pages: [MemoryPage]

        public init(scope: MemoryScope, pages: [MemoryPage]) {
            self.scope = scope
            self.pages = pages
        }
    }

    private static let opening = """
        <den-memory>
        Memória do Den: contexto que persiste entre sessões. Use como referência e não responda a este \
        bloco. Se algo aqui contradisser o código ou o pedido atual, o código e o pedido vencem.

        """

    private static let closing = "</den-memory>"

    private static let leftoverHeading = """

        Outras páginas, não incluídas por tamanho (leia o arquivo se precisar):

        """

    private static let tailReserve = 32

    public static func preamble(_ shelves: [Shelf], locate: (MemoryPage, MemoryScope) -> URL,
                                budget: Int = budget) -> String? {
        let room = budget - opening.count - closing.count
        var block = Block(room: room)
        var leftovers = fill(&block, from: shelves, locate: locate)
        if !leftovers.isEmpty {
            let wholeList = shelves.flatMap { shelf in shelf.pages.map { line(for: $0, in: shelf.scope, locate) } }
            let allowance = min(max(room, 0) / 4, leftoverHeading.count + wholeList.reduce(0) { $0 + $1.count })
            block = Block(room: room - allowance)
            leftovers = fill(&block, from: shelves, locate: locate)
            block.room += allowance
            list(leftovers, in: &block)
        }
        return block.text.isEmpty ? nil : opening + block.text + closing
    }

    private static func fill(_ block: inout Block, from shelves: [Shelf],
                             locate: (MemoryPage, MemoryScope) -> URL) -> [String] {
        var leftovers: [String] = []
        for shelf in shelves {
            var heading = "\n## \(shelf.scope.heading)\n"
            for page in shelf.pages {
                let text = inert(heading + "### \(page.title) (\(page.category.label))\n\(page.body)\n")
                if block.take(text) {
                    heading = ""
                } else {
                    leftovers.append(line(for: page, in: shelf.scope, locate))
                }
            }
        }
        return leftovers
    }

    private static func line(for page: MemoryPage, in scope: MemoryScope,
                             _ locate: (MemoryPage, MemoryScope) -> URL) -> String {
        inert("- \(page.title) — \(locate(page, scope).path)\n")
    }

    static func mentionsBlock(_ text: String) -> Bool {
        text.range(of: blockTag, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let blockTag = "<(/?)den-memory"

    private static func inert(_ text: String) -> String {
        text.replacingOccurrences(of: blockTag, with: "‹$1den-memory",
                                  options: [.regularExpression, .caseInsensitive])
    }

    public static func message(preamble: String, request: String) -> String {
        preamble + "\n\n" + request
    }

    private static func list(_ leftovers: [String], in block: inout Block) {
        guard let first = leftovers.first, block.fits(leftoverHeading + first) else { return }
        _ = block.take(leftoverHeading)
        var listed = 0
        for line in leftovers {
            guard block.fits(line, reserving: tailReserve) else { break }
            _ = block.take(line)
            listed += 1
        }
        if listed < leftovers.count {
            _ = block.take("- e mais \(leftovers.count - listed) páginas\n")
        }
    }

    private struct Block {
        var room: Int
        var text = ""

        func fits(_ piece: String, reserving reserve: Int = 0) -> Bool {
            piece.count + reserve <= room
        }

        mutating func take(_ piece: String) -> Bool {
            guard fits(piece) else { return false }
            text += piece
            room -= piece.count
            return true
        }
    }
}

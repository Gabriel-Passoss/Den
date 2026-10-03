import Foundation
import HarnessCore

extension ChatView {
    static func isUserBlock(_ block: ChatBlock) -> Bool {
        if case .line(let line) = block {
            return line.role == .user || line.role == .compaction
        }
        return false
    }

    static func harness(of block: ChatBlock) -> HarnessID? {
        switch block {
        case .line(let line): line.harness
        case .collapsed(_, let lines): lines.lazy.compactMap(\.harness).first
        }
    }

    static func turnStarts(in blocks: [ChatBlock]) -> Set<UUID> {
        var starts = Set<UUID>()
        var afterUser = true
        var previous: HarnessID?
        for block in blocks {
            if isUserBlock(block) {
                afterUser = true
            } else {
                let author = harness(of: block)
                if afterUser || author != previous { starts.insert(block.id) }
                afterUser = false
                previous = author
            }
        }
        return starts
    }
}

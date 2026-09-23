import Foundation
import HarnessCore

extension ChatModel {
    var blocks: [ChatBlock] {
        var result: [ChatBlock] = []
        var run: [ChatLine] = []
        func flush() {
            guard !run.isEmpty else { return }
            result.append(.collapsed(id: run[0].id, lines: run))
            run = []
        }
        for line in lines {
            if line.role.isStep { run.append(line) }
            else { flush(); result.append(.line(line)) }
        }
        flush()
        return result
    }
}

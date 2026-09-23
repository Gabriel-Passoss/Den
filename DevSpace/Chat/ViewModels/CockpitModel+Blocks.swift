import Foundation
import HarnessCore

extension CockpitModel {
    var blocks: [Block] {
        var result: [Block] = []
        var run: [Line] = []
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

    enum Block: Identifiable {
        case line(Line)
        case collapsed(id: UUID, lines: [Line])
        var id: UUID {
            switch self {
            case .line(let line): return line.id
            case .collapsed(let id, _): return id
            }
        }
    }
}

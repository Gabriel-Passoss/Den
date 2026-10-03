import Foundation

nonisolated enum PullRequestTone: Int, Comparable, Sendable {
    case merged, closed, open, draft, attention, failure

    static func < (lhs: PullRequestTone, rhs: PullRequestTone) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated enum ChecksSummary: Equatable, Sendable {
    case none
    case running(passed: Int, total: Int)
    case passing(total: Int)
    case failing(passed: Int, total: Int)

    var key: String {
        switch self {
        case .none: "none"
        case .running: "running"
        case .passing: "passing"
        case .failing: "failing"
        }
    }
}

nonisolated enum PullRequestStatus {
    static func checks(_ pr: PullRequest) -> ChecksSummary {
        let counted = pr.checks.filter { $0.state != .skipped }
        guard !counted.isEmpty else { return .none }
        let passed = counted.filter { $0.state == .passed }.count
        if counted.contains(where: { $0.state == .failed }) {
            return .failing(passed: passed, total: counted.count)
        }
        if counted.contains(where: { $0.state == .running || $0.state == .queued }) {
            return .running(passed: passed, total: counted.count)
        }
        return .passing(total: counted.count)
    }

    static func tone(_ pr: PullRequest) -> PullRequestTone {
        switch pr.state {
        case .merged: return .merged
        case .closed: return .closed
        case .open: break
        }
        if pr.isDraft { return .draft }
        if case .failing = checks(pr) { return .failure }
        if pr.mergeable == .conflicting || pr.review == .changesRequested { return .attention }
        return .open
    }

    static func worst(_ prs: [PullRequest]) -> PullRequest? {
        prs.max { tone($0) < tone($1) }
    }

    static func signature(_ pr: PullRequest) -> String {
        "\(pr.state.rawValue)|\(pr.isDraft)|\(checks(pr).key)|\(pr.review.rawValue)|\(pr.mergeable.rawValue)"
    }

    static func label(_ pr: PullRequest) -> String {
        switch pr.state {
        case .merged: return "Mergeado"
        case .closed: return "Fechado"
        case .open: break
        }
        if pr.isDraft { return "Rascunho" }
        let summary = checks(pr)
        if case .failing = summary { return "Checks falhando" }
        if pr.mergeable == .conflicting { return "Conflito" }
        if pr.review == .changesRequested { return "Mudanças pedidas" }
        if case .running = summary { return "Checks rodando" }
        if pr.review == .approved { return "Pronto para merge" }
        return "Aberto"
    }

    static func ordered(_ checks: [CheckRun]) -> [CheckRun] {
        let rank: [CheckRun.State: Int] = [.failed: 0, .running: 1, .queued: 2, .passed: 3, .skipped: 4]
        return checks.enumerated().sorted { a, b in
            let left = rank[a.element.state] ?? 5
            let right = rank[b.element.state] ?? 5
            return left == right ? a.offset < b.offset : left < right
        }.map(\.element)
    }

    static func headline(_ pr: PullRequest) -> String {
        let counted = pr.checks.filter { $0.state != .skipped }
        guard !counted.isEmpty else { return "Nenhum check" }
        let failed = counted.filter { $0.state == .failed }.count
        let running = counted.filter { $0.state == .running || $0.state == .queued }.count
        var parts: [String] = []
        if failed > 0 { parts.append(failed == 1 ? "1 falhou" : "\(failed) falharam") }
        if running > 0 { parts.append("\(running) rodando") }
        if parts.isEmpty {
            let passed = counted.filter { $0.state == .passed }.count
            return "\(passed) de \(counted.count) passaram"
        }
        return parts.joined(separator: " · ")
    }

    static func detail(of check: CheckRun, at now: Date) -> String {
        switch check.state {
        case .skipped:
            return "Pulado"
        case .queued:
            return check.workflow.map { "\($0) · na fila" } ?? "Na fila"
        case .running, .passed, .failed:
            guard let start = check.startedAt else { return check.workflow ?? "" }
            let end = check.completedAt ?? now
            let span = duration(max(0, Int(end.timeIntervalSince(start))))
            return check.workflow.map { "\($0) · \(span)" } ?? span
        }
    }

    static func duration(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        return "\(seconds / 60)min " + String(format: "%02ds", seconds % 60)
    }

    static func updatedLabel(since checked: Date?, now: Date) -> String {
        guard let checked else { return "Ainda não atualizado" }
        let seconds = max(0, Int(now.timeIntervalSince(checked)))
        return seconds < 60 ? "Atualizado há \(seconds)s" : "Atualizado há \(seconds / 60) min"
    }
}

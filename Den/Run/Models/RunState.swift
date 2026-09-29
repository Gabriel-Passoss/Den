import Foundation

nonisolated enum RunIndicator: Equatable, Sendable {
    case idle
    case busy
    case running
    case failed
}

nonisolated enum RunState: Equatable, Sendable {
    case starting
    case running(pid: Int32)
    case stopping
    case stopped
    case exited(ProcessExit)
    case failed(String)

    static let neverStartedLabel = "Não iniciada"

    var indicator: RunIndicator {
        switch self {
        case .stopped, .exited(.code(0)): .idle
        case .starting, .stopping: .busy
        case .running: .running
        case .exited, .failed: .failed
        }
    }

    var isActive: Bool {
        indicator == .busy || indicator == .running
    }

    func label(startedAt: Date, now: Date) -> String {
        switch self {
        case .starting: "Iniciando…"
        case .running: "Rodando · \(Self.elapsed(from: startedAt, to: now))"
        case .stopping: "Parando…"
        case .stopped: "Parado"
        case .exited(.code(0)): "Encerrado"
        case .exited(.code(let code)): "Saiu com código \(code)"
        case .exited(.signal(let signal)): "Encerrado pelo sinal \(signal)"
        case .failed(let message): "Falhou: \(message)"
        }
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(start)) / 60
        if minutes < 1 { return "agora" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

import Foundation

public protocol HarnessSession: Actor {

    func start(_ start: SessionStart) async throws -> AsyncStream<SessionUpdate>

    func send(_ turn: UserTurn) async throws

    func resolve(_ requestID: String, _ decision: PermissionDecision) async throws

    func interrupt() async throws

    func apply(knob id: String, value: String?) async throws

    func knobs() async -> [HarnessKnob]

    func stop() async
}

public protocol Harness: Sendable {

    var id: HarnessID { get }

    var displayName: String { get }

    func discover() async throws -> HarnessInstallation

    func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities

    func knobs(for installation: HarnessInstallation,
               workingDirectory: URL) -> [HarnessKnob]

    func makeSession(installation: HarnessInstallation,
                     workingDirectory: URL,
                     settings: [String: String]) -> any HarnessSession

    /// Argumentos de um turno único e barato, usado para batizar a sessão.
    /// `nil` quando o CLI não oferece um caminho não interativo confiável —
    /// aí o título curto do primeiro pedido continua valendo.
    func titleArguments(for instruction: String) -> [String]?
}

public extension Harness {
    func titleArguments(for instruction: String) -> [String]? { nil }
}

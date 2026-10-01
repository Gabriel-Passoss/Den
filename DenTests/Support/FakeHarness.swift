import Foundation
import HarnessCore
@testable import Den

struct HarnessFailure: Error, Equatable {
    let reason: String
}

/// Shared scratch space between the harness (a value type the protocol requires
/// to be Sendable) and the test that inspects it.
final class HarnessLog: @unchecked Sendable {
    var madeSessions = 0
    var lastSettings: [String: String] = [:]
    var lastWorkingDirectory: URL?
}

actor FakeSession: HarnessSession {
    private(set) var starts: [SessionStart] = []
    private(set) var sent: [UserTurn] = []
    private(set) var decisions: [(request: String, decision: PermissionDecision)] = []
    private(set) var appliedKnobs: [(id: String, value: String?)] = []
    private(set) var interrupts = 0
    private(set) var stops = 0
    private(set) var usageRequests = 0

    private var offered: [HarnessKnob] = []
    private var offeredUsage: ContextUsage?
    private var stream: AsyncStream<SessionUpdate>.Continuation?

    var sendFailure: HarnessFailure?
    var applyFailure: HarnessFailure?
    var resolveFailure: HarnessFailure?

    func offer(knobs: [HarnessKnob]) { offered = knobs }
    func offer(usage: ContextUsage?) { offeredUsage = usage }
    func failSend(_ failure: HarnessFailure?) { sendFailure = failure }
    func failApply(_ failure: HarnessFailure?) { applyFailure = failure }
    func failResolve(_ failure: HarnessFailure?) { resolveFailure = failure }

    func start(_ start: SessionStart) async throws -> AsyncStream<SessionUpdate> {
        starts.append(start)
        let (stream, continuation) = AsyncStream<SessionUpdate>.makeStream()
        self.stream = continuation
        return stream
    }

    func emit(_ update: SessionUpdate) { stream?.yield(update) }

    func finish() { stream?.finish() }

    func send(_ turn: UserTurn) async throws {
        if let sendFailure { throw sendFailure }
        sent.append(turn)
    }

    func resolve(_ requestID: String, _ decision: PermissionDecision) async throws {
        if let resolveFailure { throw resolveFailure }
        decisions.append((requestID, decision))
    }

    func interrupt() async throws { interrupts += 1 }

    func apply(knob id: String, value: String?) async throws {
        if let applyFailure { throw applyFailure }
        appliedKnobs.append((id, value))
    }

    func knobs() async -> [HarnessKnob] { offered }

    func contextUsage() async -> ContextUsage? {
        usageRequests += 1
        return offeredUsage
    }

    func stop() async {
        stops += 1
        stream?.finish()
    }
}

struct FakeHarness: Harness {
    let id: HarnessID
    let displayName: String
    let session: FakeSession
    let log: HarnessLog
    var declaredCapabilities = HarnessCapabilities()
    var declaredKnobs: [HarnessKnob] = []
    var discoveryFailure: HarnessFailure?

    init(id: String = "fake", displayName: String = "Fake",
         session: FakeSession = FakeSession(), log: HarnessLog = HarnessLog()) {
        self.id = HarnessID(rawValue: id)
        self.displayName = displayName
        self.session = session
        self.log = log
    }

    func discover() async throws -> HarnessInstallation {
        if let discoveryFailure { throw discoveryFailure }
        return HarnessInstallation(executable: "/fake/bin/harness", version: "1.0.0")
    }

    func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities {
        declaredCapabilities
    }

    func knobs(for installation: HarnessInstallation,
               workingDirectory: URL) -> [HarnessKnob] {
        declaredKnobs
    }

    func makeSession(installation: HarnessInstallation, workingDirectory: URL,
                     settings: [String: String]) -> any HarnessSession {
        log.madeSessions += 1
        log.lastSettings = settings
        log.lastWorkingDirectory = workingDirectory
        return session
    }
}

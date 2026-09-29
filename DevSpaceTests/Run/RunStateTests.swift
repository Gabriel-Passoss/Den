import Testing
import Foundation
import Darwin
@testable import DevSpace

private let start = Date(timeIntervalSince1970: 1_000_000)

private func label(_ state: RunState, after seconds: TimeInterval = 0) -> String {
    state.label(startedAt: start, now: start.addingTimeInterval(seconds))
}

@Test func labelsDescribeEachState() {
    #expect(RunState.neverStartedLabel == "Não iniciada")
    #expect(label(.starting) == "Iniciando…")
    #expect(label(.running(pid: 1), after: 30) == "Rodando · agora")
    #expect(label(.running(pid: 1), after: 12 * 60) == "Rodando · 12 min")
    #expect(label(.running(pid: 1), after: 3_700) == "Rodando · 1 h 1 min")
    #expect(label(.running(pid: 1), after: 7_200) == "Rodando · 2 h")
    #expect(label(.stopping) == "Parando…")
    #expect(label(.stopped) == "Parado")
    #expect(label(.exited(.code(0))) == "Encerrado")
    #expect(label(.exited(.code(2))) == "Saiu com código 2")
    #expect(label(.exited(.signal(9))) == "Encerrado pelo sinal 9")
    #expect(label(.failed("A pasta /x não existe")) == "Falhou: A pasta /x não existe")
}

@Test func indicatorsFollowTheState() {
    #expect(RunState.starting.indicator == .busy)
    #expect(RunState.running(pid: 1).indicator == .running)
    #expect(RunState.stopping.indicator == .busy)
    #expect(RunState.stopped.indicator == .idle)
    #expect(RunState.exited(.code(0)).indicator == .idle)
    #expect(RunState.exited(.code(1)).indicator == .failed)
    #expect(RunState.exited(.signal(SIGSEGV)).indicator == .failed)
    #expect(RunState.failed("x").indicator == .failed)
}

@Test func onlyStartingRunningAndStoppingAreActive() {
    let active: [RunState] = [.starting, .running(pid: 1), .stopping]
    let inactive: [RunState] = [.stopped, .exited(.code(0)), .exited(.signal(9)), .failed("x")]
    #expect(active.allSatisfy { $0.isActive })
    #expect(!inactive.contains { $0.isActive })
}

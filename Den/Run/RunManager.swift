import Foundation
import Observation

@MainActor
@Observable
final class RunManager {
    private(set) var instances: [UUID: RunInstance] = [:]

    @ObservationIgnored private var processes: [UUID: any RunningProcess] = [:]
    @ObservationIgnored private var exits: [UUID: ExitLatch] = [:]
    @ObservationIgnored private var discarded: Set<UUID> = []
    @ObservationIgnored private var stops: [UUID: (generation: Int, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private let launcher: any ProcessLaunching
    @ObservationIgnored private let environment: ShellEnvironment
    @ObservationIgnored private let stopGrace: Duration
    @ObservationIgnored private let logInterval: Duration

    init(launcher: any ProcessLaunching = PTYLauncher(),
         environment: ShellEnvironment = .shared,
         stopGrace: Duration = .seconds(5),
         logInterval: Duration = .milliseconds(60)) {
        self.launcher = launcher
        self.environment = environment
        self.stopGrace = stopGrace
        self.logInterval = logInterval
    }

    var hasActiveProcesses: Bool { !processes.isEmpty || !stops.isEmpty }

    func instance(for id: UUID) -> RunInstance? { instances[id] }

    func isActive(_ id: UUID) -> Bool { instances[id]?.isActive == true }

    func start(_ configuration: RunConfiguration, in root: URL) async {
        guard case .command(let spec) = configuration.kind else { return }
        let id = configuration.id
        guard !discarded.contains(id) else { return }
        let instance = instances[id] ?? RunInstance(configurationID: id)
        instances[id] = instance
        if instance.isActive { await stop(id) }
        guard !discarded.contains(id) else { return }
        let generation = instance.begin()
        processes[id] = nil
        exits[id] = nil

        let shell = await environment.resolve()
        guard instance.generation == generation, !discarded.contains(id) else { return }
        if let warning = shell.warning { instance.appendNotice(warning) }

        let directory = spec.resolvedDirectory(in: root)
        guard directory.isExistingDirectory else {
            instance.fail("A pasta \(directory.path) não existe")
            return
        }

        let request = LaunchRequest(
            shell: shell.shell, command: spec.command, directory: directory,
            environment: shell.processEnvironment(overrides: spec.environment))
        let intake = LogIntake(interval: logInterval) { [weak instance] events in
            instance?.receive(events, generation: generation)
        }
        let latch = ExitLatch()
        do {
            let process = try launcher.launch(
                request,
                onOutput: { intake.receive($0) },
                onExit: { [weak self] status in
                    latch.record(status)
                    intake.finish { [weak self] in self?.processExited(id, status: status, generation: generation) }
                })
            processes[id] = process
            exits[id] = latch
            instance.markRunning(pid: process.pid)
        } catch {
            instance.fail((error as? LaunchError)?.message
                          ?? "Não consegui iniciar o processo: \(error.localizedDescription)")
        }
    }

    func stop(_ id: UUID, grace: Duration? = nil) async {
        guard let instance = instances[id] else { return }
        if let pending = stops[id], pending.generation == instance.generation {
            await pending.task.value
            return
        }
        guard instance.isActive else { return }
        guard let process = processes[id] else {
            instance.markStopped()
            return
        }
        let generation = instance.generation
        if let status = exits[id]?.status {
            processExited(id, status: status, generation: generation)
            return
        }
        instance.markStopping()
        let grace = grace ?? stopGrace
        let termination = Task { await process.terminate(grace: grace) }
        stops[id] = (generation, termination)
        await termination.value
        if stops[id]?.generation == generation { stops[id] = nil }
        instance.settleStop(generation: generation)
    }

    func stopAll(grace: Duration) async {
        let ids = Array(instances.keys)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { await self.stop(id, grace: grace) }
            }
        }
    }

    func discard(_ id: UUID) async {
        discarded.insert(id)
        await stop(id)
        instances[id] = nil
    }

    private func processExited(_ id: UUID, status: ProcessExit, generation: Int) {
        guard instances[id]?.finish(status, generation: generation) == true else { return }
        processes[id] = nil
        exits[id] = nil
    }
}

nonisolated private final class ExitLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: ProcessExit?

    var status: ProcessExit? { lock.withLock { recorded } }

    func record(_ status: ProcessExit) {
        lock.withLock { if recorded == nil { recorded = status } }
    }
}

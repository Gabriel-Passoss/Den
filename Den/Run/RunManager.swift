import Foundation
import Observation

@MainActor
@Observable
final class RunManager {
    private(set) var instances: [UUID: RunInstance] = [:]

    @ObservationIgnored private var processes: [UUID: any RunningProcess] = [:]
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
        let instance = instances[id] ?? RunInstance(configurationID: id)
        instances[id] = instance
        if instance.isActive { await stop(id) }
        let generation = instance.begin()
        processes[id] = nil

        let shell = await environment.resolve()
        guard instance.generation == generation else { return }
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
        do {
            let process = try launcher.launch(
                request,
                onOutput: { intake.receive($0) },
                onExit: { [weak self] status in
                    intake.finish { [weak self] in self?.processExited(id, status: status, generation: generation) }
                })
            processes[id] = process
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

    func forget(_ id: UUID) {
        guard let instance = instances[id], !instance.isActive else { return }
        instances[id] = nil
    }

    private func processExited(_ id: UUID, status: ProcessExit, generation: Int) {
        guard instances[id]?.finish(status, generation: generation) == true else { return }
        processes[id] = nil
    }
}

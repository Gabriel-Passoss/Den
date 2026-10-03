import SwiftUI

@main
struct DenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment: any AppEnvironment
    @State private var runConfigurations: RunConfigurationsModel
    @State private var worktrees: WorktreeModel
    @State private var monitor: PullRequestMonitor

    init() {
        let environment = resolveEnvironment(ProcessInfo.processInfo.environment)
        self.environment = environment
        _runConfigurations = State(initialValue: RunConfigurationsModel(
            store: RunConfigurationStore(url: environment.runConfigurationsFile)))
        let ledger = TaskLedger(store: TaskWorktreeStore(url: environment.worktreesFile))
        _worktrees = State(initialValue: WorktreeModel(
            ledger: ledger, root: environment.worktreesRoot, defaults: environment.defaults,
            registry: environment.registry))
        _monitor = State(initialValue: PullRequestMonitor(
            ledger: ledger,
            fetcher: GitHubCLI(override: environment.ghOverride,
                               configured: environment.defaults.string(forKey: GitHubCLI.pathKey))))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
                .environment(appDelegate.runs)
                .environment(runConfigurations)
                .environment(worktrees)
                .environment(monitor)
                .defaultAppStorage(environment.defaults)
                .task { monitor.start() }
        }

        .commands { HarnessCommands() }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(monitor)
                .defaultAppStorage(environment.defaults)
        }
    }
}

import SwiftUI

@main
struct DenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment: any AppEnvironment
    @State private var runConfigurations: RunConfigurationsModel

    init() {
        let environment = resolveEnvironment(ProcessInfo.processInfo.environment)
        self.environment = environment
        _runConfigurations = State(initialValue: RunConfigurationsModel(
            store: RunConfigurationStore(url: environment.runConfigurationsFile)))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
                .environment(appDelegate.runs)
                .environment(runConfigurations)
                .defaultAppStorage(environment.defaults)
        }

        .commands { HarnessCommands() }

        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}

import SwiftUI

@main
struct DenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let environment = LaunchEnvironment.current
        if environment.defaults == .standard {
            LegacyDevSpace.migrate(into: environment.sessionsRoot.deletingLastPathComponent(),
                                   defaults: .standard)
        }
        InspectorPane.migrateLegacy(in: environment.defaults)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.runs)
                .environment(appDelegate.runConfigurations)
                .defaultAppStorage(LaunchEnvironment.current.defaults)
        }

        .commands { HarnessCommands() }

        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}

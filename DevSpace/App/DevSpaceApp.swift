import SwiftUI

@main
struct DevSpaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        InspectorPane.migrateLegacy(in: LaunchEnvironment.current.defaults)
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

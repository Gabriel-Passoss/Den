import SwiftUI

@main
struct DevSpaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        InspectorPane.migrateLegacy(in: .standard)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.runs)
                .environment(appDelegate.runConfigurations)
        }

        .commands { HarnessCommands() }

        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}

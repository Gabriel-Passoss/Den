import SwiftUI

@main
struct DevSpaceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .defaultAppStorage(LaunchEnvironment.current.defaults)
        }

        .commands { HarnessCommands() }

        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}

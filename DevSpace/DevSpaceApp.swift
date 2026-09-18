import SwiftUI

@main
struct DevSpaceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}

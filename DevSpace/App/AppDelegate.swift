import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let runs = RunManager()
    let runConfigurations = RunConfigurationsModel(store: .live)

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard runs.hasActiveProcesses else { return .terminateNow }
        Task {
            await runs.stopAll(grace: .seconds(2))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

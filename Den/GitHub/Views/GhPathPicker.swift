import AppKit

enum GhPathPicker {
    static func pick(for monitor: PullRequestMonitor) async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Usar"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url,
              await GitHubCLI.version(at: url.path) != nil else { return nil }
        await monitor.reconfigure(path: url.path)
        return url.path
    }
}

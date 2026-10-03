import Foundation

nonisolated enum UnreadableFile {
    static func setAside(_ url: URL, holding what: String, because error: Error) {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = url.deletingPathExtension().lastPathComponent
        let target = url.deletingLastPathComponent()
            .appending(path: "\(name).corrupt-\(stamp).\(url.pathExtension)")
        try? FileManager.default.moveItem(at: url, to: target)
        print("\(what) ilegíveis em \(url.path): \(error)")
    }
}

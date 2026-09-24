import Foundation

public func packageRoot(from filePath: String = #filePath) -> URL {
    var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
    while directory.path != "/" {
        if FileManager.default.fileExists(
            atPath: directory.appending(path: "Package.swift").path) {
            return directory
        }
        directory = directory.deletingLastPathComponent()
    }
    fatalError("could not find Package.swift walking up from \(filePath)")
}

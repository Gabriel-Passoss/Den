import Foundation

func makeTree(_ directories: [String], files: [String] = []) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for path in directories {
        try FileManager.default.createDirectory(at: root.appending(path: path),
                                                withIntermediateDirectories: true)
    }
    for path in files {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: file)
    }
    return root.standardizedFileURL
}

import Foundation
import DenMemory

let dawn = Date(timeIntervalSince1970: 1_700_000_000)

struct Scratch {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "denmemory-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func folder(_ path: String) throws -> URL {
        let folder = root.appending(path: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func write(_ text: String, to path: String) throws {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

func note(_ title: String, _ category: MemoryCategory = .note, body: String = "corpo",
          slug: String? = nil, sessions: [UUID] = []) -> MemoryPage {
    MemoryPage(slug: slug ?? MemorySlug.make(title), title: title, category: category, body: body,
               created: dawn, updated: dawn, sessions: sessions)
}

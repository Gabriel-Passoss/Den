import Foundation

nonisolated struct RunConfigurationStore: Sendable {
    let url: URL

    private struct File: Codable {
        var version: Int
        var projects: [String: [RunConfiguration]]
    }

    func load() -> [ProjectRoot: [RunConfiguration]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        do {
            let projects = try JSONDecoder().decode(File.self, from: data).projects
            return Dictionary(projects.map { (ProjectRoot(URL(fileURLWithPath: $0.key)), $0.value) },
                              uniquingKeysWith: +)
        } catch {
            UnreadableFile.setAside(url, holding: "configurações de execução", because: error)
            return [:]
        }
    }

    func save(_ projects: [ProjectRoot: [RunConfiguration]]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = File(version: 1, projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.key.path, $0.value) }))
        try encoder.encode(file).write(to: url, options: .atomic)
    }
}

import Foundation

public struct FileMemoryRepository: MemoryRepository {
    static let indexSlug = "index"
    private static let suffix = ".md"
    static let indexName = indexSlug + suffix

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func directory(of scope: MemoryScope) -> URL {
        switch scope {
        case .user: root.appending(path: "user")
        case .project(let project): root.appending(path: "projects").appending(path: project.slug)
        }
    }

    public func file(for slug: String, in scope: MemoryScope) -> URL {
        directory(of: scope).appending(path: slug + Self.suffix)
    }

    public func pages(in scope: MemoryScope) -> [MemoryPage] {
        let directory = directory(of: scope)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let pages: [MemoryPage] = names.compactMap { name in
            guard name.hasSuffix(Self.suffix), name != Self.indexName else { return nil }
            let file = directory.appending(path: name)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let slug = String(name.dropLast(Self.suffix.count)).precomposedStringWithCanonicalMapping
            return MemoryPageFile.parse(text, slug: slug, layer: scope.layer,
                                        fallbackDate: modified ?? .distantPast)
        }
        return pages.sorted { $0.listKey < $1.listKey }
    }

    public func save(_ page: MemoryPage, in scope: MemoryScope) throws {
        try check(page.slug)
        try FileManager.default.createDirectory(at: directory(of: scope), withIntermediateDirectories: true)
        try Data(MemoryPageFile.render(page).utf8).write(to: file(for: page.slug, in: scope), options: .atomic)
        try writeIndex(of: scope)
    }

    public func delete(_ slug: String, in scope: MemoryScope) throws {
        try check(slug)
        let file = file(for: slug, in: scope)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
        try writeIndex(of: scope)
    }

    private func check(_ slug: String) throws {
        let unsafe = slug.isEmpty || slug.contains("/") || slug.allSatisfy { $0 == "." }
        if unsafe { throw MemoryRepositoryError.unsafeName(slug) }
    }

    private func writeIndex(of scope: MemoryScope) throws {
        let pages = pages(in: scope)
        var lines = ["# " + scope.heading, ""]
        if pages.isEmpty { lines += ["_Nenhuma memória ainda._", ""] }
        for category in MemoryCategory.known(in: scope.layer) {
            let group = pages.filter { $0.category == category }
            if group.isEmpty { continue }
            lines += ["## " + category.label, ""]
            lines += group.map { "- [\($0.title)](\(link(to: $0.slug)))" }
            lines.append("")
        }
        let index = directory(of: scope).appending(path: Self.indexName)
        try Data(lines.joined(separator: "\n").utf8).write(to: index, options: .atomic)
    }

    private func link(to slug: String) -> String {
        (slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug) + Self.suffix
    }
}

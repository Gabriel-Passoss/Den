import Foundation

public struct MemoryConsolidator: Sendable {
    private let repository: any MemoryRepository

    public init(repository: any MemoryRepository) {
        self.repository = repository
    }

    public func apply(_ candidates: [MemoryCandidate], project: ProjectIdentity?,
                      session: UUID, now: Date) throws -> [MemoryPage] {
        var saved: [MemoryPage] = []
        for candidate in candidates {
            guard let scope = scope(of: candidate, in: project) else { continue }
            let existing = repository.pages(in: scope)
            let slug = existing.first { $0.slug == candidate.page }?.slug
                ?? freeSlug(for: candidate.title, among: existing)
            let previous = existing.first { $0.slug == slug }
            let sessions = previous?.sessions ?? []
            let page = MemoryPage(
                slug: slug, title: candidate.title,
                category: MemoryCategory.parse(candidate.category, in: scope.layer),
                body: candidate.body,
                created: previous?.created ?? now, updated: now,
                sessions: sessions.contains(session) ? sessions : sessions + [session])
            try repository.save(page, in: scope)
            saved.append(page)
        }
        return saved
    }

    private func freeSlug(for title: String, among existing: [MemoryPage]) -> String {
        let base = MemorySlug.make(title)
        let candidates = [base] + (2...existing.count + 2).map { "\(base)-\($0)" }
        let free = candidates.first { slug in
            slug != FileMemoryRepository.indexSlug && !existing.contains {
                $0.slug == slug && $0.title.caseInsensitiveCompare(title) != .orderedSame
            }
        }
        return free ?? base
    }

    private func scope(of candidate: MemoryCandidate, in project: ProjectIdentity?) -> MemoryScope? {
        switch candidate.layer {
        case .user: .user
        case .project: project.map(MemoryScope.project)
        }
    }
}

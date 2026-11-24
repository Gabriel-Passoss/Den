import Foundation

public enum SessionRepositoryError: Error, Equatable {
    case sessionNotFound(UUID)
    case segmentNotFound(UUID)
}

public protocol SessionRepository: Sendable {
    func list() async throws -> [SessionSummary]

    func load(_ sessionID: Session.ID) async throws -> Session

    func saveMetadata(_ session: Session) async throws

    func append(_ entry: TranscriptEntry, to segmentID: Segment.ID,
                in sessionID: Session.ID) async throws

    func delete(_ sessionID: Session.ID) async throws
}

import Foundation

public enum TranscriptStoreError: Error, Equatable {
    case sessionNotFound(UUID)
    case segmentNotFound(UUID)
}

public struct SessionListing: Sendable, Equatable {

    public var sessions: [SessionSummary]

    public var unreadable: [UnreadableSession]

    public init(sessions: [SessionSummary] = [], unreadable: [UnreadableSession] = []) {
        self.sessions = sessions
        self.unreadable = unreadable
    }
}

public struct UnreadableSession: Sendable, Equatable {

    public let id: UUID?

    public let location: URL

    public let reason: String

    public init(id: UUID?, location: URL, reason: String) {
        self.id = id
        self.location = location
        self.reason = reason
    }
}

public protocol TranscriptStore: Sendable {

    func saveMetadata(_ session: Session) async throws

    func append(_ entry: TranscriptEntry, to segmentID: Segment.ID,
                in sessionID: Session.ID) async throws

    func load(_ sessionID: Session.ID) async throws -> Session

    func list() async throws -> SessionListing
}

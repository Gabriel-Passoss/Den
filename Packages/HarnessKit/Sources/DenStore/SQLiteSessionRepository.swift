import Foundation
import HarnessCore
import SQLiteKit

actor SQLiteSessionRepository: SessionRepository {
    private let database: Database
    private let now: @Sendable () -> Date

    init(database: Database, now: @escaping @Sendable () -> Date) {
        self.database = database
        self.now = now
    }

    func list() throws -> [SessionSummary] {
        let (sessions, segments) = try database.read { connection in
            try (connection.query(SessionSQL.summaries) { SummaryRow($0) },
                 connection.query(SessionSQL.everySegment) { SegmentRow($0) })
        }
        let bySession = Dictionary(grouping: segments, by: \.sessionID)
        return sessions.compactMap { $0.summary(segments: bySession[$0.id] ?? []) }
    }

    func load(_ sessionID: Session.ID) throws -> Session {
        let key = Value.text(sessionID.uuidString)
        let (heads, segments, entries) = try database.read { connection in
            try (connection.query(SessionSQL.head, [key]) { ($0.text(0), $0.text(1)) },
                 connection.query(SessionSQL.segmentsOfSession, [key]) { SegmentRow($0) },
                 connection.query(SessionSQL.entriesOfSession, [key]) { ($0.text(0), $0.text(1)) })
        }
        guard let (title, directory) = heads.first else {
            throw SessionRepositoryError.sessionNotFound(sessionID)
        }
        let bySegment = Dictionary(grouping: entries, by: \.0)
        return Session(id: sessionID, title: title, workingDirectory: SessionSQL.directory(directory),
                       segments: segments.compactMap { row in
                           row.segment(entries: (bySegment[row.id] ?? []).compactMap {
                               JSONText.decode(TranscriptEntry.self, from: $0.1, as: .transcript)
                           })
                       })
    }

    func saveMetadata(_ session: Session) throws {
        let key = Value.text(session.id.uuidString)
        let moment = Value.real(now().timeIntervalSince1970)
        let segments = try session.segments.enumerated().map { ordinal, segment in
            try SegmentRow.bindings(for: segment, ordinal: ordinal, session: key)
        }
        let kept = session.segments.map { Value.text($0.id.uuidString) }
        let placeholders = Array(repeating: "?", count: kept.count).joined(separator: ", ")
        try database.write { connection in
            try connection.execute(SessionSQL.upsertSession, [
                key, .text(session.title), .text(session.workingDirectory.absoluteString), moment, moment,
            ])
            try connection.execute(
                "DELETE FROM segments WHERE session_id = ? AND id NOT IN (\(placeholders))", [key] + kept)
            try connection.execute("UPDATE segments SET ordinal = -ordinal - 1 WHERE session_id = ?", [key])
            for bindings in segments { try connection.execute(SessionSQL.upsertSegment, bindings) }
        }
    }

    func append(_ entry: TranscriptEntry, to segmentID: Segment.ID,
                in sessionID: Session.ID) throws {
        let payload = try JSONText.encode(entry, as: .transcript)
        let session = Value.text(sessionID.uuidString)
        let segment = Value.text(segmentID.uuidString)
        let moment = Value.real(now().timeIntervalSince1970)
        try database.write { connection in
            guard try connection.hasSession(sessionID) else {
                throw SessionRepositoryError.sessionNotFound(sessionID)
            }
            let owned = try connection.query(SessionSQL.segmentOfSession, [segment, session]) { $0[0] }
            guard !owned.isEmpty else { throw SessionRepositoryError.segmentNotFound(segmentID) }
            try connection.execute(SessionSQL.insertEntry, [
                .text(entry.id.uuidString), segment, .real(entry.timestamp.timeIntervalSince1970), .text(payload),
            ])
            try connection.execute("UPDATE sessions SET touched_at = ? WHERE id = ?", [moment, session])
        }
    }

    func delete(_ sessionID: Session.ID) throws {
        try database.write { connection in
            try connection.execute("DELETE FROM sessions WHERE id = ?", [.text(sessionID.uuidString)])
            guard connection.changes > 0 else { throw SessionRepositoryError.sessionNotFound(sessionID) }
        }
    }
}

private enum SessionSQL {
    static let summaries = """
        SELECT s.id, s.title, s.working_directory, s.touched_at,
               (SELECT COUNT(*) FROM entries e JOIN segments g ON g.id = e.segment_id
                WHERE g.session_id = s.id)
        FROM sessions s
        ORDER BY s.touched_at DESC, s.id ASC
        """

    private static let segmentColumns = """
        id, session_id, harness, harness_session_id, model, input_tokens, output_tokens,
        cache_read_tokens, cache_creation_tokens, cost_usd, seeded_by, context
        """

    static let everySegment = "SELECT \(segmentColumns) FROM segments ORDER BY session_id, ordinal"

    static let segmentsOfSession = "SELECT \(segmentColumns) FROM segments WHERE session_id = ? ORDER BY ordinal"

    static let head = "SELECT title, working_directory FROM sessions WHERE id = ?"

    static let entriesOfSession = """
        SELECT e.segment_id, e.payload FROM entries e JOIN segments g ON g.id = e.segment_id
        WHERE g.session_id = ? ORDER BY e.seq
        """

    static let segmentOfSession = "SELECT 1 FROM segments WHERE id = ? AND session_id = ?"

    static let insertEntry = "INSERT OR IGNORE INTO entries (id, segment_id, timestamp, payload) VALUES (?, ?, ?, ?)"

    static let upsertSession = """
        INSERT INTO sessions (id, title, working_directory, created_at, touched_at) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET title = excluded.title, working_directory = excluded.working_directory
        """

    static let upsertSegment = """
        INSERT INTO segments (id, session_id, ordinal, harness, harness_session_id, model, input_tokens,
                              output_tokens, cache_read_tokens, cache_creation_tokens, cost_usd,
                              seeded_by, context)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            ordinal = excluded.ordinal, harness = excluded.harness,
            harness_session_id = excluded.harness_session_id, model = excluded.model,
            input_tokens = excluded.input_tokens, output_tokens = excluded.output_tokens,
            cache_read_tokens = excluded.cache_read_tokens,
            cache_creation_tokens = excluded.cache_creation_tokens, cost_usd = excluded.cost_usd,
            seeded_by = excluded.seeded_by, context = excluded.context
        """

    static func directory(_ stored: String) -> URL {
        URL(string: stored) ?? URL(fileURLWithPath: stored)
    }
}

private struct SummaryRow {
    let id: String
    let title: String
    let directory: String
    let touchedAt: Double
    let entryCount: Int

    init(_ row: Row) {
        id = row.text(0)
        title = row.text(1)
        directory = row.text(2)
        touchedAt = row.real(3)
        entryCount = row.integer(4)
    }

    func summary(segments: [SegmentRow]) -> SessionSummary? {
        guard let id = UUID(uuidString: id) else { return nil }
        return SessionSummary(id: id, title: title, workingDirectory: SessionSQL.directory(directory),
                              harnesses: segments.map { HarnessID(rawValue: $0.harness) },
                              usage: segments.reduce(.zero) { $0 + $1.usage },
                              entryCount: entryCount,
                              updatedAt: Date(timeIntervalSince1970: touchedAt))
    }
}

private struct SegmentRow {
    let id: String
    let sessionID: String
    let harness: String
    let harnessSessionID: String
    let model: String
    let usage: UsageTotals
    let seededBy: String?
    let context: String?

    init(_ row: Row) {
        id = row.text(0)
        sessionID = row.text(1)
        harness = row.text(2)
        harnessSessionID = row.text(3)
        model = row.text(4)
        usage = UsageTotals(inputTokens: row.integer(5), outputTokens: row.integer(6),
                            cacheReadTokens: row.integer(7), cacheCreationTokens: row.integer(8),
                            costUSD: row.real(9))
        seededBy = row[10].textValue
        context = row[11].textValue
    }

    func segment(entries: [TranscriptEntry]) -> Segment? {
        guard let id = UUID(uuidString: id) else { return nil }
        return Segment(id: id, harness: HarnessID(rawValue: harness), harnessSessionID: harnessSessionID,
                       model: model, entries: entries, usage: usage,
                       seededBy: seededBy.flatMap { JSONText.decode(Handoff.self, from: $0, as: .transcript) },
                       context: context.flatMap { JSONText.decode(ContextUsage.self, from: $0, as: .transcript) })
    }

    static func bindings(for segment: Segment, ordinal: Int, session: Value) throws -> [Value] {
        try [
            .text(segment.id.uuidString), session, .integer(Int64(ordinal)),
            .text(segment.harness.rawValue), .text(segment.harnessSessionID), .text(segment.model),
            .integer(Int64(segment.usage.inputTokens)), .integer(Int64(segment.usage.outputTokens)),
            .integer(Int64(segment.usage.cacheReadTokens)), .integer(Int64(segment.usage.cacheCreationTokens)),
            .real(segment.usage.costUSD),
            segment.seededBy.map { try .text(JSONText.encode($0, as: .transcript)) } ?? .null,
            segment.context.map { try .text(JSONText.encode($0, as: .transcript)) } ?? .null,
        ]
    }
}

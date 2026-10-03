import Foundation
import Darwin

public actor FileTranscriptStore: TranscriptStore {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) {
        self.root = root
        let encoder = JSONEncoder()

        encoder.dateEncodingStrategy = .iso8601

        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    private func directory(for sessionID: UUID) -> URL {
        root.appendingPathComponent(sessionID.uuidString)
    }

    private func metadataFile(for sessionID: UUID) -> URL {
        directory(for: sessionID).appendingPathComponent("session.json")
    }

    private func segmentFile(_ segmentID: UUID, in sessionID: UUID) -> URL {
        directory(for: sessionID).appendingPathComponent("\(segmentID.uuidString).ndjson")
    }

    public func saveMetadata(_ session: Session) throws {
        try FileManager.default.createDirectory(
            at: directory(for: session.id), withIntermediateDirectories: true)

        var stripped = session
        stripped.segments = session.segments.map {
            var segment = $0
            segment.entries = []
            return segment
        }
        try encoder.encode(stripped).write(to: metadataFile(for: session.id), options: .atomic)
    }

    public func append(_ entry: TranscriptEntry, to segmentID: Segment.ID,
                       in sessionID: Session.ID) throws {

        let metadata = metadataFile(for: sessionID)
        guard FileManager.default.fileExists(atPath: metadata.path) else {
            throw TranscriptStoreError.sessionNotFound(sessionID)
        }
        let session = try decoder.decode(Session.self, from: Data(contentsOf: metadata))
        guard session.segments.contains(where: { $0.id == segmentID }) else {
            throw TranscriptStoreError.segmentNotFound(segmentID)
        }

        var line = try encoder.encode(entry)
        line.append(0x0A)

        let file = segmentFile(segmentID, in: sessionID)

        let fd = open(file.path, O_RDWR | O_CREAT | O_APPEND, 0o644)
        guard fd != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        var status = stat()
        guard fstat(fd, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if status.st_size > 0 {
            var lastByte: UInt8 = 0
            let bytesRead = withUnsafeMutableBytes(of: &lastByte) { buffer in
                pread(fd, buffer.baseAddress, 1, status.st_size - 1)
            }
            guard bytesRead >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if bytesRead == 1, lastByte != 0x0A {
                line.insert(0x0A, at: line.startIndex)
            }
        }

        try line.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
        }
    }

    public func delete(_ sessionID: Session.ID) throws {
        let directory = directory(for: sessionID)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw TranscriptStoreError.sessionNotFound(sessionID)
        }
        try FileManager.default.removeItem(at: directory)
    }

    public func load(_ sessionID: Session.ID) throws -> Session {
        let metadata = metadataFile(for: sessionID)
        guard FileManager.default.fileExists(atPath: metadata.path) else {
            throw TranscriptStoreError.sessionNotFound(sessionID)
        }
        var session = try decoder.decode(Session.self, from: Data(contentsOf: metadata))
        session.segments = session.segments.map { segment in
            var filled = segment
            filled.entries = entries(of: segment.id, in: sessionID)
            return filled
        }
        return session
    }

    public func list() throws -> SessionListing {
        let manager = FileManager.default

        guard let directories = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else {
            return SessionListing()
        }

        var sessions: [SessionSummary] = []
        var unreadable: [UnreadableSession] = []
        for directory in directories {
            let metadata = directory.appendingPathComponent("session.json")
            guard manager.fileExists(atPath: metadata.path) else { continue }
            do {
                let session = try decoder.decode(
                    Session.self, from: Data(contentsOf: metadata))

                var count = 0

                var conversationTouched: Date?
                for segment in session.segments {
                    let file = segmentFile(segment.id, in: session.id)
                    count += lineCount(of: file)
                    if let touched = modificationDate(of: file),
                       touched > (conversationTouched ?? .distantPast) {
                        conversationTouched = touched
                    }
                }
                let updated = conversationTouched
                    ?? modificationDate(of: metadata) ?? .distantPast
                sessions.append(SessionSummary(
                    id: session.id, title: session.title,
                    workingDirectory: session.workingDirectory,
                    harnesses: session.segments.map(\.harness),
                    usage: session.totalUsage, entryCount: count, updatedAt: updated))
            } catch {
                unreadable.append(UnreadableSession(
                    id: UUID(uuidString: directory.lastPathComponent),
                    location: directory,
                    reason: String(describing: error)))
            }
        }

        sessions.sort {
            $0.updatedAt == $1.updatedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.updatedAt > $1.updatedAt
        }
        unreadable.sort { $0.location.path < $1.location.path }
        return SessionListing(sessions: sessions, unreadable: unreadable)
    }

    private func modificationDate(of file: URL) -> Date? {
        var status = stat()
        guard stat(file.path, &status) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(status.st_mtimespec.tv_sec)
            + Double(status.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    private func entries(of segmentID: UUID, in sessionID: UUID) -> [TranscriptEntry] {
        let file = segmentFile(segmentID, in: sessionID)
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [] }
        return data.split(separator: 0x0A, omittingEmptySubsequences: true)
            .compactMap { try? decoder.decode(TranscriptEntry.self, from: Data($0)) }
    }

    private func lineCount(of file: URL) -> Int {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return 0 }
        return data.withUnsafeBytes { buffer -> Int in
            var count = 0
            var openLine = false
            for byte in buffer {
                if byte == 0x0A {
                    if openLine { count += 1; openLine = false }
                } else {
                    openLine = true
                }
            }

            return openLine ? count + 1 : count
        }
    }
}

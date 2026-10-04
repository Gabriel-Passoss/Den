import Foundation
import SQLite3

public final class Database: @unchecked Sendable {
    public enum Location: Sendable, Equatable {
        case file(URL)
        case memory
    }

    private let handle: OpaquePointer
    private let lock = NSLock()

    public init(_ location: Location) throws {
        let opened = try Self.open(location)
        do {
            try Self.configure(Connection(handle: opened), location)
        } catch {
            sqlite3_close_v2(opened)
            throw error
        }
        handle = opened
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    public func read<T>(_ body: (Connection) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(Connection(handle: handle))
    }

    public func write<T>(_ body: (Connection) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        let connection = Connection(handle: handle)
        try connection.executeScript("BEGIN IMMEDIATE")
        do {
            let result = try body(connection)
            try connection.executeScript("COMMIT")
            return result
        } catch {
            try? connection.executeScript("ROLLBACK")
            throw error
        }
    }

    private static func open(_ location: Location) throws -> OpaquePointer {
        let path = switch location {
        case .file(let url): url.path
        case .memory: ":memory:"
        }
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let code = sqlite3_open_v2(path, &opened, flags, nil)
        guard let opened else {
            throw DatabaseError.sqlite(code: code, message: "sem memória para abrir o banco")
        }
        guard code == SQLITE_OK else {
            let failure = Connection(handle: opened).failure()
            sqlite3_close_v2(opened)
            throw failure
        }
        return opened
    }

    private static let busyAttempts = 100
    private static let busyPause: UInt32 = 50000

    private static func configure(_ connection: Connection, _ location: Location) throws {
        try connection.executeScript("PRAGMA busy_timeout = 5000")
        if location != .memory {
            try waitingWhileBusy { try connection.executeScript("PRAGMA journal_mode = WAL") }
        }
        try connection.executeScript("PRAGMA foreign_keys = ON; PRAGMA synchronous = NORMAL")
    }

    private static func waitingWhileBusy(_ body: () throws -> Void) throws {
        for _ in 1..<busyAttempts {
            do {
                try body()
                return
            } catch DatabaseError.sqlite(let code, _) where code == SQLITE_BUSY {
                usleep(busyPause)
            }
        }
        try body()
    }
}

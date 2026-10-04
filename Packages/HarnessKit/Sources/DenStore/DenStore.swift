import Foundation
import HarnessCore
import SQLiteKit

public enum DenStoreError: Error, Equatable {
    case newerSchema(found: Int, supported: Int)
    case unavailable(String)
}

public struct OpenedStore: Sendable {
    public let repositories: Repositories
    public let setAside: URL?
}

public struct Repositories: Sendable {
    public let sessions: any SessionRepository
    public let sidebar: any SidebarRepository
    public let preferences: any SessionPreferencesRepository
    public let harnessCache: any HarnessCacheRepository

    init(database: Database, now: @escaping @Sendable () -> Date) {
        sessions = SQLiteSessionRepository(database: database, now: now)
        sidebar = SQLiteSidebarRepository(database: database)
        preferences = SQLiteSessionPreferencesRepository(database: database)
        harnessCache = SQLiteHarnessCacheRepository(database: database, now: now)
    }
}

public enum DenStore {
    public static func open(at file: URL,
                            now: @escaping @Sendable () -> Date = { Date() }) throws -> OpenedStore {
        try translating {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            do {
                return try OpenedStore(repositories: assemble(.file(file), now), setAside: nil)
            } catch let error as DatabaseError where error.isCorruption {
                let aside = try setAside(file, at: now())
                return try OpenedStore(repositories: assemble(.file(file), now), setAside: aside)
            }
        }
    }

    public static func inMemory(now: @escaping @Sendable () -> Date = { Date() }) throws -> Repositories {
        try translating { try assemble(.memory, now) }
    }

    private static func assemble(_ location: Database.Location,
                                 _ now: @escaping @Sendable () -> Date) throws -> Repositories {
        let database = try Database(location)
        try Migrator(Schema.migrations).migrate(database)
        SQLiteHarnessCacheRepository(database: database, now: now).prune()
        return Repositories(database: database, now: now)
    }

    private static func setAside(_ file: URL, at moment: Date) throws -> URL {
        let name = file.deletingPathExtension().lastPathComponent
        let stamp = Int(moment.timeIntervalSince1970)
        let target = file.deletingLastPathComponent()
            .appending(path: "\(name).corrupt-\(stamp).\(file.pathExtension)")
        try FileManager.default.moveItem(at: file, to: target)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.moveItem(at: URL(fileURLWithPath: file.path + suffix),
                                              to: URL(fileURLWithPath: target.path + suffix))
        }
        return target
    }

    private static func translating<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch DatabaseError.newerSchema(let found, let supported) {
            throw DenStoreError.newerSchema(found: found, supported: supported)
        } catch DatabaseError.sqlite(_, let message) {
            throw DenStoreError.unavailable(message)
        } catch {
            throw DenStoreError.unavailable(error.localizedDescription)
        }
    }
}

import Foundation
import HarnessCore
import SQLiteKit

public protocol HarnessCacheRepository: Sendable {
    func catalog(for directory: URL, harness: HarnessID) -> CommandCatalog

    func remember(_ catalog: CommandCatalog, for directory: URL, harness: HarnessID)

    func knobs(for harness: HarnessID) -> [HarnessKnob]

    func remember(_ knobs: [HarnessKnob], for harness: HarnessID)
}

struct SQLiteHarnessCacheRepository: HarnessCacheRepository {
    static let lifetime: TimeInterval = 30 * 24 * 60 * 60
    private static let lastSeen = ""

    let database: Database
    let now: @Sendable () -> Date

    func catalog(for directory: URL, harness: HarnessID) -> CommandCatalog {
        for place in [directory.standardizedFileURL.path, Self.lastSeen] {
            if let known = payload(CommandCatalog.self, harness: harness, kind: "catalog", directory: place) {
                return known
            }
        }
        return .empty
    }

    func remember(_ catalog: CommandCatalog, for directory: URL, harness: HarnessID) {
        guard !catalog.isEmpty else { return }
        store(catalog, harness: harness, kind: "catalog",
              directories: [directory.standardizedFileURL.path, Self.lastSeen])
    }

    func knobs(for harness: HarnessID) -> [HarnessKnob] {
        payload([HarnessKnob].self, harness: harness, kind: "knobs", directory: Self.lastSeen) ?? []
    }

    func remember(_ knobs: [HarnessKnob], for harness: HarnessID) {
        guard !knobs.isEmpty else { return }
        store(knobs, harness: harness, kind: "knobs", directories: [Self.lastSeen])
    }

    func prune() {
        let cutoff = now().timeIntervalSince1970 - Self.lifetime
        try? database.write { connection in
            try connection.execute("DELETE FROM harness_cache WHERE directory != '' AND updated_at < ?",
                                   [.real(cutoff)])
        }
    }

    private func payload<T: Decodable>(_ type: T.Type, harness: HarnessID, kind: String,
                                       directory: String) -> T? {
        let found = try? database.read { connection in
            try connection.query(
                "SELECT payload FROM harness_cache WHERE harness = ? AND kind = ? AND directory = ?",
                [.text(harness.rawValue), .text(kind), .text(directory)]) { $0.text(0) }
        }
        return found?.first.flatMap { JSONText.decode(type, from: $0, as: .document) }
    }

    private func store(_ value: some Encodable, harness: HarnessID, kind: String, directories: [String]) {
        guard let payload = try? JSONText.encode(value, as: .document) else { return }
        let moment = Value.real(now().timeIntervalSince1970)
        try? database.write { connection in
            for directory in directories {
                try connection.execute("""
                    INSERT INTO harness_cache (harness, kind, directory, payload, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(harness, kind, directory) DO UPDATE SET
                        payload = excluded.payload, updated_at = excluded.updated_at
                    """, [.text(harness.rawValue), .text(kind), .text(directory), .text(payload), moment])
            }
        }
    }
}

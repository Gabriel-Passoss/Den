import Foundation
import Synchronization
import HarnessCore
import DenStore
import SQLiteKit

let harnessA = HarnessID(rawValue: "harness-a")
let harnessB = HarnessID(rawValue: "harness-b")
let epoch = Date(timeIntervalSince1970: 1_700_000_000)

final class TestClock: Sendable {
    private let moment: Mutex<Date>

    init(_ start: Date = epoch) {
        moment = Mutex(start)
    }

    var now: Date { moment.withLock { $0 } }

    func advance(by seconds: TimeInterval) {
        moment.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

struct ScratchStore {
    let file: URL
    let clock = TestClock()

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "denstore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "den.sqlite")
    }

    func open() throws -> OpenedStore {
        try DenStore.open(at: file, now: { [clock] in clock.now })
    }

    func raw() throws -> Database {
        try Database(.file(file))
    }

    func siblings() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).sorted()
    }

    func remove() {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}

func spoken(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: epoch, kind: .assistantText(text), raw: .object(["t": .string(text)]))
}

func stretch(on harness: HarnessID = harnessA) -> Segment {
    Segment(harness: harness, harnessSessionID: UUID().uuidString, model: "m")
}

func conversation(_ title: String = "uma conversa", in directory: String = "/tmp/repo",
                  segments: [Segment] = [stretch()]) -> Session {
    Session(title: title, workingDirectory: URL(fileURLWithPath: directory), segments: segments)
}

func texts(of session: Session) -> [String] {
    session.allEntries.compactMap { entry in
        if case .assistantText(let text) = entry.kind { return text }
        return nil
    }
}

func saved(_ session: Session = conversation(), in repositories: Repositories) async throws -> Session {
    try await repositories.sessions.saveMetadata(session)
    return session
}

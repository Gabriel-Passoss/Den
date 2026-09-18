import Foundation

public enum SessionEvent: Sendable, Equatable {

    case sessionInitialized(model: String, harnessSessionID: String)

    case turnStarted

    case textDelta(blockIndex: Int, text: String)

    case thinkingDelta(blockIndex: Int, text: String)

    case toolInputDelta(blockIndex: Int, partialJSON: String)

    case notice(subtype: String, text: String)
}

public struct MappedOutput: Sendable, Equatable {

    public var events: [SessionEvent]

    public var entries: [TranscriptEntry]

    public init(events: [SessionEvent] = [], entries: [TranscriptEntry] = []) {
        self.events = events
        self.entries = entries
    }

    public static let empty = MappedOutput()
}

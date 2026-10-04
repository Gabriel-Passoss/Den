import Foundation

public enum Handoff: Sendable, Equatable, Codable {

    case briefing(String)

    case replay(throughEntry: UUID)

    case unrecognized(discriminator: String, payload: JSONValue)

    private enum Known: Sendable, Equatable, Codable {
        case briefing(String)
        case replay(throughEntry: UUID)

        enum CodingKeys: String, CodingKey, CaseIterable {
            case briefing, replay
        }
    }

    static let knownDiscriminators: Set<String> =
        Set(Known.CodingKeys.allCases.map(\.stringValue))

    public init(from decoder: Decoder) throws {
        let peek = try decoder.container(keyedBy: DiscriminatorKey.self)
        guard peek.allKeys.count == 1, let key = peek.allKeys.first else {
            throw DecodingError.oneDiscriminatorExpected(
                by: "Handoff", reportingAs: "seededBy", in: peek)
        }
        guard Handoff.knownDiscriminators.contains(key.stringValue) else {
            let payload = try peek.decode(JSONValue.self, forKey: key)
            self = .unrecognized(discriminator: key.stringValue, payload: payload)
            return
        }
        switch try Known(from: decoder) {
        case .briefing(let text): self = .briefing(text)
        case .replay(let entry): self = .replay(throughEntry: entry)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .briefing(let text): try Known.briefing(text).encode(to: encoder)
        case .replay(let entry): try Known.replay(throughEntry: entry).encode(to: encoder)
        case .unrecognized(let discriminator, let payload):
            var container = encoder.container(keyedBy: DiscriminatorKey.self)
            try container.encode(payload, forKey: DiscriminatorKey(discriminator))
        }
    }
}

public struct Segment: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let harness: HarnessID

    public var harnessSessionID: String
    public var model: String
    public var entries: [TranscriptEntry]

    public var usage: UsageTotals

    public var seededBy: Handoff?

    public var context: ContextUsage?

    public init(id: UUID = UUID(), harness: HarnessID, harnessSessionID: String,
                model: String, entries: [TranscriptEntry] = [],
                usage: UsageTotals = .zero, seededBy: Handoff? = nil,
                context: ContextUsage? = nil) {
        self.id = id
        self.harness = harness
        self.harnessSessionID = harnessSessionID
        self.model = model
        self.entries = entries
        self.usage = usage
        self.seededBy = seededBy
        self.context = context
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        harness = try container.decode(HarnessID.self, forKey: .harness)
        harnessSessionID = try container.decode(String.self, forKey: .harnessSessionID)
        model = try container.decode(String.self, forKey: .model)
        entries = try container.decode([TranscriptEntry].self, forKey: .entries)
        usage = try container.decode(UsageTotals.self, forKey: .usage)
        seededBy = try container.decodeIfPresent(Handoff.self, forKey: .seededBy)
        context = try? container.decodeIfPresent(ContextUsage.self, forKey: .context)
    }
}

public struct Session: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var title: String
    public var workingDirectory: URL

    public var segments: [Segment]

    public init(id: UUID = UUID(), title: String, workingDirectory: URL,
                segments: [Segment] = []) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.segments = segments
    }

    public var allEntries: [TranscriptEntry] {
        segments.flatMap(\.entries)
    }

    public var totalUsage: UsageTotals {
        segments.reduce(.zero) { $0 + $1.usage }
    }
}

public struct SessionSummary: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var title: String
    public var workingDirectory: URL

    public var harnesses: [HarnessID]
    public var usage: UsageTotals
    public var entryCount: Int
    public var updatedAt: Date

    public init(id: UUID, title: String, workingDirectory: URL, harnesses: [HarnessID],
                usage: UsageTotals, entryCount: Int, updatedAt: Date) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.harnesses = harnesses
        self.usage = usage
        self.entryCount = entryCount
        self.updatedAt = updatedAt
    }

    public init(session: Session, entryCount: Int, updatedAt: Date) {
        self.init(id: session.id, title: session.title,
                  workingDirectory: session.workingDirectory,
                  harnesses: session.segments.map(\.harness),
                  usage: session.totalUsage,
                  entryCount: entryCount,
                  updatedAt: updatedAt)
    }
}

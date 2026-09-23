public struct UnrecognizedControl: Equatable, Sendable {

    public let requestID: String?

    public let raw: JSONValue

    public let automaticReply: String?

    public var wasAnswered: Bool { automaticReply != nil }

    public init(requestID: String?, raw: JSONValue, automaticReply: String?) {
        self.requestID = requestID
        self.raw = raw
        self.automaticReply = automaticReply
    }
}

public enum SessionUpdate: Sendable {

    case event(SessionEvent)

    case entry(TranscriptEntry)

    case permission(PermissionRequest)

    case unrecognizedControl(UnrecognizedControl)

    case ended(error: String?)
}

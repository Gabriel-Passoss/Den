import Foundation
import HarnessCore

public struct MediaAttachment: Sendable, Equatable {
    public let mediaType: String
    public let data: Data

    public init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }

    public var isImage: Bool { mediaType.hasPrefix("image/") }
}

public actor ClaudeSession {

    public enum Update: Sendable {

        case event(SessionEvent)

        case entry(TranscriptEntry)

        case permission(PermissionRequest)

        case unrecognizedControl(UnrecognizedControl)

        case ended(error: String?)
    }

    private let channel: ControlChannel
    private let mapper: ClaudeEventMapper
    private var pump: Task<Void, Never>?

    public init(channel: ControlChannel, mapper: ClaudeEventMapper = ClaudeEventMapper()) {
        self.channel = channel
        self.mapper = mapper
    }

    public func start(_ launch: ProcessTransport.Launch) async throws -> AsyncStream<Update> {
        let outputs = try await channel.start(launch)

        return AsyncStream<Update> { continuation in
            pump = Task { [mapper] in
                do {
                    for try await output in outputs {
                        switch output {
                        case .conversation(let line):
                            let mapped = mapper.map(line: line)
                            for event in mapped.events { continuation.yield(.event(event)) }
                            for entry in mapped.entries { continuation.yield(.entry(entry)) }
                        case .permissionRequest(let request):

                            continuation.yield(.permission(request))
                        case .unrecognizedControl(let unrecognized):
                            continuation.yield(.unrecognizedControl(unrecognized))
                        }
                    }
                    continuation.yield(.ended(error: nil))
                } catch {
                    continuation.yield(.ended(error: String(describing: error)))
                }
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                Task { await self?.stop() }
            }
        }
    }

    public func send(_ text: String, attachments: [MediaAttachment] = []) async throws {
        var line = try JSONEncoder().encode(Self.userTurn(text: text, attachments: attachments))
        line.append(0x0A)
        try await channel.writeTurn(line)
    }

    static func userTurn(text: String, attachments: [MediaAttachment]) -> JSONValue {
        let content: JSONValue
        if attachments.isEmpty {
            content = .string(text)
        } else {
            var blocks: [JSONValue] = attachments.map { attachment in
                .object([
                    "type": .string(attachment.isImage ? "image" : "document"),
                    "source": .object([
                        "type": .string("base64"),
                        "media_type": .string(attachment.mediaType),
                        "data": .string(attachment.data.base64EncodedString()),
                    ]),
                ])
            }
            if !text.isEmpty {
                blocks.append(.object(["type": .string("text"), "text": .string(text)]))
            }
            content = .array(blocks)
        }
        return .object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": content,
            ]),
        ])
    }

    public func resolve(_ requestID: String, _ decision: PermissionDecision) async throws {
        try await channel.respond(to: requestID, with: decision)
    }

    public func stop() async {
        pump?.cancel()
        pump = nil
        await channel.stop()
    }
}

import Foundation
import HarnessCore

public actor ClaudeSession: HarnessSession {

    private let installation: HarnessInstallation
    private let workingDirectory: URL
    private var settings: [String: String]

    private let channel: ControlChannel
    private let mapper: ClaudeEventMapper
    private var pump: Task<Void, Never>?

    public init(installation: HarnessInstallation,
                workingDirectory: URL,
                settings: [String: String] = [:],
                channel: ControlChannel = ControlChannel(transport: ProcessTransport()),
                mapper: ClaudeEventMapper = ClaudeEventMapper()) {
        self.installation = installation
        self.workingDirectory = workingDirectory
        self.settings = settings
        self.channel = channel
        self.mapper = mapper
    }

    public func knobs() async -> [HarnessKnob] {
        ClaudeKnobs.all(settings: settings, detected: (
            effort: ClaudeSettings.effortLevel(forWorkingDirectory: workingDirectory),
            mode: ClaudeSettings.permissionMode(forWorkingDirectory: workingDirectory)
        ))
    }

    public func start(_ start: SessionStart) async throws -> AsyncStream<SessionUpdate> {
        let launch = ClaudeLaunch.make(
            installation: installation,
            workingDirectory: workingDirectory,
            session: ClaudeSessionStart(start),
            model: settings[ClaudeKnobs.model],
            effort: settings[ClaudeKnobs.effort].flatMap(EffortLevel.init(rawValue:)),
            permissionMode: settings[ClaudeKnobs.mode].flatMap(PermissionMode.init(rawValue:))
        )
        let outputs = try await channel.start(launch)

        return AsyncStream<SessionUpdate> { continuation in
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

    public func send(_ turn: UserTurn) async throws {
        var line = try JSONEncoder().encode(
            Self.userTurn(text: turn.text, attachments: turn.attachments))
        line.append(0x0A)
        try await channel.writeTurn(line)
    }

    public func interrupt() async throws {
        _ = try await channel.send(.interrupt)
    }

    public func apply(knob id: String, value: String?) async throws {
        settings[id] = value

        guard id == ClaudeKnobs.mode,
              let raw = value, let mode = PermissionMode(rawValue: raw) else { return }
        _ = try await channel.send(.setPermissionMode(mode))
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

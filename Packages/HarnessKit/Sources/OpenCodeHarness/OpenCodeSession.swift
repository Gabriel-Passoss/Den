import Foundation
import HarnessCore

public actor OpenCodeSession: HarnessSession {

    private let installation: HarnessInstallation
    private let workingDirectory: URL
    private var settings: [String: String]

    private let channel: ACPChannel
    private var mapper: OpenCodeEventMapper

    private var pump: Task<Void, Never>?
    private var turn: Task<Void, Never>?
    private var continuation: AsyncStream<SessionUpdate>.Continuation?

    private var harnessSessionID: String?
    private var currentKnobs: [HarnessKnob] = []

    private var inboundIDs: [String: JSONValue] = [:]
    private var offeredOptions: [String: [PermissionOption]] = [:]
    private var nextPermissionNumber = 0

    public init(installation: HarnessInstallation,
                workingDirectory: URL,
                settings: [String: String] = [:],
                channel: ACPChannel = ACPChannel(transport: ProcessTransport()),
                mapper: OpenCodeEventMapper = OpenCodeEventMapper()) {
        self.installation = installation
        self.workingDirectory = workingDirectory
        self.settings = settings
        self.channel = channel
        self.mapper = mapper
    }

    public func knobs() async -> [HarnessKnob] { currentKnobs }

    public static func launch(installation: HarnessInstallation,
                              workingDirectory: URL) -> ProcessTransport.Launch {
        ProcessTransport.Launch(
            executable: installation.executable,
            arguments: ["acp", "--cwd", workingDirectory.path],
            workingDirectory: workingDirectory
        )
    }

    // MARK: - Ciclo de vida

    public func start(_ start: SessionStart) async throws -> AsyncStream<SessionUpdate> {
        let outputs = try await channel.start(
            Self.launch(installation: installation, workingDirectory: workingDirectory))

        let stream = AsyncStream<SessionUpdate> { continuation in
            self.continuation = continuation
            pump = Task { [weak self] in
                do {
                    for try await output in outputs {
                        await self?.consume(output)
                    }
                    await self?.finish(error: nil)
                } catch {
                    await self?.finish(error: String(describing: error))
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.stop() }
            }
        }

        try await handshake(start)
        return stream
    }

    private func handshake(_ start: SessionStart) async throws {
        _ = try await channel.send("initialize", .object([
            "protocolVersion": .int(1),
            "clientCapabilities": .object([
                "fs": .object([
                    "readTextFile": .bool(false),
                    "writeTextFile": .bool(false),
                ]),
                "terminal": .bool(false),
            ]),
        ]))

        let opened: JSONValue
        switch start {
        case .resume(let id), .fork(let id):

            opened = try await channel.send("session/load", .object([
                "sessionId": .string(id),
                "cwd": .string(workingDirectory.path),
                "mcpServers": .array([]),
            ]))
            harnessSessionID = id
        case .fresh:
            opened = try await channel.send("session/new", .object([
                "cwd": .string(workingDirectory.path),
                "mcpServers": .array([]),
            ]))
            harnessSessionID = opened["sessionId"]?.stringValue
        }

        currentKnobs = OpenCodeKnobs.parse(opened["configOptions"])

        for (id, value) in settings where !value.isEmpty {
            try? await applyRemotely(knob: id, value: value)
        }

        continuation?.yield(.event(.sessionInitialized(
            model: OpenCodeKnobs.model(in: currentKnobs),
            harnessSessionID: harnessSessionID ?? "")))
    }

    // MARK: - Entrada do CLI

    private func consume(_ output: ACPOutput) async {
        switch output {
        case .notification(let method, let params):
            guard method == "session/update", let update = params["update"] else { return }
            emit(mapper.map(update: update))

        case .request(let id, let method, let params):
            guard method == "session/request_permission" else {
                await refuse(id, method: method, raw: params)
                return
            }
            nextPermissionNumber += 1
            let key = "opencode-\(nextPermissionNumber)"
            inboundIDs[key] = id
            let request = OpenCodePermission.request(id: key, params: params)
            offeredOptions[key] = request.options
            continuation?.yield(.permission(request))

        case .malformed(let raw):
            continuation?.yield(.unrecognizedControl(
                UnrecognizedControl(requestID: nil, raw: raw, automaticReply: nil)))
        }
    }

    static let refusalMessage =
        "DevSpace não reconheceu este método e não consegue atendê-lo"

    private func refuse(_ id: JSONValue, method: String, raw: JSONValue) async {
        let replied = (try? await channel.refuse(id, Self.refusalMessage)) != nil
        continuation?.yield(.unrecognizedControl(UnrecognizedControl(
            requestID: id.stringValue ?? id.intValue.map(String.init),
            raw: .object(["method": .string(method), "params": raw]),
            automaticReply: replied ? Self.refusalMessage : nil)))
    }

    private func emit(_ output: MappedOutput) {
        for event in output.events { continuation?.yield(.event(event)) }
        for entry in output.entries { continuation?.yield(.entry(entry)) }
    }

    private func finish(error: String?) {
        continuation?.yield(.ended(error: error))
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Saída para o CLI

    public func send(_ turn: UserTurn) async throws {
        guard let sessionID = harnessSessionID else { throw ACPChannel.ChannelError.notStarted }

        var blocks: [JSONValue] = turn.attachments.map { attachment in
            .object([
                "type": .string(attachment.isImage ? "image" : "resource"),
                "mimeType": .string(attachment.mediaType),
                "data": .string(attachment.data.base64EncodedString()),
            ])
        }
        if !turn.text.isEmpty || blocks.isEmpty {
            blocks.append(.object(["type": .string("text"), "text": .string(turn.text)]))
        }

        continuation?.yield(.event(.turnStarted))

        /// `session/prompt` só responde quando o turno inteiro acaba, então ele
        /// não pode bloquear quem mandou — o resultado desagua no stream.
        self.turn = Task { [weak self, channel] in
            do {
                let result = try await channel.send("session/prompt", .object([
                    "sessionId": .string(sessionID),
                    "prompt": .array(blocks),
                ]))
                await self?.closeTurn(result)
            } catch is CancellationError {
                return
            } catch {
                await self?.failTurn(error)
            }
        }
    }

    private func closeTurn(_ result: JSONValue) {
        emit(mapper.turnResult(result))
    }

    private func failTurn(_ error: any Error) {
        emit(mapper.flush())
        continuation?.yield(.entry(TranscriptEntry(
            timestamp: Date(),
            kind: .turnResult(TurnResult(
                usage: .zero, stopReason: String(describing: error), isError: true)),
            raw: .object(["error": .string(String(describing: error))]))))
    }

    public func interrupt() async throws {
        guard let sessionID = harnessSessionID else { return }

        try await channel.notify("session/cancel", .object(["sessionId": .string(sessionID)]))
    }

    public func resolve(_ requestID: String, _ decision: PermissionDecision) async throws {
        guard let id = inboundIDs.removeValue(forKey: requestID) else {
            throw ACPChannel.ChannelError.unknownRequest
        }
        let offered = offeredOptions.removeValue(forKey: requestID) ?? []
        try await channel.respond(to: id, with: .object([
            "outcome": OpenCodePermission.outcome(for: decision, offered: offered),
        ]))
    }

    public func apply(knob id: String, value: String?) async throws {
        settings[id] = value
        guard let value, !value.isEmpty else { return }
        try await applyRemotely(knob: id, value: value)
    }

    private func applyRemotely(knob id: String, value: String) async throws {
        guard let sessionID = harnessSessionID else { return }
        let updated = try await channel.send("session/set_config_option", .object([
            "sessionId": .string(sessionID),
            "configId": .string(id),
            "value": .string(value),
        ]))
        let knobs = OpenCodeKnobs.parse(updated["configOptions"])
        if !knobs.isEmpty { currentKnobs = knobs }
    }

    public func stop() async {
        turn?.cancel()
        turn = nil
        pump?.cancel()
        pump = nil
        await channel.stop()
    }
}

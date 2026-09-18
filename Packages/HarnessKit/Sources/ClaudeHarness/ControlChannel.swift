import Foundation
import HarnessCore

public enum ChannelOutput: Sendable {

    case conversation(Data)

    case permissionRequest(PermissionRequest)

    case unrecognizedControl(UnrecognizedControl)
}

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

public actor ControlChannel {
    public enum ChannelError: Error, Equatable {

        case notStarted

        case timedOut

        case channelClosed

        case requestFailed(String)

        case unknownRequest(String)
    }

    private let transport: ProcessTransport
    private let requestTimeout: Duration
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]

    private var outstandingPermissions: Set<String> = []
    private var nextRequestNumber = 0
    private var liveness: Liveness = .notStarted

    private enum Liveness { case notStarted, running, closed }

    public init(transport: ProcessTransport, requestTimeout: Duration = .seconds(30)) {
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    public func start(
        _ launch: ProcessTransport.Launch
    ) async throws -> AsyncThrowingStream<ChannelOutput, Error> {
        let lines = try await transport.start(launch)
        liveness = .running

        return AsyncThrowingStream<ChannelOutput, Error> { continuation in
            let pump = Task { [weak self] in
                do {
                    for try await line in lines {
                        guard let self else { break }
                        if let output = await self.consume(line) {
                            continuation.yield(output)
                        }
                    }
                    await self?.markClosed()
                    continuation.finish()
                } catch {
                    await self?.markClosed()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in pump.cancel() }
        }
    }

    private func consume(_ line: Data) -> ChannelOutput? {
        switch ControlFrame.classify(line) {
        case .conversation:
            return .conversation(line)
        case .permissionRequest(let request):

            outstandingPermissions.insert(request.id)
            return .permissionRequest(request)
        case .response(let id, let result):
            resolve(id, result)
            return nil
        case .unansweredControlRequest(let id, let raw):
            return .unrecognizedControl(refuse(id, raw))
        case .unknownControl(let raw):

            return .unrecognizedControl(
                UnrecognizedControl(requestID: nil, raw: raw, automaticReply: nil)
            )
        }
    }

    static let refusalMessage =
        "DevSpace não reconheceu este control_request e não consegue atendê-lo"

    private func refuse(_ requestID: String, _ raw: JSONValue) -> UnrecognizedControl {
        do {
            try transport.writeSync(
                ControlErrorResponse(requestID: requestID, message: Self.refusalMessage).data()
            )
            return UnrecognizedControl(
                requestID: requestID, raw: raw, automaticReply: Self.refusalMessage
            )
        } catch {

            return UnrecognizedControl(requestID: requestID, raw: raw, automaticReply: nil)
        }
    }

    private func resolve(_ id: String, _ result: ControlResponseResult) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        switch result {
        case .success(let payload): continuation.resume(returning: payload)
        case .failure(let message): continuation.resume(throwing: ChannelError.requestFailed(message))
        }
    }

    private func failAllPending(_ error: ChannelError) {
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting { continuation.resume(throwing: error) }
    }

    private func markClosed() {
        liveness = .closed
        failAllPending(.channelClosed)

        outstandingPermissions.removeAll()
    }

    public func send(_ request: OutboundControlRequest) async throws -> JSONValue {
        switch liveness {
        case .notStarted: throw ChannelError.notStarted
        case .closed: throw ChannelError.channelClosed
        case .running: break
        }
        nextRequestNumber += 1
        let id = "devspace-\(nextRequestNumber)"
        let data = try request.requestData(requestID: id)

        let timeout = Task { [requestTimeout] in
            try? await Task.sleep(for: requestTimeout)
            if !Task.isCancelled { timeOut(id) }
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try transport.writeSync(data)
            } catch {
                pending.removeValue(forKey: id)

                continuation.resume(throwing: ChannelError.channelClosed)
            }
        }
    }

    private func timeOut(_ id: String) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: ChannelError.timedOut)
    }

    public func respond(to requestID: String, with decision: PermissionDecision) throws {
        switch liveness {
        case .notStarted: throw ChannelError.notStarted
        case .closed: throw ChannelError.channelClosed
        case .running: break
        }

        guard outstandingPermissions.contains(requestID) else {
            throw ChannelError.unknownRequest(requestID)
        }
        let data = try decision.responseData(requestID: requestID)
        do {
            try transport.writeSync(data)
        } catch {

            throw ChannelError.channelClosed
        }

        outstandingPermissions.remove(requestID)
    }

    public func writeTurn(_ line: Data) async throws {
        try await transport.write(line)
    }

    public func endInput() async {
        liveness = .closed
        await transport.endInput()
    }

    public func stop() async {

        liveness = .closed
        failAllPending(.channelClosed)
        outstandingPermissions.removeAll()
        await transport.terminate()
    }
}

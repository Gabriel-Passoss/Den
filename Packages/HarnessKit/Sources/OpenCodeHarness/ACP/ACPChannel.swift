import Foundation
import HarnessCore

public enum ACPOutput: Sendable {

    case notification(method: String, params: JSONValue)

    case request(id: JSONValue, method: String, params: JSONValue)

    case malformed(JSONValue)
}

public actor ACPChannel {
    public enum ChannelError: Error, Equatable {
        case notStarted
        case timedOut
        case channelClosed
        case requestFailed(code: Int, message: String)

        case unknownRequest
    }

    private let transport: ProcessTransport
    private let requestTimeout: Duration
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]

    private var outstandingInbound: Set<String> = []
    private var nextRequestID = 0
    private var liveness: Liveness = .notStarted
    private var closedBy: (any Error)?

    private enum Liveness { case notStarted, running, closed }

    public init(transport: ProcessTransport, requestTimeout: Duration = .seconds(120)) {
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    public func start(
        _ launch: ProcessTransport.Launch
    ) async throws -> AsyncThrowingStream<ACPOutput, Error> {
        let lines = try await transport.start(launch)
        liveness = .running

        return AsyncThrowingStream<ACPOutput, Error> { continuation in
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
                    await self?.markClosed(by: error)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in pump.cancel() }
        }
    }

    private func consume(_ line: Data) -> ACPOutput? {
        switch ACPFrame.classify(line) {
        case .notification(let method, let params):
            return .notification(method: method, params: params)
        case .request(let id, let method, let params):
            outstandingInbound.insert(Self.key(id))
            return .request(id: id, method: method, params: params)
        case .response(let id, let result):
            resolve(id, result)
            return nil
        case .malformed(let raw):
            return .malformed(raw)
        }
    }

    private static func key(_ id: JSONValue) -> String {
        if let number = id.intValue { return "i\(number)" }
        return "s\(id.stringValue ?? "?")"
    }

    private func resolve(_ id: Int, _ result: ACPResult) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        switch result {
        case .success(let payload):
            continuation.resume(returning: payload)
        case .failure(let code, let message):
            continuation.resume(throwing: ChannelError.requestFailed(code: code, message: message))
        }
    }

    /// `cause` is why the CLI went away, such as its exit status and stderr.
    /// Requests waiting on it, and any sent after, fail with that instead of a
    /// bare `channelClosed`.
    private func markClosed(by cause: (any Error)? = nil) {
        liveness = .closed
        closedBy = cause
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting {
            continuation.resume(throwing: cause ?? ChannelError.channelClosed)
        }
        outstandingInbound.removeAll()
    }

    private func requireRunning() throws {
        switch liveness {
        case .notStarted: throw ChannelError.notStarted
        case .closed: throw closedBy ?? ChannelError.channelClosed
        case .running: break
        }
    }

    @discardableResult
    public func send(_ method: String, _ params: JSONValue = .object([:])) async throws -> JSONValue {
        try requireRunning()
        nextRequestID += 1
        let id = nextRequestID
        let data = try ACPWire.request(id: id, method: method, params: params)

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

    private func timeOut(_ id: Int) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: ChannelError.timedOut)
    }

    public func notify(_ method: String, _ params: JSONValue = .object([:])) throws {
        try requireRunning()
        try transport.writeSync(ACPWire.notification(method: method, params: params))
    }

    public func respond(to id: JSONValue, with result: JSONValue) throws {
        try requireRunning()
        guard outstandingInbound.contains(Self.key(id)) else { throw ChannelError.unknownRequest }
        try transport.writeSync(try ACPWire.response(id: id, result: result))
        outstandingInbound.remove(Self.key(id))
    }

    public func refuse(_ id: JSONValue, _ message: String) throws {
        try requireRunning()
        guard outstandingInbound.contains(Self.key(id)) else { throw ChannelError.unknownRequest }
        try transport.writeSync(
            try ACPWire.errorResponse(id: id, code: ACPWire.methodNotFound, message: message))
        outstandingInbound.remove(Self.key(id))
    }

    public func stop() async {
        markClosed()
        await transport.terminate()
    }
}

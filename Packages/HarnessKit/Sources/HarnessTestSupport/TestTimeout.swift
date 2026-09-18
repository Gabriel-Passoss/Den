import Foundation

public struct TimedOut: Error, Equatable {
    public init() {}
}

@discardableResult
public func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let once = OnceContinuation(continuation)
        Task {
            do {
                let value = try await operation()
                await once.resume(returning: value)
            } catch {
                await once.resume(throwing: error)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await once.resume(throwing: TimedOut())
        }
    }
}

private actor OnceContinuation<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

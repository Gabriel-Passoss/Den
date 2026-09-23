import Foundation
@testable import DevSpace

func withTemporaryCache(_ body: (SessionCache) throws -> Void) rethrows {
    let suite = "DevSpaceTests." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else {
        fatalError("não consegui criar o suite \(suite)")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(SessionCache(defaults: defaults))
}

let scratchCache: SessionCache = {
    let suite = "DevSpaceTests.scratch"
    guard let defaults = UserDefaults(suiteName: suite) else {
        fatalError("não consegui criar o suite \(suite)")
    }
    defaults.removePersistentDomain(forName: suite)
    return SessionCache(defaults: defaults)
}()

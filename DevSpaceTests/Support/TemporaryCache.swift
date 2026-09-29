import Foundation
@testable import DevSpace

func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suite = "DevSpaceTests." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else {
        fatalError("could not create suite \(suite)")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}

func withTemporaryCache(_ body: (SessionCache) throws -> Void) rethrows {
    try withTemporaryDefaults { try body(SessionCache(defaults: $0)) }
}

let scratchCache: SessionCache = {
    let suite = "DevSpaceTests.scratch"
    guard let defaults = UserDefaults(suiteName: suite) else {
        fatalError("could not create suite \(suite)")
    }
    defaults.removePersistentDomain(forName: suite)
    return SessionCache(defaults: defaults)
}()

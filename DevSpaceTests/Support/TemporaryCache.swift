import Foundation
@testable import DevSpace

func withTemporaryCache(_ body: (SessionCache) throws -> Void) rethrows {
    let scratch = ScratchDefaults()
    defer { scratch.remove() }
    try body(SessionCache(defaults: scratch.defaults))
}

let scratchCache: SessionCache = {
    let suite = "DevSpaceTests.scratch"
    guard let defaults = UserDefaults(suiteName: suite) else {
        fatalError("could not create suite \(suite)")
    }
    defaults.removePersistentDomain(forName: suite)
    return SessionCache(defaults: defaults)
}()

import Foundation
import DenStore
@testable import Den

func withTemporaryCache(_ body: (SessionCache) throws -> Void) rethrows {
    try body(SessionCache(scratchRepositories()))
}

let scratchCache = SessionCache(scratchRepositories())

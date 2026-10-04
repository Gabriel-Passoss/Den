import Foundation
import HarnessCore
import DenStore

nonisolated func scratchRepositories() -> Repositories {
    do {
        return try DenStore.inMemory()
    } catch {
        fatalError("could not open an in-memory store: \(error)")
    }
}

nonisolated func scratchSessions() -> any SessionRepository {
    scratchRepositories().sessions
}

import Foundation
import Synchronization

nonisolated struct ScratchDefaults {
    private static let pool = Mutex<(free: [String], made: Int)>(([], 0))

    private static let checkout: String = {
        let path = URL(filePath: #filePath).deletingLastPathComponent().path
        let hash = path.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return String(hash, radix: 16)
    }()

    let suite: String
    let defaults: UserDefaults

    init() {
        let suite = Self.pool.withLock { pool in
            if let reused = pool.free.popLast() { return reused }
            pool.made += 1
            return "DenTests.\(Self.checkout).\(pool.made)"
        }
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("could not create suite \(suite)")
        }
        defaults.removePersistentDomain(forName: suite)
        self.suite = suite
        self.defaults = defaults
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        Self.pool.withLock { $0.free.append(suite) }
    }
}

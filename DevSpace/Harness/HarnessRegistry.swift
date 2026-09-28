import Foundation
import HarnessCore
import ClaudeHarness
import OpenCodeHarness

nonisolated struct HarnessRegistry {
    let harnesses: [any Harness]

    static let standard = HarnessRegistry(harnesses: [ClaudeCodeHarness(), OpenCodeHarness()])

    var ids: [HarnessID] { harnesses.map(\.id) }

    var fallback: HarnessID { harnesses.first?.id ?? .claudeCode }

    func harness(for id: HarnessID) -> (any Harness)? {
        harnesses.first { $0.id == id }
    }

    func displayName(for id: HarnessID) -> String {
        harness(for: id)?.displayName ?? id.rawValue
    }

    private static let defaultKey = "DevSpace.defaultHarness"

    func preferred(in defaults: UserDefaults) -> HarnessID {
        guard let raw = defaults.string(forKey: Self.defaultKey) else { return fallback }
        let id = HarnessID(rawValue: raw)
        return harness(for: id) == nil ? fallback : id
    }

    func setPreferred(_ harness: HarnessID, in defaults: UserDefaults) {
        defaults.set(harness.rawValue, forKey: Self.defaultKey)
    }
}

import Foundation
import HarnessCore
import ClaudeHarness
import OpenCodeHarness

nonisolated enum HarnessRegistry {

    static let all: [any Harness] = [ClaudeCodeHarness(), OpenCodeHarness()]

    static let fallback: HarnessID = .claudeCode

    static func harness(for id: HarnessID) -> (any Harness)? {
        all.first { $0.id == id }
    }

    static func displayName(for id: HarnessID) -> String {
        harness(for: id)?.displayName ?? id.rawValue
    }

    private static let defaultKey = "DevSpace.defaultHarness"

    static func preferred(in defaults: UserDefaults) -> HarnessID {
        guard let raw = defaults.string(forKey: defaultKey) else { return fallback }
        let id = HarnessID(rawValue: raw)
        return harness(for: id) == nil ? fallback : id
    }

    static func setPreferred(_ harness: HarnessID, in defaults: UserDefaults) {
        defaults.set(harness.rawValue, forKey: defaultKey)
    }

    static var preferred: HarnessID {
        get { preferred(in: .standard) }
        set { setPreferred(newValue, in: .standard) }
    }
}

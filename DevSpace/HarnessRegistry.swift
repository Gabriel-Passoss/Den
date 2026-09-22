import Foundation
import HarnessCore
import ClaudeHarness
import OpenCodeHarness

/// O único lugar acima do HarnessKit que conhece os adaptadores concretos.
/// Tudo o mais no app fala `HarnessID` e o protocolo `Harness`.
enum HarnessRegistry {

    static let all: [any Harness] = [ClaudeCodeHarness(), OpenCodeHarness()]

    static let fallback: HarnessID = .claudeCode

    static func harness(for id: HarnessID) -> (any Harness)? {
        all.first { $0.id == id }
    }

    static func displayName(for id: HarnessID) -> String {
        harness(for: id)?.displayName ?? id.rawValue
    }

    private static let defaultKey = "DevSpace.defaultHarness"

    static var preferred: HarnessID {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultKey) else { return fallback }
            let id = HarnessID(rawValue: raw)
            return harness(for: id) == nil ? fallback : id
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultKey) }
    }
}

import Foundation
@testable import Den

struct TestEnvironment: RootedEnvironment {
    let root: URL
    let defaults: UserDefaults
    let registry: HarnessRegistry

    init(root: URL, defaults: UserDefaults, registry: HarnessRegistry = .standard) {
        self.root = root
        self.defaults = defaults
        self.registry = registry
    }
}

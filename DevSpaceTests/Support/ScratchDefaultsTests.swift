import Testing
import Foundation

@Test func suitesAreReusedInsteadOfPilingUp() {
    var names: Set<String> = []
    for _ in 0..<20 {
        let scratch = ScratchDefaults()
        scratch.defaults.set("value", forKey: "key")
        names.insert(scratch.suite)
        scratch.remove()
    }
    // Other tests may borrow from the pool meanwhile, but twenty suites in a
    // row must not mean twenty files.
    #expect(names.count < 20)
}

@Test func aFreedSuiteComesBackEmpty() throws {
    let scratch = ScratchDefaults()
    scratch.defaults.set("value", forKey: "key")
    scratch.remove()

    let reopened = try #require(UserDefaults(suiteName: scratch.suite))
    #expect(reopened.string(forKey: "key") == nil)
}

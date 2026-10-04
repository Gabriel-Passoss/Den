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
    #expect(names.count < 20,
            "twenty suites in a row must reuse pooled names rather than leave twenty plists behind")
}

@Test func aFreedSuiteComesBackEmpty() throws {
    let scratch = ScratchDefaults()
    scratch.defaults.set("value", forKey: "key")
    scratch.remove()

    let reopened = try #require(UserDefaults(suiteName: scratch.suite))
    #expect(reopened.string(forKey: "key") == nil)
}

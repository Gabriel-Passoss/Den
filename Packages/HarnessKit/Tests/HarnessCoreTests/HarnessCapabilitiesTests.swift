import Testing
import HarnessCore

@Test func capabilitiesDefaultToTheConservativeAnswer() {

    let c = HarnessCapabilities()
    #expect(!c.routesPermissionRequests)
    #expect(!c.canInterrupt)
    #expect(!c.canSetPermissionMode)
    #expect(!c.canSetModelInSession)
    #expect(!c.canResumeSession)
    #expect(!c.canForkSession)
}

@Test func capabilitiesAreValuesAndCompareByContent() {
    let a = HarnessCapabilities(canInterrupt: true)
    let b = HarnessCapabilities(canInterrupt: true)
    #expect(a == b)
    #expect(a != HarnessCapabilities())
}

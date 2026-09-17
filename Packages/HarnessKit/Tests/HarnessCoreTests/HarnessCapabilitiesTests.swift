import Testing
import HarnessCore

@Test func capabilitiesDefaultToTheConservativeAnswer() {
    // Um harness novo não suporta nada até declarar que suporta. A UI esconde
    // o que não foi declarado, em vez de oferecer botões que falham.
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

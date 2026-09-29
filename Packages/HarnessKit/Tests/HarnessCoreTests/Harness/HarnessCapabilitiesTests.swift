import Testing
import HarnessCore

@Test func capabilitiesDefaultToTheConservativeAnswer() {

    let c = HarnessCapabilities()
    #expect(!c.routesPermissionRequests)
    #expect(!c.canInterrupt)
    #expect(!c.canSetPermissionMode)
    #expect(!c.canSetModelInSession)
    #expect(!c.canSetEffortInSession)
    #expect(!c.canResumeSession)
    #expect(!c.canForkSession)
}

@Test func eachKnobCategoryAnswersToItsOwnCapability() {
    let effortOnly = HarnessCapabilities(canSetEffortInSession: true)
    #expect(effortOnly.canChangeInSession(.effort))
    #expect(!effortOnly.canChangeInSession(.model))
    #expect(!effortOnly.canChangeInSession(.mode))

    #expect(HarnessCapabilities(canSetModelInSession: true).canChangeInSession(.model))
    #expect(HarnessCapabilities(canSetPermissionMode: true).canChangeInSession(.mode))
}

@Test func capabilitiesAreValuesAndCompareByContent() {
    let a = HarnessCapabilities(canInterrupt: true)
    let b = HarnessCapabilities(canInterrupt: true)
    #expect(a == b)
    #expect(a != HarnessCapabilities())
}

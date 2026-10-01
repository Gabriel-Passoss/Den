import Testing
@testable import Den

@Test func lessThanHalfTheWindowIsCalm() {
    #expect(ContextLevel(fraction: 0) == .calm)
    #expect(ContextLevel(fraction: 0.49) == .calm)
}

@Test func fromHalfTheWindowItIsAWarning() {
    #expect(ContextLevel(fraction: 0.5) == .warning)
    #expect(ContextLevel(fraction: 0.79) == .warning)
}

@Test func fromEightyPercentItIsCritical() {
    #expect(ContextLevel(fraction: 0.8) == .critical)
    #expect(ContextLevel(fraction: 1) == .critical)
}

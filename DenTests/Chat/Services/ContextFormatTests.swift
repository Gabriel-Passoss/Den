import Testing
@testable import Den

@Test func fewTokensAreWrittenInFull() {
    #expect(ContextFormat.tokens(385) == "385")
}

@Test func thousandsKeepOneDecimalWhenItMatters() {
    #expect(ContextFormat.tokens(13_500) == "13,5k")
    #expect(ContextFormat.tokens(203_500) == "203,5k")
    #expect(ContextFormat.tokens(27_000) == "27k")
}

@Test func millionsAreWrittenInMillions() {
    #expect(ContextFormat.tokens(1_000_000) == "1M")
    #expect(ContextFormat.tokens(1_500_000) == "1,5M")
}

@Test func theShareKeepsOneDecimalWhenItMatters() {
    #expect(ContextFormat.percent(0.159) == "15,9%")
    #expect(ContextFormat.percent(0.2) == "20%")
    #expect(ContextFormat.percent(0) == "0%")
}

@Test func theSummaryReadsUsedOverWindow() {
    #expect(ContextFormat.summary(used: 203_000, window: 1_000_000) == "203k / 1M (20,3%)")
}

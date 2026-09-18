import Testing
import HarnessCore
@testable import ClaudeHarness

@Test func theClaudeCodeHarnessIDKeepsItsSpelling() {
    #expect(HarnessID.claudeCode.rawValue == "claude-code")
}

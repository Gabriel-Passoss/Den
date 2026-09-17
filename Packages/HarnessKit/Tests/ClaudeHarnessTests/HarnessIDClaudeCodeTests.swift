import Testing
import HarnessCore
@testable import ClaudeHarness

/// `HarnessID.claudeCode` mora em `ClaudeHarness`, não em `HarnessCore`: o
/// conjunto de ids é aberto justamente para que o núcleo não precise
/// conhecer harness nenhum (spec §7.1). Este é o único lugar onde a grafia
/// exata ("claude-code") é verificada.
@Test func theClaudeCodeHarnessIDKeepsItsSpelling() {
    #expect(HarnessID.claudeCode.rawValue == "claude-code")
}

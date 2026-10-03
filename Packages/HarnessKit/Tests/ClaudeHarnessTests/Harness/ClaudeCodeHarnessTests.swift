import Testing
@testable import ClaudeHarness

@Test func aQuickPromptRunsTheInstructionOnHaiku() throws {
    let args = try #require(ClaudeCodeHarness().quickPromptArguments(for: "diga oi"))
    let prompt = try #require(args.firstIndex(of: "-p"))
    #expect(args[args.index(after: prompt)] == "diga oi")
    let model = try #require(args.firstIndex(of: "--model"))
    #expect(args[args.index(after: model)] == "haiku")
}

@Test func aQuickPromptLeavesTheUsersSetupAndToolsOut() throws {
    let args = try #require(ClaudeCodeHarness().quickPromptArguments(for: "x"))
    #expect(args.contains("--safe-mode"))
    #expect(args.contains("--no-session-persistence"))
    let tools = try #require(args.firstIndex(of: "--tools"))
    #expect(args[args.index(after: tools)] == "")
}

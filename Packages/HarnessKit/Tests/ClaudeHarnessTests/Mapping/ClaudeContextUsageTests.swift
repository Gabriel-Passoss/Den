import Testing
import Foundation
import HarnessCore
import HarnessTestSupport
@testable import ClaudeHarness

private func fixture() throws -> JSONValue {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/context-usage",
                                             withExtension: "json"))
    return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
}

private func parsed() throws -> ContextUsage {
    try #require(ClaudeContextUsage.parse(try fixture()))
}

private func detail(_ category: ContextCategory, in usage: ContextUsage) -> ContextDetail? {
    usage.details.first { $0.category == category }
}

@Test func theTotalsAreTheOnesTheCLIReports() throws {
    let usage = try parsed()
    #expect(usage.usedTokens == 27_352)
    #expect(usage.windowTokens == 200_000)
    #expect(!usage.isEstimate)
}

@Test func eachCategoryKeepsItsOrderAndTokens() throws {
    let usage = try parsed()
    #expect(usage.slices.map(\.category) == [
        .systemPrompt, .systemTools, .mcpTools, .systemTools,
        .customAgents, .memoryFiles, .skills, .messages, .freeSpace,
    ])
    #expect(usage.slices.map(\.tokens) == [6374, 17456, 11610, 23786, 49, 268, 2261, 944, 172_648])
}

@Test func deferredToolsAreFlaggedAndNotTheirOwnCategory() throws {
    let usage = try parsed()
    let deferred = usage.slices.filter(\.isDeferred)
    #expect(deferred.map(\.category) == [.mcpTools, .systemTools])
}

@Test func anUnknownCategoryKeepsItsName() throws {
    let response = JSONValue.object([
        "totalTokens": .int(10), "maxTokens": .int(100),
        "categories": .array([.object([
            "name": .string("Something new"), "tokens": .int(10), "kind": .string("used"),
        ])]),
    ])
    let usage = try #require(ClaudeContextUsage.parse(response))
    #expect(usage.slices.first?.category == .other("Something new"))
}

@Test func aResponseWithoutTotalsIsNotAUsage() {
    #expect(ClaudeContextUsage.parse(.object(["categories": .array([])])) == nil)
}

@Test func mcpToolsAreListedUnderTheirServerWithoutThePrefix() throws {
    let tools = try #require(detail(.mcpTools, in: try parsed()))
    #expect(tools.items == [
        ContextItem(name: "memory_query", group: "ai-memory", tokens: 1057, isDeferred: true),
        ContextItem(name: "memory_status", group: "ai-memory", tokens: 227, isDeferred: false),
        ContextItem(name: "query-docs", group: "context7", tokens: 473, isDeferred: true),
    ])
}

@Test func memoryFilesAgentsAndSkillsAreListed() throws {
    let usage = try parsed()
    #expect(detail(.memoryFiles, in: usage)?.items.map(\.name)
            == ["/Users/someone/.claude/CLAUDE.md", "/Users/someone/project/CLAUDE.md"])
    #expect(detail(.customAgents, in: usage)?.items.map(\.name)
            == ["code-simplifier:code-simplifier"])
    #expect(detail(.skills, in: usage)?.items
            == [ContextItem(name: "tdd", group: "userSettings", tokens: 1),
                ContextItem(name: "commit-commands:commit", group: "commit-commands", tokens: 8)])
}

private let answeringCLI = #"""
#!/bin/sh
while IFS= read -r l; do
  case "$l" in
    *'"subtype":"get_context_usage"'*)
      id=$(printf '%s' "$l" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')
      printf '{"type":"control_response","response":{"subtype":"success","request_id":"%s","response":{"totalTokens":4200,"maxTokens":1000000,"categories":[{"name":"Messages","tokens":4200,"kind":"used"}]}}}\n' "$id"
      ;;
  esac
done
"""#

private let refusingCLI = #"""
#!/bin/sh
while IFS= read -r l; do
  id=$(printf '%s' "$l" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')
  printf '{"type":"control_response","response":{"subtype":"error","request_id":"%s","error":"unsupported"}}\n' "$id"
done
"""#

private func session(running script: String) throws -> ClaudeSession {
    let executable = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "fake-claude-\(UUID().uuidString)")
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                          ofItemAtPath: executable.path)
    return ClaudeSession(
        installation: HarnessInstallation(executable: executable.path, version: "2.1.274"),
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
}

@Test func theSessionAsksTheCLIWhatFillsTheContext() async throws {
    let subject = try session(running: answeringCLI)
    let updates = try await subject.start(.fresh)
    let drain = Task { for await _ in updates {} }

    let usage = try await withTimeout(seconds: 5) { await subject.contextUsage() }
    await subject.stop()
    drain.cancel()

    #expect(usage?.usedTokens == 4_200)
    #expect(usage?.windowTokens == 1_000_000)
    #expect(usage?.slices == [ContextSlice(category: .messages, tokens: 4_200)])
}

@Test func aCLIThatCannotAnswerLeavesTheUsageUnknown() async throws {
    let subject = try session(running: refusingCLI)
    let updates = try await subject.start(.fresh)
    let drain = Task { for await _ in updates {} }

    let usage = try await withTimeout(seconds: 5) { await subject.contextUsage() }
    await subject.stop()
    drain.cancel()

    #expect(usage == nil)
}

import Testing
@testable import HarnessProbeArguments

@Suite("parseRecordArguments")
struct RecordArgumentsTests {
    @Test("accepts a valid line with --out")
    func acceptsAValidLineWithOut() throws {
        let value = try parseRecordArguments([
            "--prompt", "oi", "--cwd", "/tmp/probe-scratch", "--out", "/tmp/out.ndjson",
        ]).get()
        #expect(value == RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: "/tmp/out.ndjson"))
    }

    @Test("accepts a valid line without --out")
    func acceptsAValidLineWithoutOut() throws {
        let value = try parseRecordArguments(["--prompt", "oi", "--cwd", "/tmp/probe-scratch"]).get()
        #expect(value == RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: nil))
    }

    @Test("accepts the flags in any order")
    func acceptsFlagsInAnyOrder() throws {
        let value = try parseRecordArguments([
            "--cwd", "/tmp/probe-scratch", "--out", "/tmp/out.ndjson", "--prompt", "oi",
        ]).get()
        #expect(value == RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: "/tmp/out.ndjson"))
    }

    @Test("--prompt followed by another flag does not become its value")
    func promptFollowedByAnotherFlagIsNotItsValue() {

        let result = parseRecordArguments(["--prompt", "--cwd", "/tmp/probe-scratch"])
        #expect(result == .failure(.missingValue(flag: "--prompt")))
    }

    @Test("literal reproduction of the reported incident's command line")
    func literalReproductionOfTheReportedIncident() {

        let result = parseRecordArguments([
            "--prompt", "--cwd", "/tmp/probe-scratch", "--out", "/tmp/x.ndjson",
        ])
        #expect(result == .failure(.missingValue(flag: "--prompt")))
    }

    @Test("--cwd at the end of the list, with no value")
    func cwdAtTheEndOfTheListWithNoValue() {

        let result = parseRecordArguments(["--prompt", "oi", "--cwd"])
        #expect(result == .failure(.missingValue(flag: "--cwd")))
    }

    @Test("an empty --cwd does not silently mean \"here\"")
    func emptyCwdDoesNotSilentlyMeanHere() {

        let result = parseRecordArguments(["--prompt", "oi", "--cwd", ""])
        #expect(result == .failure(.emptyValue(flag: "--cwd")))
    }

    @Test("an empty --prompt is rejected")
    func emptyPromptIsRejected() {
        let result = parseRecordArguments(["--prompt", "", "--cwd", "/tmp/probe-scratch"])
        #expect(result == .failure(.emptyValue(flag: "--prompt")))
    }

    @Test("an empty --out is rejected too")
    func emptyOutIsAlsoRejected() {
        let result = parseRecordArguments(["--prompt", "oi", "--cwd", "/tmp/probe-scratch", "--out", ""])
        #expect(result == .failure(.emptyValue(flag: "--out")))
    }

    @Test("a whitespace-only value is rejected, not just an empty string")
    func whitespaceOnlyValueIsRejected() {
        let result = parseRecordArguments(["--prompt", "oi", "--cwd", "   "])
        #expect(result == .failure(.emptyValue(flag: "--cwd")))
    }

    @Test("tabs and newlines also count as blank")
    func tabsAndNewlinesAlsoCountAsBlank() {
        let result = parseRecordArguments(["--prompt", "oi", "--cwd", "\t\n  "])
        #expect(result == .failure(.emptyValue(flag: "--cwd")))
    }

    @Test("--out followed by another flag does not become a value either")
    func outFollowedByAnotherFlagIsNotAValueEither() {
        let result = parseRecordArguments(["--prompt", "oi", "--cwd", "/tmp/probe-scratch", "--out", "--prompt"])
        #expect(result == .failure(.missingValue(flag: "--out")))
    }

    @Test("an unknown flag is rejected, not ignored")
    func unknownFlagIsRejectedNotIgnored() {
        let result = parseRecordArguments([
            "--prompt", "oi", "--cwd", "/tmp/probe-scratch", "--bogus", "y",
        ])
        #expect(result == .failure(.unknownFlag("--bogus")))
    }

    @Test("--prompt missing")
    func missingPrompt() {
        let result = parseRecordArguments(["--cwd", "/tmp/probe-scratch"])
        #expect(result == .failure(.missingRequired(flag: "--prompt")))
    }

    @Test("--cwd missing")
    func missingCwd() {
        let result = parseRecordArguments(["--prompt", "oi"])
        #expect(result == .failure(.missingRequired(flag: "--cwd")))
    }

    @Test("empty argument list")
    func emptyArgumentList() {
        let result = parseRecordArguments([])
        #expect(result == .failure(.missingRequired(flag: "--prompt")))
    }
}

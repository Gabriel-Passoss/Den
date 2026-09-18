import Testing
@testable import HarnessProbeArguments

@Suite("parsePermissionArguments")
struct PermissionArgumentsTests {
    @Test("accepts --prompt and --cwd")
    func acceptsPromptAndCwd() throws {
        let value = try parsePermissionArguments(["--prompt", "crie x.txt", "--cwd", "/tmp/probe"]).get()
        #expect(value == PermissionArguments(prompt: "crie x.txt", cwd: "/tmp/probe"))
    }

    @Test("accepts the flags in any order")
    func acceptsFlagsInAnyOrder() throws {
        let value = try parsePermissionArguments(["--cwd", "/tmp/probe", "--prompt", "oi"]).get()
        #expect(value == PermissionArguments(prompt: "oi", cwd: "/tmp/probe"))
    }

    @Test("--out is not a flag of this subcommand")
    func outIsRejectedHere() {
        let result = parsePermissionArguments([
            "--prompt", "oi", "--cwd", "/tmp/probe", "--out", "/tmp/x.ndjson",
        ])
        #expect(result == .failure(.unknownFlag("--out")))
    }

    @Test("a flag is never the value of the flag before it")
    func aFlagIsNeverAValue() {
        let result = parsePermissionArguments(["--prompt", "--cwd", "/tmp/probe"])
        #expect(result == .failure(.missingValue(flag: "--prompt")))
    }

    @Test("an empty --cwd does not silently mean here")
    func emptyCwdIsRejected() {
        let result = parsePermissionArguments(["--prompt", "oi", "--cwd", ""])
        #expect(result == .failure(.emptyValue(flag: "--cwd")))
    }

    @Test("--prompt missing")
    func missingPrompt() {
        #expect(parsePermissionArguments(["--cwd", "/tmp/probe"])
            == .failure(.missingRequired(flag: "--prompt")))
    }

    @Test("--cwd missing")
    func missingCwd() {
        #expect(parsePermissionArguments(["--prompt", "oi"])
            == .failure(.missingRequired(flag: "--cwd")))
    }
}

@Suite("parsePermissionAnswer")
struct PermissionAnswerTests {
    @Test("the recognized yeses, in both languages and any case")
    func recognizedYeses() {
        for yes in ["s", "S", "sim", "Sim", "y", "yes", "a", "allow", "p", "permitir", "  sim  "] {
            #expect(parsePermissionAnswer(yes) == .allow, "\(yes) deveria permitir")
        }
    }

    @Test("an empty line denies")
    func emptyLineDenies() {
        #expect(parsePermissionAnswer("") == .deny)
        #expect(parsePermissionAnswer("   ") == .deny)
    }

    @Test("EOF denies")
    func eofDenies() {
        #expect(parsePermissionAnswer(nil) == .deny)
    }

    @Test("anything unrecognized denies, including near misses")
    func unrecognizedDenies() {
        for no in ["n", "não", "no", "sempre", "si", "ss", "yep", "sim por favor", "1", "allowed"] {
            #expect(parsePermissionAnswer(no) == .deny, "\(no) não deveria permitir")
        }
    }
}

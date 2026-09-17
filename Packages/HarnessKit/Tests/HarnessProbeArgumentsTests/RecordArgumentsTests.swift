import Testing
@testable import HarnessProbeArguments

/// Estes testes existem porque o parser anterior falhou em produção duas
/// vezes: uma vez com `--cwd` no fim da lista caindo no cwd real do shell, e
/// outra com `--prompt --cwd <dir>` fazendo um único token servir de valor
/// para uma flag e de flag reconhecida para outra ao mesmo tempo — nos dois
/// casos um `claude` de verdade foi lançado quando um erro de uso era
/// esperado. Todos os casos aqui exercitam só `parseRecordArguments`, sem
/// nunca subir um processo.
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
        // O incidente relatado pelo revisor: um escaneamento por-flag deixava
        // este único token "--cwd" servir ao mesmo tempo de valor de
        // --prompt e de flag --cwd de verdade, passando os dois guards e
        // lançando o `claude` real.
        let result = parseRecordArguments(["--prompt", "--cwd", "/tmp/probe-scratch"])
        #expect(result == .failure(.missingValue(flag: "--prompt")))
    }

    @Test("literal reproduction of the reported incident's command line")
    func literalReproductionOfTheReportedIncident() {
        // `harness-probe record --prompt --cwd /tmp/probe-scratch --out
        // /tmp/x.ndjson`, exatamente como o revisor rodou esperando falhar
        // antes de spawnar qualquer processo — e em vez disso gastou crédito
        // de API de verdade contra o parser anterior.
        let result = parseRecordArguments([
            "--prompt", "--cwd", "/tmp/probe-scratch", "--out", "/tmp/x.ndjson",
        ])
        #expect(result == .failure(.missingValue(flag: "--prompt")))
    }

    @Test("--cwd at the end of the list, with no value")
    func cwdAtTheEndOfTheListWithNoValue() {
        // O incidente do round anterior: --cwd como último token.
        let result = parseRecordArguments(["--prompt", "oi", "--cwd"])
        #expect(result == .failure(.missingValue(flag: "--cwd")))
    }

    @Test("an empty --cwd does not silently mean \"here\"")
    func emptyCwdDoesNotSilentlyMeanHere() {
        // "".hasPrefix("--") é false, então sem esta guarda um --cwd vazio
        // passava a checagem de token como valor "válido", e
        // URL(fileURLWithPath: "") resolve para o cwd real do processo — o
        // mesmo resultado que --cwd obrigatório existe para impedir,
        // alcançado por uma variável de shell vazia em vez de um token
        // malposicionado. Vetor realista:
        // `harness-probe record --prompt "..." --cwd "$SCRATCH_DIR"` com
        // SCRATCH_DIR vazia ou não setada.
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

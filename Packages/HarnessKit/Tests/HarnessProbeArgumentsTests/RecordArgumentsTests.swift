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
    @Test("aceita uma linha válida com --out")
    func aceitaLinhaValidaComOut() throws {
        let value = try parseRecordArguments([
            "--prompt", "oi", "--cwd", "/tmp/probe-scratch", "--out", "/tmp/out.ndjson",
        ]).get()
        #expect(value == RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: "/tmp/out.ndjson"))
    }

    @Test("aceita uma linha válida sem --out")
    func aceitaLinhaValidaSemOut() throws {
        let value = try parseRecordArguments(["--prompt", "oi", "--cwd", "/tmp/probe-scratch"]).get()
        #expect(value == RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: nil))
    }

    @Test("aceita as flags em qualquer ordem")
    func aceitaFlagsForaDeOrdem() throws {
        let value = try parseRecordArguments([
            "--cwd", "/tmp/probe-scratch", "--out", "/tmp/out.ndjson", "--prompt", "oi",
        ]).get()
        #expect(value == RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: "/tmp/out.ndjson"))
    }

    @Test("--prompt seguido de outra flag não vira o valor de --prompt")
    func promptSeguidoDeFlagNaoViraValor() {
        // O incidente relatado pelo revisor: um escaneamento por-flag deixava
        // este único token "--cwd" servir ao mesmo tempo de valor de
        // --prompt e de flag --cwd de verdade, passando os dois guards e
        // lançando o `claude` real.
        let result = parseRecordArguments(["--prompt", "--cwd", "/tmp/probe-scratch"])
        #expect(result == .failure(.missingValue(flag: "--prompt")))
    }

    @Test("reprodução literal da linha de comando do incidente reportado")
    func reproducaoLiteralDoIncidente() {
        // `harness-probe record --prompt --cwd /tmp/probe-scratch --out
        // /tmp/x.ndjson`, exatamente como o revisor rodou esperando falhar
        // antes de spawnar qualquer processo — e em vez disso gastou crédito
        // de API de verdade contra o parser anterior.
        let result = parseRecordArguments([
            "--prompt", "--cwd", "/tmp/probe-scratch", "--out", "/tmp/x.ndjson",
        ])
        #expect(result == .failure(.missingValue(flag: "--prompt")))
    }

    @Test("--cwd no fim da lista, sem valor")
    func cwdNoFimDaListaSemValor() {
        // O incidente do round anterior: --cwd como último token.
        let result = parseRecordArguments(["--prompt", "oi", "--cwd"])
        #expect(result == .failure(.missingValue(flag: "--cwd")))
    }

    @Test("--out seguido de outra flag também não vira valor")
    func outSeguidoDeFlagNaoViraValor() {
        let result = parseRecordArguments(["--prompt", "oi", "--cwd", "/tmp/probe-scratch", "--out", "--prompt"])
        #expect(result == .failure(.missingValue(flag: "--out")))
    }

    @Test("flag desconhecida é rejeitada, não ignorada")
    func flagDesconhecidaERejeitada() {
        let result = parseRecordArguments([
            "--prompt", "oi", "--cwd", "/tmp/probe-scratch", "--bogus", "y",
        ])
        #expect(result == .failure(.unknownFlag("--bogus")))
    }

    @Test("--prompt ausente")
    func promptAusente() {
        let result = parseRecordArguments(["--cwd", "/tmp/probe-scratch"])
        #expect(result == .failure(.missingRequired(flag: "--prompt")))
    }

    @Test("--cwd ausente")
    func cwdAusente() {
        let result = parseRecordArguments(["--prompt", "oi"])
        #expect(result == .failure(.missingRequired(flag: "--cwd")))
    }

    @Test("lista de argumentos vazia")
    func listaVazia() {
        let result = parseRecordArguments([])
        #expect(result == .failure(.missingRequired(flag: "--prompt")))
    }
}

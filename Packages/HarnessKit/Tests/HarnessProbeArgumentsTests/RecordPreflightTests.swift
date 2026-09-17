import Testing
@testable import HarnessProbeArguments

/// Sistema de arquivos falso: dois conjuntos, nenhum I/O. O que está sendo
/// testado é a decisão e a ordem dela, não o `FileManager`.
private func probe(directories: Set<String> = [], files: Set<String> = []) -> FileSystemProbe {
    FileSystemProbe(
        exists: { directories.contains($0) || files.contains($0) },
        isDirectory: { directories.contains($0) }
    )
}

@Suite("preflightRecord")
struct RecordPreflightTests {
    @Test("--cwd existente e --out inédito passam")
    func caminhoFeliz() {
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: "/tmp/novo.ndjson"),
            on: probe(directories: ["/tmp/probe-scratch"])
        )
        #expect(problem == nil)
    }

    @Test("--out ausente é opcional de verdade")
    func semOut() {
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch"),
            on: probe(directories: ["/tmp/probe-scratch"])
        )
        #expect(problem == nil)
    }

    @Test("--cwd inexistente é recusado")
    func cwdInexistente() {
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratchh"),
            on: probe(directories: ["/tmp/probe-scratch"])
        )
        #expect(problem == .cwdNotFound("/tmp/probe-scratchh"))
        #expect(problem?.exitCode == 66)
    }

    @Test("--cwd apontando para um arquivo é recusado")
    func cwdNaoEhDiretorio() {
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/arquivo.txt"),
            on: probe(files: ["/tmp/arquivo.txt"])
        )
        #expect(problem == .cwdNotADirectory("/tmp/arquivo.txt"))
    }

    @Test("--out existente nunca é sobrescrito")
    func outExistente() {
        let fixture = "Tests/ClaudeHarnessTests/Fixtures/hello.ndjson"
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: fixture),
            on: probe(directories: ["/tmp/probe-scratch"], files: [fixture])
        )
        #expect(problem == .outputAlreadyExists(fixture))
        #expect(problem?.exitCode == 73)
    }

    /// O cenário exato do review: um caractere a mais no `--cwd`, um `--out`
    /// correto apontando para um fixture que existe. Ambas as checagens falham;
    /// a que o operador precisa ler é a do argumento que ele digitou errado.
    @Test("com --cwd errado e --out existente, o erro reportado é o do --cwd")
    func aOrdemDasChecagensEhCwdPrimeiro() {
        let fixture = "Tests/ClaudeHarnessTests/Fixtures/hello.ndjson"
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratchh", outputPath: fixture),
            on: probe(directories: ["/tmp/probe-scratch"], files: [fixture])
        )
        #expect(problem == .cwdNotFound("/tmp/probe-scratchh"))
    }

    /// As mensagens são a única saída que o operador vê; um erro que não nomeia
    /// o caminho não é acionável.
    @Test("toda mensagem nomeia o caminho ofensor")
    func mensagensNomeiamOCaminho() {
        #expect(RecordPreflightError.cwdNotFound("/x/y").message.contains("/x/y"))
        #expect(RecordPreflightError.cwdNotADirectory("/x/y").message.contains("/x/y"))
        #expect(RecordPreflightError.outputAlreadyExists("/x/y").message.contains("/x/y"))
    }
}

import Testing
@testable import HarnessProbeArguments

/// Item 10 do review final. O subcomando `permission` é o entregável nomeado da
/// spec §8, e a parte dele que pode estar errada em silêncio é esta: o parsing
/// dos argumentos e a leitura da resposta do operador. O resto — subir a sessão
/// e responder pelo canal — é ligação direta com `ClaudeLaunch.make` e
/// `ControlChannel`, que já têm testes próprios.
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

    /// `--out` não é aceito e não é ignorado. Este subcomando não grava
    /// fixture; aceitar a flag para depois descartá-la deixaria o operador
    /// achando que tem um arquivo.
    @Test("--out is not a flag of this subcommand")
    func outIsRejectedHere() {
        let result = parsePermissionArguments([
            "--prompt", "oi", "--cwd", "/tmp/probe", "--out", "/tmp/x.ndjson",
        ])
        #expect(result == .failure(.unknownFlag("--out")))
    }

    /// O invariante que custou dois lançamentos reais e não intencionais do
    /// `claude` vale aqui também, e não por reimplementação: os dois parsers
    /// compartilham a mesma passada única.
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

/// O portão de permissão do produto, na sua forma mais crua. Toda entrada
/// ambígua tem que negar: uma aprovação por engano executa a ferramenta, e não
/// há como desfazer.
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

    /// O caso que importa na prática: rodar o probe com o stdin redirecionado
    /// (de um pipe, de um arquivo, de um agente) faz `readLine()` devolver
    /// `nil` na primeira pergunta. Um default permissivo ali aprovaria toda
    /// chamada de ferramenta de uma sessão inteira sem ninguém ler nada.
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

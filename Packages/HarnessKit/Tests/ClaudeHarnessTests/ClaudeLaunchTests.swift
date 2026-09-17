import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private let install = HarnessInstallation(executable: "/opt/homebrew/bin/claude", version: "2.1.236")
private let cwd = URL(fileURLWithPath: "/tmp/scratch")
private let session = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
private let previousSession = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!

@Test func theLaunchCarriesTheFlagThatEnablesPermissionRouting() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session))
    let args = launch.arguments
    let i = try! #require(args.firstIndex(of: "--permission-prompt-tool"))
    #expect(args[args.index(after: i)] == "stdio")
}

@Test func theLaunchUsesTheStreamingProtocolInBothDirections() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session)).arguments
    #expect(args.contains("-p"))
    for pair in [("--output-format", "stream-json"), ("--input-format", "stream-json")] {
        let i = try! #require(args.firstIndex(of: pair.0))
        #expect(args[args.index(after: i)] == pair.1)
    }
    #expect(args.contains("--verbose"))
    #expect(args.contains("--include-partial-messages"))
}

@Test func theLaunchRunsInTheRequestedDirectory() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session))
    #expect(launch.workingDirectory == cwd)
    #expect(launch.executable == "/opt/homebrew/bin/claude")
}

@Test func theEnvironmentAnnouncesDevSpaceAsTheEntrypoint() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session))
    #expect(launch.environment["CLAUDE_CODE_ENTRYPOINT"] == "devspace")
}

// MARK: - SessionStart

// `--resume <id>` alone already reuses the original session (`claude --help`
// documents `--fork-session` as what changes that). The three cases below
// pin, per case, exactly which flags come out — the two that matter most are
// that `.resume` emits no `--session-id` at all, and that `.fork` is the only
// case that emits `--fork-session`. A test that only checked `.contains` for
// each flag independently would pass even if `.resume` wrongly carried both
// `--resume` and `--session-id` — pinning absence, not just presence, is the
// point.

@Test func freshEmitsANewSessionIDAndNothingElseSessionRelated() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session)).arguments
    let i = try! #require(args.firstIndex(of: "--session-id"))
    #expect(args[args.index(after: i)] == "11111111-2222-3333-4444-555555555555")
    #expect(!args.contains("--resume"))
    #expect(!args.contains("--fork-session"))
}

@Test func resumeReusesTheOriginalIDAndEmitsNoSessionIDFlag() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .resume(harnessSessionID: previousSession)).arguments
    let i = try! #require(args.firstIndex(of: "--resume"))
    #expect(args[args.index(after: i)] == "99999999-8888-7777-6666-555555555555")
    // The assertion that matters most in this test: no --session-id at all.
    // Emitting one here is exactly the incoherent pair this type exists to
    // make unrepresentable — "use this new id" and "continue the old session
    // without forking" in the same argv.
    #expect(!args.contains("--session-id"))
    #expect(!args.contains("--fork-session"))
}

@Test func forkResumesTheOldIDMarksForkSessionAndCarriesTheNewID() {
    let args = ClaudeLaunch.make(
        installation: install, workingDirectory: cwd,
        session: .fork(from: previousSession, newSessionID: session)
    ).arguments
    let resumeIndex = try! #require(args.firstIndex(of: "--resume"))
    #expect(args[args.index(after: resumeIndex)] == "99999999-8888-7777-6666-555555555555")
    // The assertion that matters most in this test: --fork-session is
    // present. Without it, --resume plus a fresh --session-id is the same
    // incoherent pair the .fork case exists to distinguish from a plain
    // resume.
    #expect(args.contains("--fork-session"))
    let sessionIndex = try! #require(args.firstIndex(of: "--session-id"))
    #expect(args[args.index(after: sessionIndex)] == "11111111-2222-3333-4444-555555555555")
}

@Test func theLaunchPassesModelPermissionModeAndEachAdditionalDirectory() {
    let args = ClaudeLaunch.make(
        installation: install,
        workingDirectory: cwd,
        session: .fresh(sessionID: session),
        model: "claude-opus-4-6",
        permissionMode: .acceptEdits,
        additionalDirectories: [
            URL(fileURLWithPath: "/tmp/scratch/a"),
            URL(fileURLWithPath: "/tmp/scratch/b"),
        ]
    ).arguments

    let modelIndex = try! #require(args.firstIndex(of: "--model"))
    #expect(args[args.index(after: modelIndex)] == "claude-opus-4-6")

    let modeIndex = try! #require(args.firstIndex(of: "--permission-mode"))
    #expect(args[args.index(after: modeIndex)] == "acceptEdits")

    // --add-dir repeats once per entry, each immediately followed by its own path.
    let addDirIndices = args.indices.filter { args[$0] == "--add-dir" }
    #expect(addDirIndices.count == 2)
    #expect(addDirIndices.map { args[args.index(after: $0)] } == ["/tmp/scratch/a", "/tmp/scratch/b"])
}

/// Item 6 do review final. Os seis modos da spec §12 são um conjunto fechado, e
/// cada um tem que chegar ao `--permission-mode` com a grafia exata que o CLI
/// aceita — um modo com typo era, antes, um erro do CLI em tempo de execução
/// descoberto só depois de a sessão subir. Este teste fixa as seis grafias de
/// uma vez: `CaseIterable` garante que um sétimo modo adicionado ao enum sem
/// grafia correspondente aqui derrube o teste em vez de passar despercebido.
@Test func everyPermissionModeReachesTheCLIWithItsVerifiedSpelling() throws {
    let spellings = PermissionMode.allCases.map { mode -> String in
        let args = ClaudeLaunch.make(
            installation: install,
            workingDirectory: cwd,
            session: .fresh(sessionID: session),
            permissionMode: mode
        ).arguments
        let index = try! #require(args.firstIndex(of: "--permission-mode"))
        return args[args.index(after: index)]
    }
    #expect(spellings == ["acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan"])
}

/// Item 10 do review final, do lado do argv.
///
/// O `harness-probe permission` é o entregável nomeado da spec §8 ("em modo
/// `manual` pergunta 'permitir Bash?' e a sessão obedece"), e o defeito que ele
/// consertou foi o probe montar o próprio argv e ter **divergido**: sem
/// `--permission-prompt-tool stdio` ele era estruturalmente incapaz de observar
/// um pedido de permissão, e carregava um `--safe-mode` que `ClaudeLaunch` não
/// tem. Agora ele chama esta função, então a divergência é irrepresentável.
///
/// Este teste fixa a configuração exata que o subcomando pede — sessão nova e
/// modo `manual` — e as três propriedades de que ele depende para funcionar.
/// Verificado só por construção e por aqui, nunca contra o CLI real: rodar uma
/// sessão de verdade gasta dinheiro do operador e é decisão dele.
@Test func theProbesPermissionSessionAsksInsteadOfDeciding() throws {
    let args = ClaudeLaunch.make(
        installation: install,
        workingDirectory: cwd,
        session: .fresh(sessionID: session),
        permissionMode: .manual
    ).arguments

    // 1. A flag oculta sem a qual nenhum `can_use_tool` chega ao fio.
    let promptToolIndex = try #require(args.firstIndex(of: "--permission-prompt-tool"))
    #expect(args[args.index(after: promptToolIndex)] == "stdio")

    // 2. O modo que torna o probe reprodutível em vez de herdar o
    //    `defaultMode` das configurações do operador.
    let modeIndex = try #require(args.firstIndex(of: "--permission-mode"))
    #expect(args[args.index(after: modeIndex)] == "manual")

    // 3. stream-json nas duas direções: sem o `--input-format`, não há por onde
    //    a resposta do operador voltar.
    #expect(args.contains("--input-format"))
    #expect(args.contains("--output-format"))

    // E o que o probe NÃO passa mais: `--safe-mode` era invenção dele.
    #expect(!args.contains("--safe-mode"))
}

/// E sem modo nenhum a flag não aparece: herdar a configuração do operador é um
/// caso legítimo, distinto de passar um modo.
@Test func noPermissionModeMeansNoFlagAtAll() {
    let args = ClaudeLaunch.make(
        installation: install,
        workingDirectory: cwd,
        session: .fresh(sessionID: session)
    ).arguments
    #expect(!args.contains("--permission-mode"))
}

@Test func claudeCodeDeclaresWhatItSupports() {
    let c = ClaudeLaunch.capabilities(for: install)
    #expect(c.routesPermissionRequests)
    #expect(c.canInterrupt)
    #expect(c.canSetPermissionMode)
    #expect(c.canResumeSession)
    #expect(c.canForkSession)
    // `set_model` exists in the control protocol (OutboundControlRequest),
    // so flipping this to `true` looks like fixing an oversight. It isn't:
    // it was never verified against the real CLI, and spec §4.1 wants the
    // conservative answer until someone confirms it. Only change this to
    // `true` once a real session has shown the CLI accepting a `set_model`
    // control request and actually acting on it — not before.
    #expect(!c.canSetModelInSession)
}

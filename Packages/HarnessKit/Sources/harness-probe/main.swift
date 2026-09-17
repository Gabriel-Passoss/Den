import Foundation
import ClaudeHarness
import HarnessProbeArguments

/// Ferramenta de diagnóstico: descobre o binário `claude` real e grava uma
/// sessão `stream-json` em disco. Sem ArgumentParser — a restrição global do
/// pacote é zero dependências externas, e isto é um utilitário interno, não
/// uma superfície pública.
func usage() -> Never {
    FileHandle.standardError.write(Data("""
    uso:
      harness-probe discover
      harness-probe record --prompt <texto> --cwd <dir> [--out <arquivo.ndjson>]

    --cwd precisa ser um diretório que já existe.
    --out recusa sobrescrever: se o arquivo existir, apague-o explicitamente
    antes de regravar. Não há --force, de propósito.

    """.utf8))
    exit(64)
}

func errLine(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Mensagem curada para cada falha de descoberta. O default do Swift
/// (`"\(error)"` num enum) imprimiria `notFound`, que não diz ao operador o que
/// fazer — e a spec §5.3 classifica `DiscoveryFailure` e `AuthFailure` como
/// **acionáveis**, ou seja, o valor está inteiro na mensagem.
func describe(_ error: ClaudeDiscovery.DiscoveryError) -> String {
    switch error {
    case .notFound:
        return """
        o binário `claude` não foi encontrado.
        Procurado pelo shell de login (`$SHELL -l -c 'command -v claude'`) e nos \
        caminhos conhecidos. Instale o Claude Code, ou garanta que ele está no \
        PATH do seu shell de login.
        """
    case .unreadableVersion(let raw):
        return """
        `claude --version` respondeu algo que não dá para ler como versão: \(raw)
        """
    case .versionCommandFailed(let exitCode, let stderr):
        return """
        `claude --version` saiu com código \(exitCode) — o binário está instalado \
        mas não está funcionando. Autenticação expirada, node ausente ou permissão \
        são as causas típicas (spec §5.3).
        stderr: \(stderr.isEmpty ? "(vazio)" : stderr)
        """
    }
}

/// O `FileSystemProbe` de verdade. A decisão em si mora em
/// `preflightRecord`, num alvo que os testes alcançam; aqui fica só a ligação
/// com o `FileManager`.
let liveFileSystem = FileSystemProbe(
    exists: { FileManager.default.fileExists(atPath: $0) },
    isDirectory: { path in
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
)

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

// Carrega um código de saída para depois do `switch`, em vez de chamar
// `exit(_:)` de dentro de um `case`. `exit(_:)` termina o processo na hora,
// sem passar pelos `defer`s do Swift — e o `defer` do case "record" é quem
// chama `transport.terminate()`. Se o filho ainda estiver vivo (por exemplo,
// abortamos a gravação por uma falha de escrita em disco, não porque o
// `claude` real já tinha saído), sair direto aqui o deixaria órfão.
//
// A regra exata, já que o `case "record"` tem `exit(_:)` em quatro lugares:
// sair direto é seguro enquanto o `defer` ainda não foi armado — é o caso das
// falhas de preflight, de descoberta e de criação do arquivo, todas anteriores
// à criação do transporte. Depois do `defer`, só há uma saída direta, e ela
// está anotada onde acontece: o `exit(status)` que reporta o código do
// harness. Ali o filho comprovadamente já saiu — é o que `terminationStatus`
// significa —, então não há nada que o `defer` teria a fazer.
var exitCode: Int32 = 0

switch command {
case "discover":
    do {
        let install = try await ClaudeDiscovery().discover()
        print("executável: \(install.executable)")
        print("versão:     \(install.version)")
    } catch let error as ClaudeDiscovery.DiscoveryError {
        errLine("✗ \(describe(error))")
        exitCode = 69 // EX_UNAVAILABLE
    } catch {
        errLine("✗ falha inesperada ao descobrir o binário: \(error)")
        exitCode = 69
    }

case "record":
    // Parseia tudo de uma vez em vez de escanear `args` independentemente
    // por flag (essa era a falha: um único token como "--cwd" podia servir
    // ao mesmo tempo de valor de --prompt e de flag --cwd de verdade, e as
    // duas buscas separadas passavam). Ver HarnessProbeArguments para o
    // contrato completo e os testes que provam os quatro modos de falha.
    let parsedArguments: RecordArguments
    switch parseRecordArguments(Array(args.dropFirst())) {
    case .success(let parsed):
        parsedArguments = parsed
    case .failure(let error):
        errLine(error.message)
        usage()
    }
    let prompt = parsedArguments.prompt
    let cwd = URL(fileURLWithPath: parsedArguments.cwd)
    let outputPath = parsedArguments.outputPath
    let sessionID = UUID()

    // Impresso antes de qualquer coisa que possa falhar — inclusive antes da
    // descoberta do binário — para que o diretório-alvo seja a primeira coisa
    // visível, nunca algo que só apareceria depois de o processo já ter sido
    // lançado contra ele.
    errLine("diretório de trabalho: \(cwd.path)")

    // Segunda fase da validação, e ela roda **antes de qualquer efeito
    // colateral**: antes da descoberta, antes de criar o arquivo de saída,
    // antes de subir processo nenhum. A ordem é o defeito que esta checagem
    // conserta — a versão anterior truncava o `--out` para 0 byte e só então
    // descobria, lá dentro do `Process.run()`, que o `--cwd` não existia. Uma
    // gravação que custou dinheiro real sumia por um caractere digitado errado.
    //
    // A decisão mora em `preflightRecord`, no alvo `HarnessProbeArguments`,
    // porque um `main.swift` não pode ser importado por um alvo de teste — a
    // mesma razão que tirou o parser daqui.
    if let problem = preflightRecord(parsedArguments, on: liveFileSystem) {
        errLine("✗ \(problem.message)")
        exit(problem.exitCode)
    }

    let install: HarnessInstallation
    do {
        install = try await ClaudeDiscovery().discover()
    } catch let error as ClaudeDiscovery.DiscoveryError {
        errLine("✗ \(describe(error))")
        exit(69) // EX_UNAVAILABLE
    } catch {
        errLine("✗ falha inesperada ao descobrir o binário: \(error)")
        exit(69)
    }
    errLine("→ \(install.executable) \(install.version), sessão \(sessionID)")

    // Escreve incrementalmente: se a sessão travar esperando aprovação de
    // permissão e o operador interromper (Ctrl-C), o arquivo já contém tudo
    // que foi capturado até aquele instante — não só o que sobraria de um
    // buffer em memória gravado ao final do laço.
    var outputHandle: FileHandle?
    if let outputPath {
        guard FileManager.default.createFile(atPath: outputPath, contents: nil),
              let handle = FileHandle(forWritingAtPath: outputPath)
        else {
            errLine("não foi possível criar o arquivo de saída em \(outputPath)")
            exit(74) // EX_IOERR
        }
        outputHandle = handle
    }

    let transport = ProcessTransport()

    // SIGINT (Ctrl-C) não passa pelo `defer` normal do Swift: o sistema
    // encerraria o processo antes que qualquer código nosso rodasse. Sem
    // isto, interromper uma sessão travada esperando aprovação deixaria o
    // `claude` real órfão. Ignoramos a disposição padrão do sinal e o
    // tratamos numa fila comum, onde é seguro chamar código assíncrono.
    signal(SIGINT, SIG_IGN)
    let sigintSource = DispatchSource.makeSignalSource(
        signal: SIGINT,
        queue: DispatchQueue(label: "harness-probe.sigint")
    )
    sigintSource.setEventHandler {
        errLine("\n⚠ interrompido — encerrando o processo filho antes de sair...")
        Task {
            await transport.terminate()
            exit(130)
        }
    }
    sigintSource.resume()

    // Contrato do Task 3: abandonar o stream sem chamar terminate() vaza o
    // processo filho. Este defer cobre toda saída deste bloco — sucesso,
    // erro lançado por start/write, ou erro de enquadramento propagado pelo
    // próprio laço abaixo.
    defer {
        try? outputHandle?.close()
        await transport.terminate()
    }

    // Tudo daqui para baixo pode lançar — spawn, escrita no stdin,
    // enquadramento. Sem este `do/catch`, qualquer uma dessas falhas virava
    // `Fatal error: Error raised at top level`: um stack trace no lugar de uma
    // mensagem, e o `defer` acima nunca rodando. O `catch` marca `exitCode` em
    // vez de chamar `exit(_:)` justamente para que o `defer` — que é quem
    // derruba o filho — aconteça antes da saída.
    do {
        let stream = try await transport.start(ProcessTransport.Launch(
            executable: install.executable,
            arguments: [
                "-p",
                "--output-format", "stream-json",
                "--input-format", "stream-json",
                "--include-partial-messages",
                "--verbose",
                "--session-id", sessionID.uuidString.lowercased(),
                // Sem isto, o `claude` real **executa** os hooks/plugins/skills do
                // operador (~/.claude): visto na prática, um hook de SessionStart
                // despejando o texto inteiro de uma skill dentro da gravação.
                // --safe-mode impede essa execução e mantém autenticação e
                // ferramentas normais.
                //
                // O que ele NÃO faz — e os três fixtures provam: o `system/init`
                // continua listando o inventário instalado da máquina. `plugins`
                // (11 entradas, com caminhos absolutos), `skills` (15) e
                // `slash_commands` (47) aparecem em todas as gravações, feitas com
                // --safe-mode. Ou seja, --safe-mode é sobre execução, não sobre
                // vazamento de metadado — quem for escrever testes contra esses
                // bytes tem que tratar esses campos como variáveis por máquina.
                "--safe-mode",
                // Fixa o modo de permissão em vez de herdar a configuração global
                // do operador (aqui, "auto" — um classificador que pode aprovar
                // silenciosamente sem nunca emitir pedido no fio). "manual" torna
                // o probe reprodutível para qualquer operador. NÃO garante um
                // pedido de permissão observável para toda chamada de ferramenta
                // — na prática, leituras via Bash (ex.: "ls") passam direto sem
                // nenhuma mensagem de permissão; só chamadas de escrita (Write,
                // ou Bash redirecionando para um arquivo) produzem a mensagem
                // `{"type":"system","subtype":"permission_denied",...}` seguida
                // de um `tool_result` de erro sintético. Ver relatório da Task 4.
                "--permission-mode", "manual",
            ],
            workingDirectory: cwd
        ))

        // O turno do usuário, no formato de entrada do stream-json.
        //
        // VERIFICADO contra o claude 2.1.236: três gravações bem-sucedidas
        // (hello, tool-use, permission-denied), aceitas sem alteração na primeira
        // tentativa. Não é mais hipótese. Segue valendo que o protocolo não é
        // contrato público (spec §5.4): se uma versão futura reclamar, o formato
        // correto aparece no stderr do próprio CLI.
        let turn: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": prompt],
        ]
        try await transport.write(try JSONSerialization.data(withJSONObject: turn))
        await transport.endInput()

        var count = 0
        // `count` só conta linhas que de fato chegaram ao disco. Uma falha de
        // escrita aborta a gravação em vez de ser engolida: um `try?` aqui faria
        // o resumo final mentir "N linhas gravadas" sobre um arquivo truncado —
        // exatamente o fixture corrompido e sem rótulo que esta tarefa existe
        // para evitar. Aborta no primeiro erro em vez de tentar continuar: uma
        // vez que o disco não aceita mais bytes, não há razão para acreditar que
        // a próxima escrita vá funcionar, e um arquivo "quase completo, com um
        // buraco no meio" não é mais confiável como fixture do que um truncado
        // no fim — em ambos os casos o único jeito seguro de seguir é regravar.
        var writeFailure: (line: Int, error: any Error)?
        // Toda linha vai para stdout como veio, sem interpretação: o objetivo
        // desta etapa é justamente descobrir o formato.
        for try await line in stream {
            FileHandle.standardOutput.write(line + Data("\n".utf8))
            guard let outputHandle else { continue }
            do {
                try outputHandle.write(contentsOf: line)
                try outputHandle.write(contentsOf: Data("\n".utf8))
                count += 1
            } catch {
                writeFailure = (count + 1, error)
                break
            }
        }

        if let outputPath {
            if let writeFailure {
                errLine("✗ escrita falhou na linha \(writeFailure.line) de \(outputPath): \(writeFailure.error)")
                errLine("✗ \(count) linha(s) confirmadamente gravada(s) antes da falha — arquivo incompleto, não usar como fixture")
                exitCode = 74 // EX_IOERR — mesmo código usado quando a criação do arquivo falha
            } else {
                errLine("← \(count) linhas gravadas em \(outputPath)")
            }
        }

        let stderrText = await transport.standardError
        if !stderrText.isEmpty {
            errLine("stderr do harness:\n\(stderrText)")
        }
        // Exceção documentada ao comentário de cabeçalho: este `exit(_:)` está
        // dentro do `case`, e portanto pula o `defer` que chama `terminate()` — e
        // mesmo assim está correto. `terminationStatus` só é não-nil quando o filho
        // **já saiu** (é o que a propriedade garante), então não há processo vivo
        // para o `defer` derrubar. O `outputHandle` também não precisa do `close()`:
        // as escritas são `write(2)` direto, sem buffer de usuário para perder.
        if let status = await transport.terminationStatus, status != 0 {
            errLine("saída com código \(status)")
            exit(status)
        }
    } catch {
        errLine("✗ a gravação falhou: \(error)")
        let stderrText = await transport.standardError
        if !stderrText.isEmpty {
            errLine("stderr do harness:\n\(stderrText)")
        }
        exitCode = 70 // EX_SOFTWARE
    }

default:
    usage()
}

// Chega aqui só depois que o `case` correspondente terminou normalmente — e
// portanto depois que o `defer` dele (se houver) já rodou. É por isso que a
// falha de escrita não chama `exit(_:)` direto: ela só marca `exitCode` e
// deixa o bloco terminar, para que `transport.terminate()` aconteça primeiro.
if exitCode != 0 {
    exit(exitCode)
}

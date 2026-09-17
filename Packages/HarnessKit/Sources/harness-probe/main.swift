import Foundation
import ClaudeHarness
import HarnessCore
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
      harness-probe permission --prompt <texto> --cwd <dir>

    --cwd precisa ser um diretório que já existe.
    --out recusa sobrescrever: se o arquivo existir, apague-o explicitamente
    antes de regravar. Não há --force, de propósito.

    `permission` é o entregável da Etapa 3: sobe a sessão pela MESMA construção
    de argv que o app usa (ClaudeLaunch.make, em modo `manual`), imprime cada
    pedido de permissão e pergunta no terminal. Qualquer resposta que não seja
    um "sim" reconhecido nega — inclusive o EOF, então não redirecione o stdin.

    Ressalva: o CLI só encaminha o pedido quando as regras dele avaliam para
    "ask". Ferramentas liberadas por `permissions.allow`, por um hook
    `PreToolUse`, ou pelo `defaultMode` das configurações do operador nunca
    chegam a perguntar. Se nada for perguntado, comece conferindo isso.

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

/// Reimprime um `JSONValue` como JSON para o operador ler no terminal.
///
/// O default do Swift para um enum com valores associados imprimiria a árvore
/// de casos (`object(["command": string("ls")])`), e o operador está lendo isto
/// para decidir se aprova uma chamada de ferramenta — o ruído aqui custa uma
/// decisão errada, não só legibilidade.
func renderJSON(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let data = try? encoder.encode(value) else { return "(não foi possível reimprimir)" }
    return String(decoding: data, as: UTF8.self)
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
        // Argv PRÓPRIO, e não `ClaudeLaunch.make`, de propósito — é a única
        // divergência deliberada que sobrou entre o probe e o app.
        //
        // `make` passa `--permission-prompt-tool stdio` incondicionalmente: é o
        // que sustenta `capabilities.routesPermissionRequests`, e tornar a flag
        // opcional lá enfraqueceria uma invariante que o adaptador construiu de
        // propósito. Mas `record` não tem responder de permissão — ele só
        // despeja linhas —, então roteado por `make` ele congelaria no primeiro
        // pedido: uma gravação travada, que custa dinheiro e minutos do
        // operador. Quem quer ver o pedido de permissão usa `permission`, que
        // chama `make` e sabe responder.
        //
        // `--safe-mode` é a outra metade e só existe aqui, pela razão logo
        // abaixo: um fixture não deve conter os hooks e skills do operador.
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

case "permission":
    // O ENTREGÁVEL NOMEADO DA ETAPA 3 (spec §8): "harness-probe em modo
    // `manual` pergunta 'permitir Bash?' e a sessão obedece".
    //
    // A diferença que importa em relação a `record` não é o diálogo — é de
    // onde vem o argv. Este caso chama `ClaudeLaunch.make`, a mesma função que
    // o app vai chamar, então o que este subcomando exercita é literalmente a
    // invocação de produção. `record` monta o próprio argv e continua assim de
    // propósito: ele não tem responder de permissão, e `ClaudeLaunch.make`
    // passa `--permission-prompt-tool stdio` incondicionalmente (é o que
    // sustenta `capabilities.routesPermissionRequests`). Um `record` roteado
    // por ele congelaria no primeiro pedido, que é exatamente o defeito que
    // este subcomando existe para consertar — só que na gravação, que custa
    // dinheiro. Ver o comentário do argv de `record`.
    let permissionArguments: PermissionArguments
    switch parsePermissionArguments(Array(args.dropFirst())) {
    case .success(let parsed):
        permissionArguments = parsed
    case .failure(let error):
        errLine(error.message)
        usage()
    }
    let permissionCwd = URL(fileURLWithPath: permissionArguments.cwd)
    errLine("diretório de trabalho: \(permissionCwd.path)")

    // Mesma segunda fase de validação de `record`, e pela mesma razão: antes
    // de qualquer efeito colateral. `outputPath` nil pula a checagem de --out,
    // que este subcomando não tem.
    let permissionPreflightArguments = RecordArguments(
        prompt: permissionArguments.prompt, cwd: permissionArguments.cwd
    )
    if let problem = preflightRecord(permissionPreflightArguments, on: liveFileSystem) {
        errLine("✗ \(problem.message)")
        exit(problem.exitCode)
    }

    let permissionInstall: HarnessInstallation
    do {
        permissionInstall = try await ClaudeDiscovery().discover()
    } catch let error as ClaudeDiscovery.DiscoveryError {
        errLine("✗ \(describe(error))")
        exit(69)
    } catch {
        errLine("✗ falha inesperada ao descobrir o binário: \(error)")
        exit(69)
    }

    let launch = ClaudeLaunch.make(
        installation: permissionInstall,
        workingDirectory: permissionCwd,
        session: .fresh(sessionID: UUID()),
        permissionMode: .manual
    )

    // Impresso antes de subir processo nenhum. Uma sessão custa dinheiro do
    // operador, e ele merece ver exatamente o que vai rodar antes de pagar por
    // isso. É também como se verifica, sem gastar nada, que este subcomando e
    // o app constroem o mesmo argv.
    errLine("→ \(launch.executable) \(launch.arguments.joined(separator: " "))")

    let permissionTransport = ProcessTransport()
    let channel = ControlChannel(transport: permissionTransport)

    signal(SIGINT, SIG_IGN)
    let permissionSigint = DispatchSource.makeSignalSource(
        signal: SIGINT,
        queue: DispatchQueue(label: "harness-probe.permission.sigint")
    )
    permissionSigint.setEventHandler {
        errLine("\n⚠ interrompido — encerrando o processo filho antes de sair...")
        Task {
            await channel.stop()
            exit(130)
        }
    }
    permissionSigint.resume()

    // Mesmo contrato do Task 3 que `record` obedece: abandonar o fluxo sem
    // `stop()` deixa o filho vivo com o stdout sem leitor.
    defer { await channel.stop() }

    do {
        let stream = try await channel.start(launch)

        let turn: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": permissionArguments.prompt],
        ]
        try await channel.writeTurn(try JSONSerialization.data(withJSONObject: turn))
        // NÃO fecha o stdin aqui, diferente de `record`. O stdin é por onde a
        // resposta de permissão sai — fechá-lo agora tornaria toda decisão do
        // operador impossível de entregar, e o `respond` falharia com
        // `.channelClosed` no primeiro pedido.

        var asked = 0
        for try await output in stream {
            switch output {
            case .conversation(let data):
                FileHandle.standardOutput.write(data + Data("\n".utf8))
                // O `result` é a última mensagem de uma sessão (as três
                // gravações da Etapa 2 terminam nele, sem exceção). O stdin só
                // é fechado AQUI, e não logo depois do turno como `record` faz,
                // porque até este ponto ele é a única via de resposta de
                // permissão. E é fechado de fato: com o stdin aberto o CLI
                // segue esperando outro turno, o fluxo nunca termina, e o probe
                // trava DEPOIS de a sessão ter obedecido — a mesma classe de
                // defeito que esta etapa inteira existe para eliminar, só que
                // do nosso lado do pipe.
                if let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                   value["type"]?.stringValue == "result" {
                    await channel.endInput()
                }

            case .permissionRequest(let request):
                asked += 1
                errLine("")
                errLine("┌─ PEDIDO DE PERMISSÃO (\(request.id))")
                errLine("│ ferramenta: \(request.toolName)")
                if let description = request.description {
                    errLine("│ descrição:  \(description)")
                }
                errLine("│ input:      \(renderJSON(request.input))")
                for suggestion in request.suggestions {
                    errLine("│ sugestão:   \(renderJSON(suggestion.raw))")
                }
                errLine("└─ permitir? [s/N]")
                // `readLine()` bloqueia a thread cooperativa enquanto o
                // operador pensa. Aceitável aqui e em nenhum outro lugar: a
                // bomba do canal roda numa Task própria e vai bufferizando o
                // stdout, e este é um utilitário de diagnóstico de um operador
                // só. O app NÃO deve ler decisão assim.
                let answer = parsePermissionAnswer(readLine())
                switch answer {
                case .allow:
                    errLine("→ permitido")
                    try await channel.respond(to: request.id, with: .allow(updatedInput: nil))
                case .deny:
                    errLine("→ negado")
                    try await channel.respond(
                        to: request.id,
                        with: .deny(message: "negado pelo operador", interrupt: false)
                    )
                }

            case .unrecognizedControl(let unrecognized):
                // A superfície nova do canal, aqui no seu primeiro consumidor
                // real. Se isto aparecer numa sessão de verdade, é um subtipo
                // que o DevSpace ainda não conhece — e `wasAnswered` diz se a
                // sessão degradou ou travou, que é a diferença entre um aviso e
                // uma emergência.
                errLine("")
                errLine("⚠ quadro de controle não reconhecido \(unrecognized.requestID ?? "(sem request_id)")")
                errLine("  respondido: \(unrecognized.automaticReply ?? "NÃO — o harness pode estar esperando")")
                errLine("  cru:        \(renderJSON(unrecognized.raw))")
            }
        }

        errLine("\n← a sessão terminou; \(asked) pedido(s) de permissão")
        let stderrText = await permissionTransport.standardError
        if !stderrText.isEmpty {
            errLine("stderr do harness:\n\(stderrText)")
        }
        if asked == 0 {
            errLine("""
            ⚠ nenhum pedido chegou. Isso NÃO prova que o roteamento está quebrado: \
            o CLI só encaminha quando as regras dele avaliam para "ask". Confira \
            `permissions.allow`, hooks de PreToolUse, e o `defaultMode` das suas \
            configurações antes de suspeitar do DevSpace.
            """)
        }
    } catch {
        errLine("✗ a sessão falhou: \(error)")
        let stderrText = await permissionTransport.standardError
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

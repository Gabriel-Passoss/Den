import Foundation
import ClaudeHarness
import HarnessCore
import HarnessProbeArguments

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

func renderJSON(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let data = try? encoder.encode(value) else { return "(não foi possível reimprimir)" }
    return String(decoding: data, as: UTF8.self)
}

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

var exitCode: Int32 = 0

switch command {
case "discover":
    do {
        let install = try await ClaudeDiscovery().discover()
        print("executável: \(install.executable)")
        print("versão:     \(install.version)")
    } catch let error as ClaudeDiscovery.DiscoveryError {
        errLine("✗ \(describe(error))")
        exitCode = 69
    } catch {
        errLine("✗ falha inesperada ao descobrir o binário: \(error)")
        exitCode = 69
    }

case "record":

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

    errLine("diretório de trabalho: \(cwd.path)")

    if let problem = preflightRecord(parsedArguments, on: liveFileSystem) {
        errLine("✗ \(problem.message)")
        exit(problem.exitCode)
    }

    let install: HarnessInstallation
    do {
        install = try await ClaudeDiscovery().discover()
    } catch let error as ClaudeDiscovery.DiscoveryError {
        errLine("✗ \(describe(error))")
        exit(69)
    } catch {
        errLine("✗ falha inesperada ao descobrir o binário: \(error)")
        exit(69)
    }
    errLine("→ \(install.executable) \(install.version), sessão \(sessionID)")

    var outputHandle: FileHandle?
    if let outputPath {
        guard FileManager.default.createFile(atPath: outputPath, contents: nil),
              let handle = FileHandle(forWritingAtPath: outputPath)
        else {
            errLine("não foi possível criar o arquivo de saída em \(outputPath)")
            exit(74)
        }
        outputHandle = handle
    }

    let transport = ProcessTransport()

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

    defer {
        try? outputHandle?.close()
        await transport.terminate()
    }

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

                "--safe-mode",

                "--permission-mode", "manual",
            ],
            workingDirectory: cwd
        ))

        let turn: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": prompt],
        ]
        try await transport.write(try JSONSerialization.data(withJSONObject: turn))
        await transport.endInput()

        var count = 0

        var writeFailure: (line: Int, error: any Error)?

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
                exitCode = 74
            } else {
                errLine("← \(count) linhas gravadas em \(outputPath)")
            }
        }

        let stderrText = await transport.standardError
        if !stderrText.isEmpty {
            errLine("stderr do harness:\n\(stderrText)")
        }

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
        exitCode = 70
    }

case "permission":

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

    defer { await channel.stop() }

    do {
        let stream = try await channel.start(launch)

        let turn: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": permissionArguments.prompt],
        ]
        try await channel.writeTurn(try JSONSerialization.data(withJSONObject: turn))

        var asked = 0
        for try await output in stream {
            switch output {
            case .conversation(let data):
                FileHandle.standardOutput.write(data + Data("\n".utf8))

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
        exitCode = 70
    }

default:
    usage()
}

if exitCode != 0 {
    exit(exitCode)
}

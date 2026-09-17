import Foundation
import ClaudeHarness

/// Ferramenta de diagnóstico: descobre o binário `claude` real e grava uma
/// sessão `stream-json` em disco. Sem ArgumentParser — a restrição global do
/// pacote é zero dependências externas, e isto é um utilitário interno, não
/// uma superfície pública.
func usage() -> Never {
    FileHandle.standardError.write(Data("""
    uso:
      harness-probe discover
      harness-probe record --prompt <texto> [--cwd <dir>] [--out <arquivo.ndjson>]

    """.utf8))
    exit(64)
}

func value(_ flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), args.index(after: i) < args.endIndex else { return nil }
    return args[args.index(after: i)]
}

func errLine(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

switch command {
case "discover":
    let install = try await ClaudeDiscovery().discover()
    print("executável: \(install.executable)")
    print("versão:     \(install.version)")

case "record":
    guard let prompt = value("--prompt", in: args) else { usage() }
    let cwd = URL(fileURLWithPath: value("--cwd", in: args) ?? FileManager.default.currentDirectoryPath)
    let outputPath = value("--out", in: args)
    let sessionID = UUID()

    let install = try await ClaudeDiscovery().discover()
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

    let stream = try await transport.start(ProcessTransport.Launch(
        executable: install.executable,
        arguments: [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--session-id", sessionID.uuidString.lowercased(),
            // Sem isto, o `claude` real carrega os hooks/plugins/skills do
            // operador (~/.claude) e a sessão registra caminhos absolutos da
            // máquina — visto na prática: hooks de SessionStart despejando o
            // texto inteiro de uma skill, caminhos de plugin, socket de
            // mensageria. --safe-mode desliga essas customizações mas mantém
            // autenticação e ferramentas normais (spec do próprio --help).
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
    // ATENÇÃO: este shape é a hipótese de partida, não fato verificado. Se o
    // CLI reclamar no stderr, o formato correto aparece ali — corrigir aqui e
    // anotar no relatório da Task 4. Descobrir isso é justamente o objetivo
    // desta etapa.
    let turn: [String: Any] = [
        "type": "user",
        "message": ["role": "user", "content": prompt],
    ]
    try await transport.write(try JSONSerialization.data(withJSONObject: turn))
    await transport.endInput()

    var count = 0
    // Toda linha vai para stdout como veio, sem interpretação: o objetivo
    // desta etapa é justamente descobrir o formato.
    for try await line in stream {
        count += 1
        try? outputHandle?.write(contentsOf: line)
        try? outputHandle?.write(contentsOf: Data("\n".utf8))
        FileHandle.standardOutput.write(line + Data("\n".utf8))
    }

    if let outputPath {
        errLine("← \(count) linhas gravadas em \(outputPath)")
    }

    let stderrText = await transport.standardError
    if !stderrText.isEmpty {
        errLine("stderr do harness:\n\(stderrText)")
    }
    if let status = await transport.terminationStatus, status != 0 {
        errLine("saída com código \(status)")
        exit(status)
    }

default:
    usage()
}

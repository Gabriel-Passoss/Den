import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

/// O harness falso é `/bin/sh` rodando um script inline — nenhum arquivo de
/// recurso necessário.
private func shellLaunch(_ script: String) -> ProcessTransport.Launch {
    ProcessTransport.Launch(
        executable: "/bin/sh",
        arguments: ["-c", script],
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        environment: ProcessInfo.processInfo.environment
    )
}

/// Um script que larga `writers` netos despejando linhas de 4 KiB em stdout para
/// sempre — netos que herdaram o pipe e sobrevivem ao filho. O filho sai na hora.
private func floodScript(writers: Int) -> String {
    """
    pad=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    i=0; while [ $i -lt 7 ]; do pad="$pad$pad"; i=$((i+1)); done
    n=0
    while [ $n -lt \(writers) ]; do
      ( while :; do printf '%s\\n' "$pad"; done ) &
      n=$((n+1))
    done
    printf '{"a":1}\\n'
    """
}

@Test func leAsLinhasQueOProcessoEmite() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch(#"printf '{"a":1}\n{"b":2}\n'"#))

        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received == [#"{"a":1}"#, #"{"b":2}"#])
    }
}

@Test func capturaOStandardError() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch(#"echo aviso >&2; printf '{"a":1}\n'"#))
        for try await _ in stream {}
        let stderr = await transport.standardError
        #expect(stderr.contains("aviso"))
    }
}

@Test func escreveNoStdinEOProcessoResponde() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        // Ecoa cada linha recebida de volta, envelopada.
        let stream = try await transport.start(
            shellLaunch(#"while read -r l; do printf '{"echo":%s}\n' "$l"; done"#)
        )

        try await transport.write(Data(#"{"a":1}"#.utf8))
        try await transport.write(Data(#"{"b":2}"#.utf8))
        await transport.endInput()

        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received == [#"{"echo":{"a":1}}"#, #"{"echo":{"b":2}}"#])
    }
}

@Test func registraOCodigoDeSaida() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch("exit 3"))
        for try await _ in stream {}
        let status = await transport.terminationStatus
        #expect(status == 3)
    }
}

@Test func terminateDerrubaUmProcessoQueNaoTermina() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch("sleep 60"))
        let started = ContinuousClock.now
        await transport.terminate()
        for try await _ in stream {}
        let status = await transport.terminationStatus
        #expect(status != nil)
        // O polling tem que perceber o SIGTERM na hora: um encerramento bem
        // comportado não pode custar os 5 segundos do prazo até o SIGKILL.
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}

@Test func propagaErroDeEnquadramento() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport(framingLimit: 16)
        let stream = try await transport.start(shellLaunch(#"printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'"#))
        await #expect(throws: NDJSONFramer.FramingError.self) {
            for try await _ in stream {}
        }
    }
}

/// Saída corrompida não pode deixar um harness órfão: o fluxo já terminou com
/// erro, ninguém mais lê o stdout dele, e ele ficaria vivo travado na escrita.
@Test func erroDeEnquadramentoDerrubaOProcesso() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport(framingLimit: 16)
        let stream = try await transport.start(
            shellLaunch(#"printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'; sleep 30"#)
        )
        await #expect(throws: NDJSONFramer.FramingError.self) {
            for try await _ in stream {}
        }

        var status: Int32?
        for _ in 0..<100 {
            status = await transport.terminationStatus
            if status != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(status != nil)
    }
}

/// Um spawn que falha não pode deixar o transporte num estado meio montado:
/// perguntar o `terminationStatus` de um `Process` que nunca rodou levanta
/// exceção, e os leitores ficariam armados em pipes sem ninguém do outro lado.
@Test func falhaAoSubirUmExecutavelQueNaoExiste() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        var launch = shellLaunch("exit 0")
        launch.executable = "/nao/existe/harness"

        await #expect(throws: (any Error).self) {
            _ = try await transport.start(launch)
        }
        let status = await transport.terminationStatus
        #expect(status == nil)
    }
}

/// Nada pode se perder entre o último callback de leitura e a saída do
/// processo: as linhas que ainda estavam no pipe nesse instante contam.
@Test func naoPerdeLinhasDeUmaRajadaQueTerminaNaHora() async throws {
    try await withTimeout(seconds: 10) {
        let transport = ProcessTransport()
        let stream = try await transport.start(
            shellLaunch(#"i=1; while [ $i -le 2000 ]; do printf '{"n":%d}\n' "$i"; i=$((i+1)); done"#)
        )

        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received.count == 2000)
        #expect(received.first == #"{"n":1}"#)
        #expect(received.last == #"{"n":2000}"#)
    }
}

/// O dreno final não pode esperar o pipe fechar de verdade: um neto que herdou
/// stdout/stderr sobrevive ao harness, e esperar por ele travaria o fluxo para
/// sempre — uma sessão congelada sem erro nenhum (spec §4.4).
@Test func terminaOFluxoSemEsperarUmNetoQueHerdouOsPipes() async throws {
    try await withTimeout(seconds: 3) {
        let transport = ProcessTransport()
        let stream = try await transport.start(
            shellLaunch(#"(sleep 5) & printf '{"a":1}\n'"#)
        )

        let started = ContinuousClock.now
        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received == [#"{"a":1}"#])
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}

/// Um neto que herdou o stdout e *continua escrevendo* reenche o pipe tão rápido
/// quanto a varredura final o esvazia. Sem um teto, `poll` pode nunca devolver
/// 0: `continuation.finish()` nunca é alcançado, o fluxo nunca termina e a
/// sessão congela sem erro nenhum — tudo isso com o lock na mão e o buffer
/// crescendo na velocidade do pipe. O outro lado do neto que só segura os fds.
@Test func terminaOFluxoComUmNetoQueNaoParaDeEscrever() async throws {
    try await withTimeout(seconds: 3) {
        let transport = ProcessTransport()
        // Os netos despejam linhas de 4 KiB: o que interessa aqui é volume de
        // bytes, e linhas curtas só fariam o enquadrador dominar a medição.
        let stream = try await transport.start(shellLaunch(floodScript(writers: 16)))

        let started = ContinuousClock.now
        var received = 0
        for try await _ in stream { received += 1 }

        #expect(received > 0)
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}

/// O teto da varredura, medido direto no `readPending`. Pelo fluxo ele fica
/// escondido: enquanto o filho está vivo o `readabilityHandler` drena algumas
/// centenas de KiB do mesmo despejo, e esse ruído é maior que o próprio teto.
///
/// São várias varreduras porque uma só é uma amostra: quando o pipe fica vazio
/// por um instante, `poll` devolve 0 e mesmo uma varredura sem teto volta cedo.
/// O teto vale para *toda* varredura, então basta insistir.
@Test func aVarreduraFinalTemTeto() async throws {
    try await withTimeout(seconds: 10) {
        let target = Pipe()
        let flooder = Process()
        flooder.executableURL = URL(fileURLWithPath: "/bin/sh")
        flooder.arguments = ["-c", floodScript(writers: 32)]
        flooder.standardOutput = target
        try flooder.run()
        defer { flooder.terminate() }

        let ceiling = StreamIO.sweepByteLimit + StreamIO.sweepReadSize
        for _ in 0..<6 {
            // Deixa os escritores saturarem o pipe antes de cada varredura.
            try await Task.sleep(for: .milliseconds(5))
            let swept = StreamIO.readPending(target.fileHandleForReading)
            #expect(swept.count <= ceiling)
        }
    }
}

/// Um pipe de stderr cheio trava o filho dentro do `write`, e o sintoma é uma
/// sessão que congela sem erro nenhum (spec §4.4). Drenar só no fim não basta:
/// o dreno tem que ser contínuo, em paralelo com o stdout.
@Test func drenaStderrContinuamenteEnquantoOStdoutFlui() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        // 100 blocos de 4 KiB em stderr — muito acima dos 64 KiB que um pipe do
        // macOS segura — intercalados com as linhas NDJSON do stdout.
        let stream = try await transport.start(shellLaunch("""
            pad=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
            i=0; while [ $i -lt 7 ]; do pad="$pad$pad"; i=$((i+1)); done
            i=1
            while [ $i -le 100 ]; do
              printf '%s\\n' "$pad" >&2
              printf '{"n":%d}\\n' "$i"
              i=$((i+1))
            done
            """))

        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received.count == 100)
        #expect(received.first == #"{"n":1}"#)
        #expect(received.last == #"{"n":100}"#)

        // E nada de stderr se perdeu no caminho.
        let stderr = await transport.standardError
        #expect(stderr.count >= 100 * 4096)
    }
}

/// Escrever num pipe sem leitor dispara SIGPIPE, que por padrão mata o processo
/// *pai* — ou seja, o DevSpace inteiro. Tem que virar um erro comum.
@Test func escreverDepoisQueOFilhoFechouOStdinFalhaSemMatarOPai() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        // Fecha o stdin, avisa que fechou, e segue vivo — então a escrita passa
        // pela checagem de `isRunning` e bate mesmo num pipe sem leitor.
        let stream = try await transport.start(
            shellLaunch(#"exec 0<&-; printf '{"ready":1}\n'; sleep 5"#)
        )

        var iterator = stream.makeAsyncIterator()
        let ready = try await iterator.next()
        #expect(ready.map { String(decoding: $0, as: UTF8.self) } == #"{"ready":1}"#)

        await #expect(throws: (any Error).self) {
            try await transport.write(Data(#"{"a":1}"#.utf8))
        }
        await transport.terminate()
    }
}

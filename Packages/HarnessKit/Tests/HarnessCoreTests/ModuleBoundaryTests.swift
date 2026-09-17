import Testing
import Foundation
import HarnessCore

// Este alvo NÃO depende de ClaudeHarness. Se algum destes tipos voltar para
// lá, este arquivo deixa de compilar — que é exatamente o alarme desejado.
@Test func theGenericTypesLiveInHarnessCore() async throws {
    let transport = ProcessTransport()
    let stream = try await transport.start(ProcessTransport.Launch(
        executable: "/bin/sh",
        arguments: ["-c", #"printf '{"a":1}\n'"#],
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
    ))
    var lines: [String] = []
    for try await line in stream { lines.append(String(decoding: line, as: UTF8.self)) }
    #expect(lines == [#"{"a":1}"#])

    let install = HarnessInstallation(executable: "/usr/bin/true", version: "1.0.0")
    #expect(install.executable == "/usr/bin/true")

    let failure = CommandFailure(exitCode: 3, stderr: "boom")
    #expect(failure.exitCode == 3)
}

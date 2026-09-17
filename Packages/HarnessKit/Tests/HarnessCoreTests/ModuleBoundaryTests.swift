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

/// Item 5 do review final, e o mesmo alarme do teste acima uma camada mais
/// para cima. A spec §4.1 declara `PermissionRequest` e `PermissionDecision`
/// como tipos de apoio da abstração **neutra**; enquanto eles moravam em
/// `ClaudeHarness`, um adaptador do Codex precisava de `import ClaudeHarness`
/// só para dizer a palavra "allow".
///
/// Este arquivo NÃO importa `ClaudeHarness`. Se algum destes tipos voltar para
/// lá, ele deixa de compilar.
@Test func theNeutralPermissionTypesLiveInHarnessCore() throws {
    let request = PermissionRequest(
        id: "r-1",
        toolName: "Bash",
        input: .object(["command": .string("ls")]),
        suggestions: [PermissionSuggestion(type: "setMode", mode: "acceptEdits")]
    )
    #expect(request.toolName == "Bash")
    #expect(request.suggestions.first?.mode == "acceptEdits")

    let decision = PermissionDecision.allow(updatedInput: nil)
    #expect(decision == .allow(updatedInput: nil))

    // Item 6: o conjunto fechado da spec §12, também neutro.
    #expect(PermissionMode.allCases.count == 6)
    #expect(PermissionMode(rawValue: "acceptEdits") == .acceptEdits)
    // Um modo com typo é irrepresentável em vez de ser um erro do CLI em
    // tempo de execução — que é o ponto inteiro do item 6.
    #expect(PermissionMode(rawValue: "acceptEdit") == nil)
}

/// Item 8 do review final: o portão estrutural do próprio plano, agora
/// automático.
///
/// A regra da spec §7.1 é que `HarnessCore` não sabe da existência de harness
/// nenhum em particular, e o Step 7 da Task 1 a verificava à mão
/// (`grep -ril claude Sources/HarnessCore/`). Uma verificação manual num
/// checklist é uma verificação que um dia não é feita — e não foi: um
/// comentário em `JSONValue` justificava uma limitação aceita nomeando o
/// runtime de um harness específico. O alarme de compilação do teste acima
/// pega tipos no módulo errado; este pega *prosa* no módulo errado, que é o
/// caminho por onde o acoplamento volta primeiro.
///
/// Varre a fonte a partir de `#filePath` porque é o único caminho que o alvo
/// de teste conhece em tempo de compilação — `Bundle.module` daria os recursos
/// copiados, não a árvore de fontes.
@Test func harnessCoreNeverNamesASpecificHarness() throws {
    let core = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HarnessCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // HarnessKit
        .appending(path: "Sources/HarnessCore")

    let files = try #require(
        FileManager.default.enumerator(at: core, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    )
    #expect(!files.isEmpty, "a varredura não achou fonte nenhuma — o caminho mudou")

    // Nomes próprios de harness. Comentário, identificador ou string: se a
    // palavra aparece aqui, a §7.1 já foi quebrada.
    let forbidden = ["claude", "codex", "opencode"]
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8).lowercased()
        for name in forbidden where text.contains(name) {
            Issue.record("\(file.lastPathComponent) menciona \"\(name)\" — spec §7.1")
        }
    }
}

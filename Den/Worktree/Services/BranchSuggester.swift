import Foundation
import HarnessCore

nonisolated struct BranchSuggestion: Equatable, Sendable {
    let type: String
    let stem: String
}

nonisolated struct BranchSuggester: Sendable {
    typealias Run = @Sendable (_ executable: String, _ arguments: [String],
                               _ timeout: Duration) async -> ProcessOutcome?

    var run: Run = { executable, arguments, timeout in
        await TimedProcess.run(executable, arguments, timeout: timeout)
    }
    var timeout: Duration = .seconds(20)

    static func instruction(for message: String) -> String {
        "Gere o nome de uma branch git para o pedido a seguir, no padrão Conventional: "
            + "<tipo>/<descrição>. O tipo é um de \(BranchNamer.types.joined(separator: ", ")) e "
            + "descreve o trabalho pedido, porque o PR dessa branch também segue o Conventional Commits. "
            + "A descrição é sempre em inglês, mesmo que o pedido esteja em outro idioma, e tem de 2 a 5 "
            + "palavras em minúsculas, separadas por hífen. "
            + "Sem aspas e sem explicação. Responda somente o nome.\n\nPedido: \(message.prefix(600))"
    }

    func suggest(for message: String, harness: any Harness) async -> BranchSuggestion? {
        guard let arguments = harness.titleArguments(for: Self.instruction(for: message)),
              let installation = try? await harness.discover(),
              let outcome = await run(installation.executable, arguments, timeout),
              outcome.succeeded else { return nil }
        return Self.suggestion(from: outcome.output, message: message)
    }

    static func suggestion(from answer: String, message: String) -> BranchSuggestion? {
        let line = (answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t`\"'“”‘’"))
        guard !line.isEmpty, line.count <= 120 else { return nil }
        var type: String?
        var rest = line
        if let separator = line.firstIndex(where: { $0 == "/" || $0 == ":" }) {
            let head = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            if BranchNamer.types.contains(head) {
                type = head
                rest = String(line[line.index(after: separator)...])
            }
        }
        let key = BranchNamer.ticketKey(in: message)
        let described = key.map { rest.contains($0) ? rest : "\($0) \(rest)" } ?? rest
        guard let stem = BranchNamer.stem(for: described) else { return nil }
        return BranchSuggestion(type: type ?? BranchNamer.type(for: message), stem: stem)
    }
}

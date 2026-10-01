import Foundation

nonisolated enum ReplySuggestion {
    static let none = "NENHUMA"
    static let maxLength = 200
    static let requestLimit = 600
    static let replyLimit = 1_500

    static func isAsking(_ reply: String) -> Bool {
        let prose = reply.components(separatedBy: "```")
            .enumerated()
            .filter { $0.offset.isMultiple(of: 2) }
            .map(\.element)
            .joined(separator: "\n")
        return prose.split(whereSeparator: \.isNewline)
            .map { $0.replacing(/`[^`]*`/, with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(3)
            .contains { $0.contains(/\?(?=[\s)"”*_.]|$)/) }
    }

    static func instruction(request: String, reply: String) -> String {
        """
        Você sugere a resposta que o usuário daria a um assistente de programação. \
        Leia o pedido do usuário e a última mensagem do assistente. Se a mensagem \
        termina pedindo algo ao usuário (uma pergunta, uma escolha, uma confirmação), \
        escreva a resposta mais provável do usuário: curta (até 12 palavras), na voz \
        do usuário, na mesma língua, sem aspas. Se não há pergunta para o usuário, \
        responda exatamente \(none).

        Pedido do usuário: \(request.prefix(requestLimit))

        Última mensagem do assistente: \(reply.suffix(replyLimit))
        """
    }

    static func parse(_ output: String) -> String? {
        let cleaned = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned.count <= maxLength,
              !cleaned.contains(where: \.isNewline) else { return nil }
        let bare = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        return bare == none ? nil : cleaned
    }
}

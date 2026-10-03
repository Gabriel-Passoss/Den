import Foundation

nonisolated enum ReplySuggestion {
    static let noQuestion = "NENHUMA"
    static let maxLength = 200
    static let replyLimit = 1_500

    static func isAsking(_ reply: String) -> Bool {
        let prose = reply.components(separatedBy: "```")
            .enumerated()
            .filter { $0.offset.isMultiple(of: 2) }
            .map(\.element)
            .joined(separator: "\n")
        return prose.split(whereSeparator: \.isNewline)
            .reversed()
            .lazy
            .map { $0.replacing(#/`[^`]*`/#, with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .contains { $0.contains(#/\?(?=[\s)"”*_.]|$)/#) }
    }

    static func instruction(request: String, reply: String) -> String {
        """
        Você sugere a resposta que o usuário daria a um assistente de programação. \
        Leia o pedido do usuário e a última mensagem do assistente. Se a mensagem \
        termina pedindo algo ao usuário (uma pergunta, uma escolha, uma confirmação), \
        escreva a resposta mais provável do usuário: curta (até 12 palavras), na voz \
        do usuário, na mesma língua, sem aspas. Se não há pergunta para o usuário, \
        responda exatamente \(noQuestion).

        Pedido do usuário: \(request.prefix(QuickPrompt.requestLimit))

        Última mensagem do assistente: \(reply.suffix(replyLimit))
        """
    }

    static func parse(_ output: String) -> String? {
        guard let line = QuickPrompt.oneLine(output, maxLength: maxLength) else { return nil }
        let bare = line.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        return bare == noQuestion ? nil : line
    }
}

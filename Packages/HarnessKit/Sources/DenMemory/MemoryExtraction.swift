import Foundation
import HarnessCore

public struct MemoryCandidate: Equatable, Sendable {
    public let layer: MemoryLayer
    public let category: String
    public let title: String
    public let body: String
    public let page: String?

    public init(layer: MemoryLayer, category: String, title: String, body: String, page: String?) {
        self.layer = layer
        self.category = category
        self.title = title
        self.body = body
        self.page = page
    }
}

public enum MemoryExtraction {
    public static let excerptLimit = 16000
    public static let maximum = 5
    static let titleLimit = 120
    static let bodyLimit = 2000

    public static func userTurns(in entries: [TranscriptEntry]) -> Int {
        entries.count { entry in
            guard case .userMessage(let text, _) = entry.kind else { return false }
            let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !typed.isEmpty && !typed.hasPrefix("/") && !typed.hasPrefix("<")
        }
    }

    public static func instruction(entries: [TranscriptEntry], shelves: [MemoryRecall.Shelf]) -> String? {
        let lines = entries.compactMap(HandoffSeed.line(of:))
        guard !lines.isEmpty else { return nil }
        let known = shelves.flatMap { shelf in
            shelf.pages.map { "- [\(shelf.scope.layer.rawValue)] \($0.slug): \($0.title)" }
        }
        let hasProject = shelves.contains { $0.scope.layer == .project }
        let parts: [String?] = [
            rules,
            hasProject ? nil : "Esta conversa não está num repositório: use somente a camada \"user\".\n",
            "Páginas existentes:",
            known.isEmpty ? "(nenhuma)" : known.joined(separator: "\n"),
            "",
            "Conversa:",
            excerpt(of: lines),
        ]
        return parts.compactMap(\.self).joined(separator: "\n")
    }

    public static func candidates(from output: String) -> [MemoryCandidate]? {
        guard let open = output.firstIndex(of: "{"), let close = output.lastIndex(of: "}"), open < close,
              let reply = try? JSONDecoder().decode(JSONValue.self, from: Data(output[open...close].utf8)),
              case .array(let items)? = reply["memories"] else { return nil }
        return Array(items.compactMap(candidate(from:)).prefix(maximum))
    }

    private static func excerpt(of lines: [String]) -> String {
        let whole = lines.joined(separator: "\n\n")
        guard whole.count > excerptLimit else { return whole }
        return "[início da conversa omitido]\n" + whole.suffix(excerptLimit)
    }

    private static func candidate(from item: JSONValue) -> MemoryCandidate? {
        guard let layer = MemoryLayer(rawValue: text(item["layer"]).lowercased()) else { return nil }
        let title = text(item["title"])
        let body = text(item["body"])
        guard !title.isEmpty, title.count <= titleLimit, !body.isEmpty, body.count <= bodyLimit,
              !holdsSecret(title + "\n" + body), !MemoryRecall.mentionsBlock(title + "\n" + body)
        else { return nil }
        let category = text(item["category"])
        let page = text(item["page"])
        return MemoryCandidate(layer: layer, category: category.isEmpty ? MemoryCategory.note.rawValue : category,
                               title: title, body: body, page: page.isEmpty ? nil : page)
    }

    private static func text(_ value: JSONValue?) -> String {
        (value?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func holdsSecret(_ text: String) -> Bool {
        text.contains(/-----BEGIN [A-Z ]*PRIVATE KEY-----/)
            || text.contains(/\bgh[pousr]_[A-Za-z0-9]{20,}/)
            || text.contains(/\bsk-[A-Za-z0-9_\-]{20,}/)
            || text.contains(/\bAKIA[0-9A-Z]{16}\b/)
            || text.contains(/\bxox[baprs]-[A-Za-z0-9\-]{10,}/)
    }

    private static let rules = """
        Você mantém a memória de longo prazo de um assistente de programação. Leia o trecho de conversa \
        no fim e extraia apenas o que vale lembrar em sessões futuras.

        Guarde somente fatos duráveis:
        - camada "project": o que vale só para este repositório — convenções, nomenclatura, decisões de \
        arquitetura com o motivo, regras de negócio, termos do domínio, armadilhas, comandos de build e teste.
        - camada "user": o que vale para o usuário em qualquer repositório — estilo de código, regras \
        permanentes, processos, preferências de comunicação, ambiente.

        Não guarde o que foi feito nesta tarefa, estado temporário, pendências, o que já está numa página \
        existente sem mudança, nem segredo algum (senha, token, chave).

        Categorias de "project": \(names(of: .project)).
        Categorias de "user": \(names(of: .user)).

        Uma memória por fato, no máximo \(maximum). Título curto; corpo em até 600 caracteres, em markdown, \
        na língua da conversa, dizendo a regra e, quando houver, o motivo. Para corrigir ou completar uma \
        página existente, repita o identificador dela em "page"; senão deixe "page" vazio.

        Responda somente com JSON, sem texto antes ou depois, neste formato:
        {"memories": [{"layer": "project", "category": "convention", "title": "...", "body": "...", "page": ""}]}
        Se não houver nada durável, responda {"memories": []}.

        """

    private static func names(of layer: MemoryLayer) -> String {
        MemoryCategory.known(in: layer).map(\.rawValue).joined(separator: ", ")
    }
}

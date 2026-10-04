import Foundation

public enum MemoryLayer: String, Sendable, CaseIterable {
    case user
    case project
}

public enum MemoryCategory: String, Sendable, CaseIterable {
    case convention
    case naming
    case architecture
    case businessRule = "business-rule"
    case glossary
    case pitfall
    case command
    case codeStyle = "code-style"
    case rule
    case workflow
    case communication
    case environment
    case note

    public var layer: MemoryLayer? {
        switch self {
        case .convention, .naming, .architecture, .businessRule, .glossary, .pitfall, .command: .project
        case .codeStyle, .rule, .workflow, .communication, .environment: .user
        case .note: nil
        }
    }

    public var label: String {
        switch self {
        case .convention: "Convenções"
        case .naming: "Nomenclatura"
        case .architecture: "Arquitetura e decisões"
        case .businessRule: "Regras de negócio"
        case .glossary: "Glossário"
        case .pitfall: "Armadilhas"
        case .command: "Comandos"
        case .codeStyle: "Estilo de código"
        case .rule: "Regras"
        case .workflow: "Processos"
        case .communication: "Comunicação"
        case .environment: "Ambiente"
        case .note: "Notas"
        }
    }

    public static func known(in layer: MemoryLayer) -> [MemoryCategory] {
        allCases.filter { $0.belongs(to: layer) }
    }

    public static func parse(_ raw: String, in layer: MemoryLayer) -> MemoryCategory {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard let category = MemoryCategory(rawValue: name), category.belongs(to: layer) else { return .note }
        return category
    }

    private func belongs(to layer: MemoryLayer) -> Bool {
        self.layer == nil || self.layer == layer
    }
}

public struct MemoryPage: Identifiable, Equatable, Sendable {
    public var slug: String
    public var title: String
    public var category: MemoryCategory
    public var body: String
    public var created: Date
    public var updated: Date
    public var sessions: [UUID]

    public var id: String { slug }

    public init(slug: String, title: String, category: MemoryCategory, body: String,
                created: Date, updated: Date, sessions: [UUID] = []) {
        self.slug = slug
        self.title = title
        self.category = category
        self.body = body
        self.created = created
        self.updated = updated
        self.sessions = sessions
    }
}

public struct HarnessKnob: Identifiable, Sendable, Equatable {

    public enum Category: String, Sendable, Equatable {
        case model, effort, mode
    }

    public struct Option: Sendable, Equatable {
        public let value: String
        public let label: String

        /// Cabeçalho da seção a que a opção pertence, quando o harness oferece
        /// uma lista longa o bastante para pedir divisão — dezenas de modelos
        /// separados por provedor, por exemplo. `nil` desenha lista plana.
        public let group: String?

        public init(value: String, label: String, group: String? = nil) {
            self.value = value
            self.label = label
            self.group = group
        }
    }

    public let id: String
    public let category: Category
    public let name: String

    public var currentValue: String?
    public var options: [Option]

    public init(id: String, category: Category, name: String,
                currentValue: String? = nil, options: [Option] = []) {
        self.id = id
        self.category = category
        self.name = name
        self.currentValue = currentValue
        self.options = options
    }

    public func label(for value: String?) -> String? {
        guard let value else { return nil }
        return options.first { $0.value == value }?.label ?? value
    }

    /// As opções na ordem em que chegaram, quebradas nas seções que declararam.
    /// Uma seção só existe se alguma opção a nomeou, então harnesses de lista
    /// plana devolvem um único grupo sem título.
    public var groupedOptions: [(group: String?, options: [Option])] {
        var groups: [(group: String?, options: [Option])] = []
        for option in options {
            if let last = groups.last, last.group == option.group {
                groups[groups.count - 1].options.append(option)
            } else {
                groups.append((group: option.group, options: [option]))
            }
        }
        return groups
    }
}

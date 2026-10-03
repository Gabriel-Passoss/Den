public struct RecordArguments: Equatable, Sendable {
    public var prompt: String
    public var cwd: String
    public var outputPath: String?

    public init(prompt: String, cwd: String, outputPath: String? = nil) {
        self.prompt = prompt
        self.cwd = cwd
        self.outputPath = outputPath
    }
}

public enum RecordArgumentError: Error, Equatable, Sendable {

    case missingValue(flag: String)

    case emptyValue(flag: String)

    case unknownFlag(String)

    case missingRequired(flag: String)

    public var message: String {
        switch self {
        case .missingValue(let flag):
            "\(flag) foi informado sem um valor válido."
        case .emptyValue(let flag):
            "\(flag) foi informado com um valor vazio (ou só espaços) — confira se a variável de shell usada não está vazia."
        case .unknownFlag(let flag):
            "flag desconhecida: \(flag)"
        case .missingRequired(let flag):
            "\(flag) é obrigatório."
        }
    }
}

public func parseRecordArguments(_ args: [String]) -> Result<RecordArguments, RecordArgumentError> {
    scanFlags(args, known: ["--prompt", "--cwd", "--out"]).flatMap { values in
        guard let prompt = values["--prompt"] else {
            return .failure(.missingRequired(flag: "--prompt"))
        }
        guard let cwd = values["--cwd"] else {
            return .failure(.missingRequired(flag: "--cwd"))
        }
        return .success(RecordArguments(prompt: prompt, cwd: cwd, outputPath: values["--out"]))
    }
}

public struct PermissionArguments: Equatable, Sendable {
    public var prompt: String
    public var cwd: String

    public init(prompt: String, cwd: String) {
        self.prompt = prompt
        self.cwd = cwd
    }
}

public func parsePermissionArguments(_ args: [String]) -> Result<PermissionArguments, RecordArgumentError> {
    scanFlags(args, known: ["--prompt", "--cwd"]).flatMap { values in
        guard let prompt = values["--prompt"] else {
            return .failure(.missingRequired(flag: "--prompt"))
        }
        guard let cwd = values["--cwd"] else {
            return .failure(.missingRequired(flag: "--cwd"))
        }
        return .success(PermissionArguments(prompt: prompt, cwd: cwd))
    }
}

private func scanFlags(
    _ args: [String],
    known: Set<String>
) -> Result<[String: String], RecordArgumentError> {
    var values: [String: String] = [:]
    var index = args.startIndex
    while index < args.endIndex {
        let flag = args[index]
        guard known.contains(flag) else {
            return .failure(.unknownFlag(flag))
        }

        let valueIndex = args.index(after: index)
        guard valueIndex < args.endIndex, !args[valueIndex].hasPrefix("--") else {
            return .failure(.missingValue(flag: flag))
        }
        let value = args[valueIndex]
        guard !value.isBlankValue else {
            return .failure(.emptyValue(flag: flag))
        }

        values[flag] = value
        index = args.index(after: valueIndex)
    }
    return .success(values)
}

public enum PermissionAnswer: Equatable, Sendable {
    case allow
    case deny
}

public func parsePermissionAnswer(_ line: String?) -> PermissionAnswer {
    guard let line else { return .deny }
    let normalized = line.lowercased().filter { !$0.isWhitespace }
    let yes: Set<String> = ["s", "sim", "y", "yes", "a", "allow", "p", "permitir"]
    return yes.contains(normalized) ? .allow : .deny
}

private extension String {

    var isBlankValue: Bool {
        allSatisfy(\.isWhitespace)
    }
}

public struct FileSystemProbe: Sendable {

    public var exists: @Sendable (String) -> Bool

    public var isDirectory: @Sendable (String) -> Bool

    public init(
        exists: @escaping @Sendable (String) -> Bool,
        isDirectory: @escaping @Sendable (String) -> Bool
    ) {
        self.exists = exists
        self.isDirectory = isDirectory
    }
}

public enum RecordPreflightError: Error, Equatable, Sendable {
    case cwdNotFound(String)
    case cwdNotADirectory(String)
    case outputAlreadyExists(String)

    public var message: String {
        switch self {
        case .cwdNotFound(let path):
            """
            --cwd não existe: \(path)
            confira o caminho — um caractere errado aqui só apareceria como erro \
            depois de o processo já ter sido lançado contra ele.
            """
        case .cwdNotADirectory(let path):
            "--cwd não é um diretório: \(path)"
        case .outputAlreadyExists(let path):
            """
            --out já existe: \(path)
            recusando sobrescrever. Uma gravação custa dinheiro real e leva \
            minutos; um arquivo truncado por engano não volta. Escolha outro \
            caminho, ou apague este explicitamente antes de regravar.
            """
        }
    }

    public var exitCode: Int32 {
        switch self {
        case .cwdNotFound, .cwdNotADirectory: 66
        case .outputAlreadyExists: 73
        }
    }
}

public func preflightRecord(
    _ arguments: RecordArguments,
    on fileSystem: FileSystemProbe
) -> RecordPreflightError? {
    guard fileSystem.exists(arguments.cwd) else {
        return .cwdNotFound(arguments.cwd)
    }
    guard fileSystem.isDirectory(arguments.cwd) else {
        return .cwdNotADirectory(arguments.cwd)
    }
    if let outputPath = arguments.outputPath, fileSystem.exists(outputPath) {
        return .outputAlreadyExists(outputPath)
    }
    return nil
}

/// O estado do sistema de arquivos que o preflight precisa consultar, injetado
/// como duas perguntas em vez de um `FileManager`.
///
/// Mantém este alvo livre de Foundation e de I/O — a mesma razão pela qual
/// `parseRecordArguments` mora aqui — e, mais importante, torna a **ordem** e o
/// **veredito** das checagens testáveis sem criar diretório nenhum. O bug que
/// este preflight existe para impedir é de ordenação: hoje a validação acontecia
/// tarde demais, depois de o arquivo de saída já ter sido truncado.
public struct FileSystemProbe: Sendable {
    /// Existe algo neste caminho (arquivo, diretório ou symlink).
    public var exists: @Sendable (String) -> Bool
    /// Existe e é um diretório.
    public var isDirectory: @Sendable (String) -> Bool

    public init(
        exists: @escaping @Sendable (String) -> Bool,
        isDirectory: @escaping @Sendable (String) -> Bool
    ) {
        self.exists = exists
        self.isDirectory = isDirectory
    }
}

/// Por que `record` recusou argumentos que o parser já tinha aceitado.
///
/// São erros que o parser **não** pode dar: ele é uma função pura e não toca o
/// disco de propósito. Estes dependem do estado da máquina, e por isso vivem
/// numa segunda fase — que ainda assim roda antes de qualquer efeito colateral.
public enum RecordPreflightError: Error, Equatable, Sendable {
    case cwdNotFound(String)
    case cwdNotADirectory(String)
    case outputAlreadyExists(String)

    public var message: String {
        switch self {
        case .cwdNotFound(let path):
            return """
            --cwd não existe: \(path)
            confira o caminho — um caractere errado aqui só apareceria como erro \
            depois de o processo já ter sido lançado contra ele.
            """
        case .cwdNotADirectory(let path):
            return "--cwd não é um diretório: \(path)"
        case .outputAlreadyExists(let path):
            return """
            --out já existe: \(path)
            recusando sobrescrever. Uma gravação custa dinheiro real e leva \
            minutos; um arquivo truncado por engano não volta. Escolha outro \
            caminho, ou apague este explicitamente antes de regravar.
            """
        }
    }

    /// Códigos de `sysexits.h`, os mesmos que o resto do `harness-probe` usa.
    public var exitCode: Int32 {
        switch self {
        case .cwdNotFound, .cwdNotADirectory: return 66 // EX_NOINPUT
        case .outputAlreadyExists: return 73 // EX_CANTCREAT
        }
    }
}

/// Checa, **antes de qualquer efeito colateral**, o que o parser não tinha como
/// checar. Devolve `nil` quando está tudo certo.
///
/// ## Ordem
///
/// `--cwd` primeiro, `--out` depois. A ordem não é estética: o vetor real é um
/// typo em `--cwd` combinado com um `--out` correto apontando para um fixture
/// que já existe. Reportar o argumento que foi de fato digitado errado é o que
/// transforma "não foi possível criar o arquivo" numa mensagem acionável.
///
/// ## Por que a recusa de `--out` é dura, sem `--force`
///
/// Os usuários desta ferramenta são o operador e agentes futuros, e ambos já
/// destruíram coisas com typo. Uma flag `--force` é justamente o tipo de token
/// que entra numa linha de comando memorizada e nunca mais sai — rearmando a
/// destruição exata que a checagem existe para impedir, agora com aprovação
/// prévia. Uma recusa dura força um `rm` separado e deliberado, que não cabe
/// dentro da linha de gravação por descuido.
///
/// Há também uma razão estrutural: `--force` seria a primeira flag booleana do
/// parser, que hoje tem um invariante simples e testado — *todo* token é uma
/// flag conhecida ou o valor da flag anterior. Uma flag sem valor reintroduz
/// exatamente a classe de ambiguidade (`--prompt --force`) que custou dois
/// lançamentos reais e não intencionais do `claude`.
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

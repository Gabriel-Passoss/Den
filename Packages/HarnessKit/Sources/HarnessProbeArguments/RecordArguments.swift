/// Argumentos já validados de `harness-probe record`.
///
/// Extraído para um alvo próprio (em vez de viver como código de topo em
/// `main.swift`) especificamente para ser testável: um alvo executável cujo
/// arquivo se chama `main.swift` não pode ser importado por um alvo de teste,
/// então a lógica de parsing — a parte com bugs de verdade, comprovados em
/// produção duas vezes — precisa morar num lugar que os testes alcancem.
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

/// Por que `parseRecordArguments` recusou a lista de argumentos.
public enum RecordArgumentError: Error, Equatable, Sendable {
    /// Uma flag reconhecida apareceu sem um valor válido depois dela — seja
    /// por ser o último token da lista, seja porque o próximo token começa
    /// com "--" (e portanto é outra flag, não um valor).
    case missingValue(flag: String)
    /// Um token não é nenhuma das flags reconhecidas — nunca ignorado.
    case unknownFlag(String)
    /// Uma flag obrigatória (`--prompt` ou `--cwd`) nunca apareceu.
    case missingRequired(flag: String)

    public var message: String {
        switch self {
        case .missingValue(let flag):
            return "\(flag) foi informado sem um valor válido."
        case .unknownFlag(let flag):
            return "flag desconhecida: \(flag)"
        case .missingRequired(let flag):
            return "\(flag) é obrigatório."
        }
    }
}

/// Parseia os argumentos de `record` (sem o token do subcomando) numa única
/// passada sequencial.
///
/// ## Contrato
///
/// - Cada token da lista é OU uma das flags reconhecidas (`--prompt`,
///   `--cwd`, `--out`) OU o valor que pertence à flag imediatamente anterior.
///   Não existem posicionais.
/// - **Um token que começa com `--` nunca é aceito como valor**, mesmo na
///   posição onde um valor era esperado — ele é sempre tratado como a
///   próxima flag, e a flag anterior fica sem valor (erro
///   `.missingValue`). Isto existe porque a versão anterior deste parser
///   escaneava `args` uma vez por flag, independentemente: `--prompt --cwd
///   /tmp/x` fazia a busca por `--prompt` achar o valor `"--cwd"` (o token
///   seguinte, sem checar o que ele era) e, separadamente, a busca por
///   `--cwd` achar esse *mesmo* token como a flag de verdade. As duas
///   buscas passavam ao mesmo tempo, e um `claude` real era lançado com um
///   `--cwd` que nunca deveria ter sido aceito como argumento de
///   `--prompt`. Uma única passada, com essa regra, torna essa ambiguidade
///   irrepresentável: o token só pode desempenhar um papel.
/// - `--prompt` e `--cwd` são obrigatórios; `--out` é opcional.
/// - Qualquer token que não seja uma das três flags reconhecidas é um erro
///   (`.unknownFlag`) — nunca ignorado silenciosamente. Um typo na flag falha
///   alto, em vez de cair num default.
///
/// Devolve `Result` em vez de `throws` para que o chamador seja obrigado, no
/// próprio tipo, a lidar com os dois casos antes de agir sobre o resultado —
/// nada aqui deveria propagar como um erro Swift não tratado até o topo.
public func parseRecordArguments(_ args: [String]) -> Result<RecordArguments, RecordArgumentError> {
    let known: Set<String> = ["--prompt", "--cwd", "--out"]

    var prompt: String?
    var cwd: String?
    var outputPath: String?

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

        switch flag {
        case "--prompt": prompt = value
        case "--cwd": cwd = value
        case "--out": outputPath = value
        default: break // inatingível: `known` já filtrou os três casos acima
        }

        index = args.index(after: valueIndex)
    }

    guard let prompt else { return .failure(.missingRequired(flag: "--prompt")) }
    guard let cwd else { return .failure(.missingRequired(flag: "--cwd")) }
    return .success(RecordArguments(prompt: prompt, cwd: cwd, outputPath: outputPath))
}

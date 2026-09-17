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
    /// Uma flag reconhecida apareceu com um valor presente, mas vazio ou só
    /// espaço em branco. Caso distinto de `.missingValue` de propósito: o
    /// vetor real é uma variável de shell vazia (`--cwd "$VAR"` com `VAR`
    /// não setada), não um token esquecido — e a mensagem certa para cada
    /// um é diferente o suficiente para valer a separação.
    case emptyValue(flag: String)
    /// Um token não é nenhuma das flags reconhecidas — nunca ignorado.
    case unknownFlag(String)
    /// Uma flag obrigatória (`--prompt` ou `--cwd`) nunca apareceu.
    case missingRequired(flag: String)

    public var message: String {
        switch self {
        case .missingValue(let flag):
            return "\(flag) foi informado sem um valor válido."
        case .emptyValue(let flag):
            return "\(flag) foi informado com um valor vazio (ou só espaços) — confira se a variável de shell usada não está vazia."
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
/// - **Um valor vazio ou só com espaço em branco é sempre erro**
///   (`.emptyValue`), mesmo quando o token está presente. `"".hasPrefix("--")`
///   é `false`, então sem esta regra `--cwd ""` passava a guarda acima como
///   valor "válido" — e `URL(fileURLWithPath: "")`, do lado de quem consome
///   `RecordArguments`, resolve para o diretório de trabalho real do
///   processo. O vetor realista é um idiom de shell comum,
///   `--cwd "$SCRATCH_DIR"` com a variável vazia ou não setada — o mesmo
///   resultado que `--cwd` obrigatório existia para impedir, alcançado por
///   ausência de validação em vez de ambiguidade de token.
///
/// Devolve `Result` em vez de `throws` para que o chamador seja obrigado, no
/// próprio tipo, a lidar com os dois casos antes de agir sobre o resultado —
/// nada aqui deveria propagar como um erro Swift não tratado até o topo.
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

/// Argumentos já validados de `harness-probe permission`.
///
/// Não tem `--out` de propósito: este subcomando não grava fixture nenhum, e
/// aceitar a flag para depois ignorá-la seria mentir no `usage`. Um `--out`
/// aqui é `.unknownFlag`, como qualquer outro token não reconhecido.
public struct PermissionArguments: Equatable, Sendable {
    public var prompt: String
    public var cwd: String

    public init(prompt: String, cwd: String) {
        self.prompt = prompt
        self.cwd = cwd
    }
}

/// Mesmo contrato e mesma passada única de `parseRecordArguments` — os dois
/// compartilham `scanFlags`, para que o invariante que custou dois lançamentos
/// reais e não intencionais do `claude` valha nos dois subcomandos em vez de
/// ser reimplementado no segundo.
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

/// A passada única, sem saber quais flags são obrigatórias — isso é decisão de
/// cada subcomando. Devolve o valor de cada flag que apareceu.
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

/// O que o operador respondeu a um pedido de permissão no terminal.
public enum PermissionAnswer: Equatable, Sendable {
    case allow
    case deny
}

/// Lê a resposta do operador. `nil` é o EOF do stdin.
///
/// **Tudo que não for um "sim" reconhecido é `deny`** — linha vazia, texto
/// desconhecido, e EOF. Não há default permissivo e não há repergunta: este é
/// o portão de permissão do produto, e a única resposta segura para uma
/// entrada ambígua é a que não executa a ferramenta. O EOF importa na prática,
/// não em teoria: rodar o probe com o stdin redirecionado (de um pipe, de um
/// arquivo, de um agente) faz `readLine()` devolver `nil` na primeira pergunta,
/// e um default permissivo ali aprovaria toda chamada de ferramenta de uma
/// sessão inteira sem ninguém ler nada.
///
/// A comparação é sem caixa e sem espaço nas pontas — "  Sim  " é sim —, e
/// aceita as duas línguas porque o texto da pergunta é em português e os
/// identificadores do protocolo são em inglês.
public func parsePermissionAnswer(_ line: String?) -> PermissionAnswer {
    guard let line else { return .deny }
    let normalized = line.lowercased().filter { !$0.isWhitespace }
    let yes: Set<String> = ["s", "sim", "y", "yes", "a", "allow", "p", "permitir"]
    return yes.contains(normalized) ? .allow : .deny
}

extension String {
    /// Vazia, ou só espaço em branco (inclui tabs e quebras de linha). Sem
    /// depender de Foundation — `Character.isWhitespace` já é da biblioteca
    /// padrão — para este alvo continuar livre de I/O e de dependências
    /// pesadas, coerente com o resto do parser sendo uma função pura.
    fileprivate var isBlankValue: Bool {
        allSatisfy(\.isWhitespace)
    }
}

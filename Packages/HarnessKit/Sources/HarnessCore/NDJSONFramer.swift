import Foundation

/// Converte um fluxo de bytes em linhas NDJSON completas.
///
/// Mantém em buffer a linha parcial entre chamadas, porque um chunk lido de um
/// pipe quase nunca coincide com a fronteira de uma linha.
public struct NDJSONFramer: Sendable {
    public enum FramingError: Error, Equatable {
        /// A linha parcial passou do teto sem nenhuma quebra de linha à vista.
        /// Sinaliza saída corrompida ou não-NDJSON — não vale continuar lendo.
        case lineTooLong(limit: Int)
    }

    private static let newline: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    private var buffer = Data()
    private let limit: Int

    public init(limit: Int = 8 * 1024 * 1024) {
        self.limit = limit
    }

    /// Consome um chunk e devolve as linhas que ficaram completas com ele.
    /// Linhas vazias são descartadas.
    ///
    /// `searchStart` marca ao mesmo tempo (a) de onde a próxima busca por
    /// `\n` deve continuar e (b) até onde o buffer já foi consumido — as
    /// duas coisas coincidem porque uma linha só é consumida quando sua
    /// quebra de linha é encontrada. Isso evita re-fatiar a cauda inteira
    /// do buffer a cada linha extraída (custo O(n·k) para um chunk com k
    /// linhas); em vez disso, o prefixo consumido é descartado uma única
    /// vez, depois do laço — O(n) no total.
    ///
    /// Cuidado com índices de `Data`: uma fatia (`buffer[a..<b]`) preserva
    /// o espaço de índices do buffer pai — não começa em 0. `searchStart`
    /// e `index` abaixo são sempre índices do próprio `buffer`, nunca de
    /// uma fatia derivada, então nunca ficam fora de base. O único lugar
    /// em que precisamos reancorar para 0 é ao empacotar uma linha para
    /// devolução (`Data(buffer[...])`), porque esse valor sai do struct e
    /// passa a viver com índices próprios.
    public mutating func push(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)

        var lines: [Data] = []
        var searchStart = buffer.startIndex
        while let index = buffer[searchStart...].firstIndex(of: Self.newline) {
            var line = Data(buffer[searchStart..<index])
            searchStart = buffer.index(after: index)
            if line.count > limit {
                throw FramingError.lineTooLong(limit: limit)
            }
            if line.last == Self.carriageReturn { line.removeLast() }
            if !line.isEmpty { lines.append(line) }
        }
        buffer.removeSubrange(buffer.startIndex..<searchStart)

        if buffer.count > limit {
            throw FramingError.lineTooLong(limit: limit)
        }
        return lines
    }
}

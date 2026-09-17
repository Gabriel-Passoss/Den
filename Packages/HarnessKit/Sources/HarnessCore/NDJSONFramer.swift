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
    public mutating func push(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)

        var lines: [Data] = []
        while let index = buffer.firstIndex(of: Self.newline) {
            var line = Data(buffer[buffer.startIndex..<index])
            buffer = Data(buffer[buffer.index(after: index)...])
            if line.last == Self.carriageReturn { line.removeLast() }
            if !line.isEmpty { lines.append(line) }
        }

        if buffer.count > limit {
            throw FramingError.lineTooLong(limit: limit)
        }
        return lines
    }
}

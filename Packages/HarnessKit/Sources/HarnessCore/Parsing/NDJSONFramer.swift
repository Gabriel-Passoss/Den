import Foundation

public struct NDJSONFramer: Sendable {
    public enum FramingError: Error, Equatable {

        case lineTooLong(limit: Int)
    }

    private static let newline: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    private var buffer = Data()
    private let limit: Int

    public init(limit: Int = 8 * 1024 * 1024) {
        self.limit = limit
    }

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

import Foundation

public enum Value: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public var textValue: String? {
        if case .text(let text) = self { return text }
        return nil
    }

    public var integerValue: Int64? {
        if case .integer(let number) = self { return number }
        return nil
    }

    public var realValue: Double? {
        switch self {
        case .real(let number): number
        case .integer(let number): Double(number)
        case .null, .text, .blob: nil
        }
    }
}

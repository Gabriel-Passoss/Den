import Foundation

enum JSONText {
    enum Flavor {
        case transcript
        case document
    }

    static func encode(_ value: some Encodable, as flavor: Flavor) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if flavor == .transcript { encoder.dateEncodingStrategy = .iso8601 }
        return try String(decoding: encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String, as flavor: Flavor) -> T? {
        let decoder = JSONDecoder()
        if flavor == .transcript { decoder.dateDecodingStrategy = .iso8601 }
        return try? decoder.decode(type, from: Data(text.utf8))
    }
}

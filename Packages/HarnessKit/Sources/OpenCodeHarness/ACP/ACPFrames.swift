import Foundation
import HarnessCore

public enum ACPResult: Equatable, Sendable {
    case success(JSONValue)
    case failure(code: Int, message: String)

    public var payload: JSONValue? {
        if case .success(let value) = self { return value }
        return nil
    }

    public var errorMessage: String? {
        if case .failure(_, let message) = self { return message }
        return nil
    }
}

public enum ACPFrame: Equatable, Sendable {

    case response(id: Int, ACPResult)

    case request(id: JSONValue, method: String, params: JSONValue)

    case notification(method: String, params: JSONValue)

    case malformed(JSONValue)

    public static func classify(_ line: Data) -> ACPFrame {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line) else {
            return .malformed(.string(String(decoding: line, as: UTF8.self)))
        }
        let params = value["params"] ?? .null

        if let method = value["method"]?.stringValue {

            guard let id = value["id"], id != .null else {
                return .notification(method: method, params: params)
            }
            return .request(id: id, method: method, params: params)
        }

        guard let id = value["id"]?.intValue else { return .malformed(value) }

        if let error = value["error"] {
            return .response(id: id, .failure(
                code: error["code"]?.intValue ?? 0,
                message: error["message"]?.stringValue ?? "erro sem mensagem"))
        }
        guard let result = value["result"] else { return .malformed(value) }
        return .response(id: id, .success(result))
    }
}

enum ACPWire {
    static let version = JSONValue.string("2.0")

    static func request(id: Int, method: String, params: JSONValue) throws -> Data {
        try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": version,
            "id": .int(id),
            "method": .string(method),
            "params": params,
        ]))
    }

    static func notification(method: String, params: JSONValue) throws -> Data {
        try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": version,
            "method": .string(method),
            "params": params,
        ]))
    }

    static func response(id: JSONValue, result: JSONValue) throws -> Data {
        try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": version,
            "id": id,
            "result": result,
        ]))
    }

    static func errorResponse(id: JSONValue, code: Int, message: String) throws -> Data {
        try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": version,
            "id": id,
            "error": .object([
                "code": .int(code),
                "message": .string(message),
            ]),
        ]))
    }

    static let methodNotFound = -32601
}

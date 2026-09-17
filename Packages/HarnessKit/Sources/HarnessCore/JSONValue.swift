import Foundation

/// Um valor JSON qualquer, preservado sem esquema.
///
/// Inteiro e ponto flutuante são casos distintos de propósito: `Double`
/// representa inteiros exatamente só até 2^53 — acima disso, a precisão se
/// perde de forma silenciosa (sem erro, sem crash). O `input` de uma
/// ferramenta é devolvido ao CLI quando o usuário permite a chamada, e esse
/// input pode carregar ids, offsets de byte ou timestamps em nanossegundos
/// grandes o bastante para passar de 2^53. Um único caso `.number(Double)`
/// corromperia esses valores silenciosamente no round-trip.
///
/// Limitação conhecida e aceita: um número JSON sem resto fracionário
/// decodifica sempre como `.int`, não importa como foi escrito no fixture
/// original — `decode(Int.self)` aceita o token `1.0` porque ele não tem
/// parte fracionária. `{"opacity":1.0}` vira `.int(1)` e reencoda como
/// `{"opacity":1}`: o ponto decimal se perde. Isso é aceitável porque o
/// consumidor real (Claude Code, um processo Node) trata `1` e `1.0` como o
/// mesmo `Number` em JavaScript — a diferença é inobservável do outro lado
/// do pipe. Seria inaceitável para um harness cuja linguagem distingue os
/// dois; nesse caso este tipo precisaria de um parser JSON próprio que
/// preserva a forma do token, não apenas o `Codable` de container único.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

public extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    var stringValue: String? {
        guard case .string(let s) = self else { return nil }
        return s
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let o) = self else { return nil }
        return o
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let a) = self else { return nil }
        return a
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        // Int antes de Double: acima de 2^53, Double perde precisão inteira de
        // forma silenciosa (9007199254740993 viraria 9007199254740992). Essa
        // ordem é o que impede essa corrupção — não "simplifique" trocando-a.
        if let i = try? container.decode(Int.self) { self = .int(i); return }
        if let d = try? container.decode(Double.self) { self = .double(d); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? container.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "valor JSON não reconhecido"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

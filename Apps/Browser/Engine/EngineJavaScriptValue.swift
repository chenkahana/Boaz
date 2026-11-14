import Foundation

indirect enum EngineJavaScriptValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([EngineJavaScriptValue])
    case object([String: EngineJavaScriptValue])

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let result = try? value.decode(Bool.self) { self = .bool(result) }
        else if let result = try? value.decode(Double.self) { self = .number(result) }
        else if let result = try? value.decode(String.self) { self = .string(result) }
        else if let result = try? value.decode([EngineJavaScriptValue].self) { self = .array(result) }
        else { self = .object(try value.decode([String: EngineJavaScriptValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let result): try value.encode(result)
        case .number(let result): try value.encode(result)
        case .string(let result): try value.encode(result)
        case .array(let result): try value.encode(result)
        case .object(let result): try value.encode(result)
        }
    }
}

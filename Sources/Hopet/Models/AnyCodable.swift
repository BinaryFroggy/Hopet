import Foundation

/// 适配任意 JSON 标量/对象/数组的 Codable 包装器。
/// 仅用于 StateEvent.payload；内部会保留嵌套结构以便点号路径取值。
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.value = NSNull(); return }
        if let b = try? container.decode(Bool.self) { self.value = b; return }
        if let i = try? container.decode(Int.self) { self.value = i; return }
        if let d = try? container.decode(Double.self) { self.value = d; return }
        if let s = try? container.decode(String.self) { self.value = s; return }
        if let arr = try? container.decode([AnyCodable].self) { self.value = arr.map { $0.value }; return }
        if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:                 try container.encodeNil()
        case let b as Bool:             try container.encode(b)
        case let i as Int:              try container.encode(i)
        case let d as Double:           try container.encode(d)
        case let s as String:           try container.encode(s)
        case let arr as [Any]:          try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }
}

extension AnyCodable {
    /// 按点号路径（如 "tool_input.command"）从嵌套字典里取值，找不到返回 nil。
    public static func value(at path: String, in dict: [String: Any]) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        var cursor: Any = dict
        for part in parts {
            guard let map = cursor as? [String: Any], let next = map[part] else { return nil }
            cursor = next
        }
        return cursor
    }
}

import Foundation

/// A loosely-typed JSON value, for decoding a field whose shape the SDK doesn't fix (e.g. a
/// challenge's backend-supplied `metadata`).
///
/// `Codable` has no built-in "any JSON value" type, so this exists to fill that gap.
enum JSONValue: Decodable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}

extension [String: JSONValue] {
    /// Presents backend context the way `Challenge.metadata` does. The backend contract
    /// guarantees every value is a string or null. A value of any other type breaks that contract
    /// and is left out, so the rest of the challenge still reaches the app.
    func flattenedToMetadata() -> [String: String?] {
        var flattened: [String: String?] = [:]
        for (key, value) in self {
            switch value {
            case .null:
                // `.some(nil)`, so the key stays, with a null value, and is not removed.
                flattened[key] = .some(nil)
            case let .string(text):
                flattened[key] = text
            case .bool, .int, .double, .array, .object:
                continue
            }
        }
        return flattened
    }
}

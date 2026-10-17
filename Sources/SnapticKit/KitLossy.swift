import Foundation

/// A coding key built from any string, for dictionaries keyed by our own types.
package struct AnyCodingKey: CodingKey {
    package var stringValue: String
    package var intValue: Int? { nil }

    package init(_ string: String) { stringValue = string }
    package init?(stringValue: String) { self.stringValue = stringValue }
    package init?(intValue: Int) { return nil }
}

/// A string-keyed map that decodes entry by entry. Unknown keys (from a newer
/// or older version of Snaptic) are kept and written back unchanged; entries
/// whose value can't be decoded are dropped individually instead of wiping the
/// whole map.
package struct LossyMap<Key: Hashable & RawRepresentable, Value: Codable & Equatable>: Codable, Equatable
where Key.RawValue == String {
    package var values: [Key: Value]
    private var unknown: [String: Value]

    package static var maxEntries: Int { 256 }

    package init(_ values: [Key: Value] = [:]) {
        self.values = values
        self.unknown = [:]
    }

    package subscript(key: Key) -> Value? {
        get { values[key] }
        set { values[key] = newValue }
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var known: [Key: Value] = [:]
        var other: [String: Value] = [:]
        for codingKey in container.allKeys.prefix(Self.maxEntries) {
            guard let value = try? container.decode(Value.self, forKey: codingKey) else { continue }
            if let key = Key(rawValue: codingKey.stringValue) {
                known[key] = value
            } else {
                other[codingKey.stringValue] = value
            }
        }
        values = known
        unknown = other
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknown where Key(rawValue: key) == nil {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        for (key, value) in values {
            try container.encode(value, forKey: AnyCodingKey(key.rawValue))
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes a field, falling back to a default when it is missing or invalid.
    package func lossy<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}

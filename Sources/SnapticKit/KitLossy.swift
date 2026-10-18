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

    /// Drops entries with unknown keys beyond `n` (sanitizers use this to bound growth).
    package mutating func dropUnknown(keepingAtMost n: Int) {
        guard unknown.count > n else { return }
        let keep = unknown.keys.sorted().prefix(max(0, n))
        unknown = unknown.filter { keep.contains($0.key) }
    }

    package subscript(key: Key) -> Value? {
        get { values[key] }
        set { values[key] = newValue }
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var known: [Key: Value] = [:]
        var other: [String: Value] = [:]
        let sortedKeys = container.allKeys.sorted { $0.stringValue < $1.stringValue }
        for codingKey in sortedKeys.prefix(Self.maxEntries) {
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

extension LossyMap: Sendable where Key: Sendable, Value: Sendable {}

/// An array decoded element by element (mirrors LossyMap; 0.3 N18, R5-3): a bad element is skipped and the rest
/// kept; encodes every element. At most `maxElements` elements are read. Moved here from ConfigAutomation.swift
/// (same name, same `items`).
package struct LossyArray<Element: Codable & Equatable>: Codable, Equatable {
    package var items: [Element]

    package static var maxElements: Int { 1_024 }

    package init(_ items: [Element] = []) { self.items = items }

    /// Always decodes, whatever the element holds, so the container moves on (`nil` = a bad element).
    private struct Attempt: Decodable {
        let value: Element?
        init(from decoder: Decoder) throws { value = try? Element(from: decoder) }
    }

    package init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        var read = 0
        while !container.isAtEnd && read < Self.maxElements {
            read += 1
            guard let attempt = try? container.decode(Attempt.self) else { break }
            if let value = attempt.value { result.append(value) }
        }
        items = result
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for item in items { try container.encode(item) }
    }
}

extension LossyArray: Sendable where Element: Sendable {}

extension Array where Element: Identifiable {
    /// First element per id wins, order kept; never traps on duplicate ids (R5-3, security L3).
    package func uniquedByID() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}

extension Array where Element: Hashable {
    /// First occurrence wins, order kept.
    package func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension KeyedDecodingContainer {
    /// `c.lossyArray(.presets, default)`: a missing or non-array value gives the fallback; an array decodes element by
    /// element (never all-or-nothing).
    package func lossyArray<T: Codable & Equatable>(_ key: Key, _ fallback: @autoclosure () -> [T]) -> [T] {
        guard let decoded = (try? decodeIfPresent(LossyArray<T>.self, forKey: key)) ?? nil else { return fallback() }
        return decoded.items
    }

    /// lossyArray, then uniquedByID: duplicate ids are dropped on decode (the first is kept).
    package func lossyUniqueArray<T: Codable & Equatable & Identifiable>(_ key: Key,
                                                                         _ fallback: @autoclosure () -> [T]) -> [T] {
        lossyArray(key, fallback()).uniquedByID()
    }
}

/// When a ConfigStore writes (FIXES-R2 W1): a pending change always; `force` also when
/// nothing was ever written, so a value equal to the defaults still lands on disk.
package enum ConfigSavePolicy {
    package static func shouldWrite(hasPendingChange: Bool, force: Bool, everWritten: Bool) -> Bool {
        hasPendingChange || (force && !everWritten)
    }
}

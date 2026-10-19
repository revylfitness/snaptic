import SwiftUI
import SnapticKit

/// The binding helpers the 0.2 pages each wrote (ManagementBindings and friends) collapse here (§4.5). Every setter
/// writes only when the value changes, and never calls `sanitized()`: the store sanitizes on load and on outside
/// changes, and the controls already clamp.
@MainActor enum SettingsBinding {
    /// A config field.
    static func store<T: ConfigModel, V: Equatable>(_ store: ConfigStore<T>, _ path: WritableKeyPath<T, V>) -> Binding<V> {
        Binding(get: { store.value[keyPath: path] },
                set: { newValue in
                    if store.value[keyPath: path] != newValue { store.value[keyPath: path] = newValue }
                })
    }

    /// A field of one entry of a keyed config map (per display, per app); a missing entry reads as `fallback` and
    /// is created on the first write.
    static func entry<T: ConfigModel, K: Hashable, E, V: Equatable>(
        _ store: ConfigStore<T>, _ map: WritableKeyPath<T, [K: E]>, _ key: K, fallback: @escaping () -> E,
        _ path: WritableKeyPath<E, V>
    ) -> Binding<V> {
        Binding(get: { (store.value[keyPath: map][key] ?? fallback())[keyPath: path] },
                set: { newValue in
                    var entry = store.value[keyPath: map][key] ?? fallback()
                    guard entry[keyPath: path] != newValue else { return }
                    entry[keyPath: path] = newValue
                    store.value[keyPath: map][key] = entry
                })
    }

    /// The same for a `LossyMap` (unknown keys are kept).
    static func lossyEntry<T: ConfigModel, K: Hashable & RawRepresentable, E: Codable & Equatable, V: Equatable>(
        _ store: ConfigStore<T>, _ map: WritableKeyPath<T, LossyMap<K, E>>, _ key: K, fallback: @escaping () -> E,
        _ path: WritableKeyPath<E, V>
    ) -> Binding<V> where K.RawValue == String {
        Binding(get: { (store.value[keyPath: map][key] ?? fallback())[keyPath: path] },
                set: { newValue in
                    var entry = store.value[keyPath: map][key] ?? fallback()
                    guard entry[keyPath: path] != newValue else { return }
                    entry[keyPath: path] = newValue
                    store.value[keyPath: map][key] = entry
                })
    }

    /// An `Int` setting shown by a slider or field (rounded and clamped to `range`).
    static func double(_ binding: Binding<Int>, in range: ClosedRange<Int>) -> Binding<Double> {
        Binding(get: { Double(binding.wrappedValue) },
                set: { v in
                    guard v.isFinite else { return }
                    let i = Int(min(Double(range.upperBound), max(Double(range.lowerBound), v.rounded())))
                    if binding.wrappedValue != i { binding.wrappedValue = i }
                })
    }

    /// The opposite of a flag ("Adjust this display" over a stored "suspended").
    static func inverted(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { !binding.wrappedValue }, set: { binding.wrappedValue = !$0 })
    }

    /// Membership of `element` in a set (checkbox groups).
    static func member<E: Hashable>(_ element: E, of set: Binding<Set<E>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(element) },
                set: { on in
                    guard set.wrappedValue.contains(element) != on else { return }
                    if on { set.wrappedValue.insert(element) } else { set.wrappedValue.remove(element) }
                })
    }

    /// Membership of `element` in an ordered list; a new member is appended once.
    static func member<E: Equatable>(_ element: E, of list: Binding<[E]>) -> Binding<Bool> {
        Binding(get: { list.wrappedValue.contains(element) },
                set: { on in
                    guard list.wrappedValue.contains(element) != on else { return }
                    if on { list.wrappedValue.append(element) } else { list.wrappedValue.removeAll { $0 == element } }
                })
    }

    /// An optional value edited as a plain one; writing `fallback` stores nil when `nilAtFallback` is set.
    static func unwrapped<V: Equatable>(_ binding: Binding<V?>, fallback: V, nilAtFallback: Bool = false) -> Binding<V> {
        Binding(get: { binding.wrappedValue ?? fallback },
                set: { v in
                    let stored: V? = nilAtFallback && v == fallback ? nil : v
                    if binding.wrappedValue != stored { binding.wrappedValue = stored }
                })
    }
}

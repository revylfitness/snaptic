import Foundation

/// Config key paths from stored properties (owner: A; 0.3 §4.8, R5-13). Used by `--selftest-controls`, which walks the
/// app-side Switcher `Config` (Kit can't see it) and checks every path against `ControlLegacy.switcherKeyPaths` and the
/// `keys` of the Switcher control tables. Walker rules (R5-13): path segments are Swift stored-property names, not
/// CodingKeys; `LossyMap` walks only `values` and `LossyArray` only `items`; Dictionary, Array, Set and LossyArray
/// elements become `*`; Optional is unwrapped (nil contributes nothing below the property); an enum with a payload
/// contributes its case name, then the payload labels (`kind.duration.seconds`). Every prefix is listed too.
package enum KitKeyPaths {
    /// Every dotted path of `value`, prefixes included.
    package static func paths(_ value: Any) -> Set<String> {
        var out = Set<String>()
        walk(value, prefix: "", depth: 0, into: &out)
        return out
    }

    /// The paths that are no other path's prefix (the values a control edits).
    package static func leaves(_ paths: Set<String>) -> Set<String> {
        var interior = Set<String>()
        for path in paths {
            var parts = path.split(separator: ".", omittingEmptySubsequences: false)
            while parts.count > 1 {
                parts.removeLast()
                interior.insert(parts.joined(separator: "."))
            }
        }
        return paths.subtracting(interior)
    }

    /// A path is covered when it or one of its ancestors is declared, or when something below it is (an empty
    /// collection or nil optional has no element paths of its own).
    package static func isCovered(_ path: String, by declared: Set<String>) -> Bool {
        var parts = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        while !parts.isEmpty {
            if declared.contains(parts.joined(separator: ".")) { return true }
            parts.removeLast()
        }
        return declared.contains { $0.hasPrefix(path + ".") }
    }

    /// The `--selftest-controls` verdict, one line per problem (empty = pass):
    /// - every leaf of `walked` is covered by a legacy path, a declared control key or an internal key (a new key
    ///   without a control fails);
    /// - every legacy path still exists in `walked`, unless all of its legacy ids were removed with a reason.
    package static func coverageProblems(walked: Set<String>, legacy: [String: [LegacyControlID]], declared: Set<String>,
                                         internalKeys: Set<String>, removed: Set<LegacyControlID>) -> [String] {
        let known = Set(legacy.keys).union(declared).union(internalKeys)
        var problems: [String] = []
        for leaf in leaves(walked).sorted() where !isCovered(leaf, by: known) {
            problems.append("key \(leaf) has no control (declare it in a Switcher table's keys)")
        }
        for (path, ids) in legacy.sorted(by: { $0.key < $1.key }) {
            let gone = !walked.contains(path)
            let allRemoved = !ids.isEmpty && ids.allSatisfy { removed.contains($0) }
            if gone && !allRemoved {
                problems.append("legacy key \(path) no longer exists and isn't removed")
            }
        }
        return problems
    }

    /// Deep enough for every config; a cycle (classes) can't make the walk unbounded.
    private static let maxDepth = 24

    private static func walk(_ value: Any, prefix: String, depth: Int, into out: inout Set<String>) {
        guard depth < maxDepth else { return }
        let mirror = Mirror(reflecting: value)
        func join(_ name: String) -> String { prefix.isEmpty ? name : prefix + "." + name }
        switch mirror.displayStyle {
        case .optional:
            if let child = mirror.children.first { walk(child.value, prefix: prefix, depth: depth + 1, into: &out) }
        case .collection, .set:
            for child in mirror.children { walk(child.value, prefix: join("*"), depth: depth + 1, into: &out) }
        case .dictionary:
            for child in mirror.children {
                let pair = Mirror(reflecting: child.value).children.map(\.value)
                if pair.count == 2 { walk(pair[1], prefix: join("*"), depth: depth + 1, into: &out) }
            }
        case .enum:
            guard let child = mirror.children.first, let name = child.label else { return }
            let path = join(name)
            out.insert(path)
            walk(child.value, prefix: path, depth: depth + 1, into: &out)
        case .tuple:
            for child in mirror.children {
                guard let label = child.label, !label.hasPrefix(".") else {
                    walk(child.value, prefix: prefix, depth: depth + 1, into: &out)
                    continue
                }
                let path = join(label)
                out.insert(path)
                walk(child.value, prefix: path, depth: depth + 1, into: &out)
            }
        case .struct, .class:
            let typeName = String(describing: mirror.subjectType)
            if typeName.hasPrefix("LossyMap<") {
                if let values = mirror.children.first(where: { $0.label == "values" }) {
                    walk(values.value, prefix: prefix, depth: depth + 1, into: &out)
                }
                return
            }
            if typeName.hasPrefix("LossyArray<") {
                if let items = mirror.children.first(where: { $0.label == "items" }) {
                    walk(items.value, prefix: prefix, depth: depth + 1, into: &out)
                }
                return
            }
            for child in mirror.children {
                guard let label = child.label else { continue }
                let path = join(label)
                out.insert(path)
                walk(child.value, prefix: path, depth: depth + 1, into: &out)
            }
        default:
            return
        }
    }
}

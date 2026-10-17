import Foundation

package enum BackupError: Error, Equatable, Sendable {
    case tooLarge
    case notJSON
    case wrongFormat
    case newerVersion(Int)
    case noSections

    package var message: String {
        switch self {
        case .tooLarge: return L("The file is larger than 1 MB.")
        case .notJSON: return L("The file isn't a Snaptic settings backup.")
        case .wrongFormat: return L("The file isn't a Snaptic settings backup.")
        case .newerVersion(let v): return L("The backup was made by a newer Snaptic (format ") + String(v) + ")."
        case .noSections: return L("The backup contains no settings.")
        }
    }
}

/// Settings backup documents (PLAN §3.4): what an export leaves out, what an import
/// ignores even if present, and how an import is merged and previewed. Works on JSON
/// so every team's settings take part without per-type code.
package enum KitBackup {
    package static let format = "app.snaptic.backup"
    package static let version = 1
    package static let maxBytes = 1_048_576

    package static let switcherSection = "switcher"
    package static let modulesSection = "modules"
    package static let displaysSection = "displays"
    package static let sections = [switcherSection, modulesSection, displaysSection]

    /// Removed from exports and from imports: hooks, actions, CLI settings, onboarding
    /// progress, and the sensitive Displays toggles.
    package static let removedPaths: [[String]] = [
        [modulesSection, "commandLine"],
        [modulesSection, "onboarding"],
        [modulesSection, "onboardingPermissions"],
        [displaysSection, "automation"],
        [displaysSection, "features", "disconnect"],
        [displaysSection, "features", "autoDisconnectBuiltin"],
        [displaysSection, "features", "dimToBlack"],
        [displaysSection, "features", "sleepPrevention"],
        [displaysSection, "features", "hooks"],
        [displaysSection, "features", "customActions"],
    ]

    /// Keys removed at any depth (case-insensitive substrings): the DisplayKey salt, DDC
    /// unlocks, "Allow without asking" flags, preset trust and anything secret. Teams name
    /// such fields with one of these words.
    package static let sensitiveKeyFragments = [
        "salt", "trust", "unlock", "allowwithoutasking", "preconfirmallow", "secret", "token",
    ]

    package static func isSensitive(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return sensitiveKeyFragments.contains { lowered.contains($0) }
    }

    // MARK: Export

    /// A backup document from each store's own JSON (keys = section names).
    package static func makeDocument(sections input: [String: Data], created: String, appVersion: String) -> Data? {
        var out: [String: Any] = [:]
        for (name, data) in input where sections.contains(name) {
            guard let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            out[name] = strip(object, section: name)
        }
        let document: [String: Any] = [
            "format": format, "version": version, "created": created, "snaptic": appVersion, "sections": out,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted]),
              data.count <= maxBytes else { return nil }
        return data
    }

    // MARK: Import

    /// Validates a document and returns each known section's JSON, already stripped of
    /// everything an export would have left out (imports never carry those fields).
    package static func parseDocument(_ data: Data) -> Result<[String: Data], BackupError> {
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failure(.notJSON) }
        guard root["format"] as? String == format else { return .failure(.wrongFormat) }
        guard let v = root["version"] as? Int else { return .failure(.wrongFormat) }
        guard v <= version else { return .failure(.newerVersion(v)) }
        guard let input = root["sections"] as? [String: Any] else { return .failure(.noSections) }
        var result: [String: Data] = [:]
        for name in sections {
            guard let section = input[name] as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: strip(section, section: name), options: [.sortedKeys])
            else { continue }
            result[name] = json
        }
        return result.isEmpty ? .failure(.noSections) : .success(result)
    }

    /// `imported` laid over `current`: objects merge key by key, anything else (numbers,
    /// strings, arrays) is replaced. Fields the import doesn't carry keep their current
    /// value, which is how stripped fields survive an import.
    package static func merge(current: Data, imported: Data) -> Data? {
        guard let base = try? JSONSerialization.jsonObject(with: current),
              let overlay = try? JSONSerialization.jsonObject(with: imported) else { return nil }
        let merged = deepMerge(base, overlay)
        guard JSONSerialization.isValidJSONObject(merged) else { return nil }
        return try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    /// Dotted paths of leaves that differ between two JSON documents, sorted, at most `limit`.
    package static func changedPaths(from old: Data, to new: Data, limit: Int = 50) -> [String] {
        guard let a = try? JSONSerialization.jsonObject(with: old),
              let b = try? JSONSerialization.jsonObject(with: new) else { return [] }
        var paths: [String] = []
        diff(a, b, path: "", into: &paths)
        return Array(paths.sorted().prefix(limit))
    }

    // MARK: JSON helpers

    package static func strip(_ object: Any, section: String) -> Any {
        var stripped = stripSensitive(object)
        for path in removedPaths where path.first == section {
            stripped = remove(Array(path.dropFirst()), from: stripped)
        }
        return stripped
    }

    private static func stripSensitive(_ object: Any) -> Any {
        if let dict = object as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in dict where !isSensitive(key) { out[key] = stripSensitive(value) }
            return out
        }
        if let array = object as? [Any] { return array.map(stripSensitive) }
        return object
    }

    private static func remove(_ path: [String], from object: Any) -> Any {
        guard let first = path.first, var dict = object as? [String: Any] else { return object }
        if path.count == 1 {
            dict[first] = nil
        } else if let child = dict[first] {
            dict[first] = remove(Array(path.dropFirst()), from: child)
        }
        return dict
    }

    private static func deepMerge(_ base: Any, _ overlay: Any) -> Any {
        guard var a = base as? [String: Any], let b = overlay as? [String: Any] else { return overlay }
        for (key, value) in b {
            a[key] = a[key].map { deepMerge($0, value) } ?? value
        }
        return a
    }

    private static func diff(_ a: Any?, _ b: Any?, path: String, into paths: inout [String]) {
        if let da = a as? [String: Any], let db = b as? [String: Any] {
            for key in Set(da.keys).union(db.keys) {
                diff(da[key], db[key], path: path.isEmpty ? key : path + "." + key, into: &paths)
            }
            return
        }
        if canonical(a) != canonical(b) { paths.append(path.isEmpty ? "(all)" : path) }
    }

    /// A leaf as canonical JSON text (wrapped in an array so fragments serialize).
    private static func canonical(_ value: Any?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

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
    /// 0.3 §3.6: Awake's settings, written from `AwakeConfig.exportable(includeTriggers:)` and read back through
    /// `importAwake(current:imported:)` (`importable(current:)` last).
    package static let awakeSection = "awake"
    package static let sections = [switcherSection, modulesSection, displaysSection, awakeSection]

    /// Sections whose backups are an allowlist (0.3 §3.6): only these paths (below the section, "*" = any one key)
    /// are written or read; everything else in the section (history, runtime state, salts, a newer Snaptic's fields)
    /// never leaves this Mac and is never taken from a file. `removedPaths` then strips inside the allowed paths.
    package static let allowedPaths: [String: [[String]]] = [
        awakeSection: [
            ["features"],
            ["sessions", "presets"],
            ["sessions", "defaultPresetID"],
            ["sessions", "defaultOptions"],
            ["sessions", "lastCustomSeconds"],
            ["sessions", "behavior"],
            ["guards"],
            ["triggers"],
            ["activity"],
            ["indicator"],
            ["shortcuts"],
        ],
    ]

    /// Keys removed at any depth inside one section (exact names). Awake: the salted router, Bluetooth and USB
    /// hashes and the salted display fingerprints of rule conditions; they are useless on another Mac and are never
    /// taken from a file (0.3 §3.6).
    package static let sectionSensitiveKeys: [String: Set<String>] = [
        awakeSection: ["hash", "uidHash", "serialHash", "record"],
    ]

    /// Removed from exports and from imports: hooks, actions, CLI settings, onboarding
    /// progress, and the sensitive Displays toggles. "*" matches any one key (a display).
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
        // Safety switches a file must never flip (FIXES-R1 A2).
        [displaysSection, "management", "autoDisconnectWithoutDDC"],
        [displaysSection, "perDisplay", "*", "management", "preventSleep"],
        [displaysSection, "perDisplay", "*", "management", "ignoreForAutoDisconnect"],
        [displaysSection, "color", "allowGammaWithCustomProfile"],
        // Awake (0.3 §2.14, §3.2, §3.6): Drive Alive (volumes, interval, "also without a session"), pointer
        // movement, the session started at launch, recent apps; Awake's command-line verbs like every CLI setting.
        [awakeSection, "drives"],
        [awakeSection, "features", "pointerNudge"],
        [awakeSection, "features", "commandLine"],
        [awakeSection, "sessions", "behavior", "startAtLaunch"],
        [awakeSection, "sessions", "recentApps"],
    ]

    /// Lists an import may only add to, never shrink: the result is current ∪ imported
    /// (current entries first), so a backup can't unprotect an app from captures.
    package static let unionPaths: [[String]] = [
        [displaysSection, "pip", "protectedBundlePrefixes"],
    ]

    /// Changes the import preview lists first and in full ("*" = any one key; a pattern
    /// matches the path and everything under it).
    package static let safetyPaths: [[String]] = [
        [modulesSection],
        [displaysSection, "features"],
        [displaysSection, "safety"],
        [displaysSection, "management"],
        [displaysSection, "perDisplay", "*", "management"],
        [displaysSection, "ddc"],
        [displaysSection, "perDisplay", "*", "ddc"],
        [displaysSection, "color"],
        [displaysSection, "perDisplay", "*", "color"],
        [displaysSection, "resolution"],
        [displaysSection, "perDisplay", "*", "resolution"],
        [displaysSection, "brightness", "dimOnLockLevel"],
        [displaysSection, "perDisplay", "*", "brightness", "minHardware"],
        [displaysSection, "layouts"],
        [displaysSection, "virtualScreens"],
        [displaysSection, "pip", "protectedBundlePrefixes"],
        // Awake (0.3 §3.2): what starts sessions or keeps the Mac awake on its own (features, rules, hotkeys), activity
        // simulation (features, default and preset options, the stop-after time), the battery and heat limits, and
        // the session rules for locking, sleeping and switching users.
        [awakeSection, "features"],
        [awakeSection, "guards"],
        [awakeSection, "activity"],
        [awakeSection, "triggers"],
        [awakeSection, "shortcuts"],
        [awakeSection, "sessions", "presets"],
        [awakeSection, "sessions", "defaultOptions"],
        [awakeSection, "sessions", "behavior"],
    ]

    /// Keys removed at any depth (case-insensitive substrings): the DisplayKey salt, DDC
    /// unlocks, every "allow…" flag ("Allow without asking", gamma with a custom profile,
    /// modes below 720p), preset trust and anything secret. Teams name such fields with one
    /// of these words.
    package static let sensitiveKeyFragments = [
        "salt", "trust", "unlock", "allow", "secret", "token",
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

    /// `imported` laid over `current`: objects merge key by key; arrays whose elements are all
    /// objects with an `id` merge element by element (FIXES-R3 8: the imported list and order,
    /// each element laid over the current one with the same id, so a layout keeps its trust);
    /// anything else (numbers, strings, other arrays) is replaced, except `unionPaths` of
    /// `section`, which only grow. Fields the import doesn't carry keep their current value,
    /// which is how stripped fields survive an import.
    package static func merge(current: Data, imported: Data, section: String? = nil) -> Data? {
        guard let base = try? JSONSerialization.jsonObject(with: current),
              let overlay = try? JSONSerialization.jsonObject(with: imported) else { return nil }
        var merged = deepMerge(base, overlay)
        if let section {
            for path in unionPaths where path.first == section {
                merged = unite(Array(path.dropFirst()), current: base, merged: merged)
            }
        }
        guard JSONSerialization.isValidJSONObject(merged) else { return nil }
        return try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    /// The preview's lines for one section: safety-related changes (all of them) and the
    /// rest (at most `limit`), each sorted, as dotted paths below the section.
    package static func previewChanges(section: String, from old: Data, to new: Data,
                                       limit: Int = 50) -> (safety: [String], other: [String]) {
        let all = changedPaths(from: old, to: new, limit: Int.max)
        let safety = all.filter { isSafetyRelated(section: section, path: $0) }
        let other = all.filter { !isSafetyRelated(section: section, path: $0) }
        return (safety, Array(other.prefix(limit)))
    }

    /// Whether a dotted path inside `section` falls under `safetyPaths`.
    package static func isSafetyRelated(section: String, path: String) -> Bool {
        // A whole section replaced: safety-related if anything in it is.
        if path == "(all)" { return safetyPaths.contains { $0.first == section } }
        let parts = [section] + path.split(separator: ".").map(String.init)
        return safetyPaths.contains { pattern in
            pattern.count <= parts.count && zip(pattern, parts).allSatisfy { $0 == "*" || $0 == $1 }
        }
    }

    /// Dotted paths of leaves that differ between two JSON documents, sorted, at most `limit`.
    package static func changedPaths(from old: Data, to new: Data, limit: Int = 50) -> [String] {
        guard let a = try? JSONSerialization.jsonObject(with: old),
              let b = try? JSONSerialization.jsonObject(with: new) else { return [] }
        var paths: [String] = []
        diff(a, b, path: "", into: &paths)
        return Array(paths.sorted().prefix(limit))
    }

    // MARK: Awake (0.3 §2.14, §3.6)

    /// The `awake` section of an export: `exportable(includeTriggers:)`, then the generic stripping (the allowlist,
    /// `removedPaths`, salted hashes). Without `includeTriggers` the section carries no `triggers` key at all, so an
    /// import of it keeps the rules already on the Mac instead of clearing them.
    package static func awakeSectionData(_ config: AwakeConfig, includeTriggers: Bool) -> Data? {
        guard let data = try? JSONEncoder().encode(config.exportable(includeTriggers: includeTriggers)),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if !includeTriggers { object["triggers"] = nil }
        let stripped = strip(object, section: awakeSection)
        guard JSONSerialization.isValidJSONObject(stripped) else { return nil }
        return try? JSONSerialization.data(withJSONObject: stripped, options: [.sortedKeys])
    }

    /// The Awake settings an import of the `awake` section results in (security L5): the section stripped again (it
    /// may come from anywhere), laid over `current` with `merge` (lists of ids element by element), decoded lossily,
    /// sanitized, and **then** `importable(current:)` as the last step, so nothing after it can bring back pointer
    /// movement, Drive Alive volumes or a looser guard. Nil when the result isn't usable.
    package static func importAwake(current: AwakeConfig, imported: Data) -> AwakeConfig? {
        guard let object = try? JSONSerialization.jsonObject(with: imported), object is [String: Any] else { return nil }
        let stripped = strip(object, section: awakeSection)
        guard JSONSerialization.isValidJSONObject(stripped),
              let overlay = try? JSONSerialization.data(withJSONObject: stripped, options: [.sortedKeys]),
              let before = try? JSONEncoder().encode(current),
              let merged = merge(current: before, imported: overlay, section: awakeSection),
              let decoded = try? JSONDecoder().decode(AwakeConfig.self, from: merged) else { return nil }
        return decoded.sanitized().importable(current: current)
    }

    // MARK: JSON helpers

    package static func strip(_ object: Any, section: String) -> Any {
        var stripped = object
        if let allowed = allowedPaths[section] { stripped = keepOnly(allowed, in: stripped) ?? [String: Any]() }
        stripped = stripSensitive(stripped, exact: sectionSensitiveKeys[section] ?? [])
        for path in removedPaths where path.first == section {
            stripped = remove(Array(path.dropFirst()), from: stripped)
        }
        return stripped
    }

    private static func stripSensitive(_ object: Any, exact: Set<String>) -> Any {
        if let dict = object as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in dict where !isSensitive(key) && !exact.contains(key) {
                out[key] = stripSensitive(value, exact: exact)
            }
            return out
        }
        if let array = object as? [Any] { return array.map { stripSensitive($0, exact: exact) } }
        return object
    }

    /// `object` reduced to the allowed paths: an empty path keeps everything below it; a key no path names is
    /// dropped; a non-object where a path goes deeper is dropped (nil).
    private static func keepOnly(_ paths: [[String]], in object: Any) -> Any? {
        if paths.contains(where: \.isEmpty) { return object }
        guard let dict = object as? [String: Any] else { return nil }
        var out: [String: Any] = [:]
        for (key, value) in dict {
            let below = paths.filter { $0.first == key || $0.first == "*" }.map { Array($0.dropFirst()) }
            guard !below.isEmpty, let kept = keepOnly(below, in: value) else { continue }
            out[key] = kept
        }
        return out
    }

    private static func remove(_ path: [String], from object: Any) -> Any {
        guard let first = path.first, var dict = object as? [String: Any] else { return object }
        if first == "*" {
            if path.count == 1 { return [String: Any]() }
            for (key, child) in dict { dict[key] = remove(Array(path.dropFirst()), from: child) }
        } else if path.count == 1 {
            dict[first] = nil
        } else if let child = dict[first] {
            dict[first] = remove(Array(path.dropFirst()), from: child)
        }
        return dict
    }

    /// At `path`, `merged` gets current's array plus the merged array's new entries.
    private static func unite(_ path: [String], current: Any?, merged: Any) -> Any {
        guard let first = path.first else {
            guard let had = current as? [Any] else { return merged }
            guard let now = merged as? [Any] else { return had }
            var seen = Set(had.compactMap { canonical($0) })
            var out = had
            for item in now {
                guard let key = canonical(item) else { continue }
                if seen.insert(key).inserted { out.append(item) }
            }
            return out
        }
        // An import that replaced the enclosing object with something else keeps the
        // current object: the list can't be dropped that way either.
        guard var dict = merged as? [String: Any] else { return current ?? merged }
        let currentChild = (current as? [String: Any])?[first]
        if let child = dict[first] {
            dict[first] = unite(Array(path.dropFirst()), current: currentChild, merged: child)
        } else if let currentChild {
            dict[first] = currentChild
        }
        return dict
    }

    private static func deepMerge(_ base: Any, _ overlay: Any) -> Any {
        if let a = base as? [Any], let b = overlay as? [Any], let merged = mergeByID(current: a, imported: b) { return merged }
        guard var a = base as? [String: Any], let b = overlay as? [String: Any] else { return overlay }
        for (key, value) in b {
            a[key] = a[key].map { deepMerge($0, value) } ?? value
        }
        return a
    }

    /// Element-wise merge of two lists of `id`-carrying objects; nil when either list holds
    /// anything else (then the import replaces the list). Elements only in `current` are
    /// dropped (the import decides the members); new ids come in as imported.
    private static func mergeByID(current: [Any], imported: [Any]) -> [Any]? {
        guard !imported.isEmpty else { return nil }
        var byID: [String: Any] = [:]
        for item in current {
            guard let o = item as? [String: Any], let id = idKey(o) else { return nil }
            if byID[id] == nil { byID[id] = o }
        }
        var out: [Any] = []
        for item in imported {
            guard let o = item as? [String: Any], let id = idKey(o) else { return nil }
            // A duplicated id uses the current element once; later copies come in as imported.
            if let old = byID.removeValue(forKey: id) { out.append(deepMerge(old, o)) } else { out.append(o) }
        }
        return out
    }

    /// An element's `id` (a string or a number) as canonical text.
    private static func idKey(_ object: [String: Any]) -> String? {
        guard let id = object["id"], !(id is [Any]), !(id is [String: Any]), !(id is NSNull) else { return nil }
        return canonical(id)
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

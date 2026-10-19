import Foundation

// Pure rules behind H's Settings pages (PLAN 0.3 §4.3, §4.7): the one-time General cards, list wording, the version
// line, the host diagnostics report and the Window Switcher page's choice gating. Tested on Linux.

/// The one-time cards at the top of General (C7, design M3; `ModulesConfig.newModuleCards`).
package enum GeneralCardRules {
    /// The module a card turns on or shows.
    package static func module(of card: NewModuleCard) -> ModuleID {
        switch card {
        case .displays: return .displays
        case .awake, .awakeMigrated: return .awake
        }
    }

    /// The cards to show now, in the stored order. "New: …" shows while its module is off; the migration notice
    /// shows once whatever the state. A module turned off by `Modules.disable.<id>` shows none of its cards.
    /// "New: Awake" yields to the migration notice when both are stored.
    package static func visible(_ cards: [NewModuleCard], enabled: Set<ModuleID>, blocked: Set<ModuleID>) -> [NewModuleCard] {
        var seen = Set<NewModuleCard>()
        return cards.filter { card in
            guard seen.insert(card).inserted, !blocked.contains(module(of: card)) else { return false }
            switch card {
            case .displays: return !enabled.contains(.displays)
            case .awake: return !enabled.contains(.awake) && !cards.contains(.awakeMigrated)
            case .awakeMigrated: return true
            }
        }
    }

    /// The config after a card was dismissed (or acted on): the card leaves the list, and the Displays card also
    /// clears the 0.2 flag that StatusMenu still reads.
    package static func dismissing(_ card: NewModuleCard, in config: ModulesConfig) -> ModulesConfig {
        var c = config
        c.newModuleCards.removeAll { $0 == card }
        if card == .displays { c.showNewDisplaysCard = false }
        return c
    }

    /// With every module off, General offers the module switches (StatusMenu opens General then).
    package static func showsModuleChooser(enabled: Set<ModuleID>, blocked: Set<ModuleID>) -> Bool {
        enabled.subtracting(blocked).isEmpty && blocked.count < ModuleID.allCases.count
    }
}

/// Wording helpers (copy rules, PLAN 0.3 §4.2: serial comma).
package enum SettingsText {
    /// "A", "A and B", "A, B, and C". Empty names are skipped.
    package static func list(_ items: [String]) -> String {
        let names = items.filter { !$0.isEmpty }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return names[0] + L(" and ") + names[1]
        default: return names.dropLast().joined(separator: ", ") + L(", and ") + names[names.count - 1]
        }
    }

    /// The Permissions page's "Needed by …" line.
    package static func neededBy(_ names: [String]) -> String {
        let text = list(names)
        return text.isEmpty ? L("Not needed by the features that are on.") : L("Needed by ") + text + "."
    }

    /// "Version 0.3.0 (45)"; the build is left out when it repeats the version or is missing.
    package static func version(short: String?, build: String?) -> String {
        let s = (short ?? "").trimmingCharacters(in: .whitespaces)
        let b = (build ?? "").trimmingCharacters(in: .whitespaces)
        let shown = s.isEmpty ? "?" : s
        return b.isEmpty || b == s ? L("Version ") + shown : L("Version ") + shown + " (" + b + ")"
    }

    /// The (i) popover text for command-line exit codes (General › Advanced).
    package static var exitCodes: String {
        [
            "0 " + L("Done."),
            "2 " + L("The command or its options weren’t understood."),
            "3 " + L("Nothing matched."),
            "4 " + L("Not allowed."),
            "5 " + L("Unavailable: Snaptic isn’t running, command-line control is off, or the feature is off."),
            "6 " + L("Cancelled or timed out."),
        ].joined(separator: "\n") + "\n\n" + L("Add --json for machine-readable output.")
    }
}

/// The host part of About › Diagnostics Report… (shown when Displays doesn't run; Displays has its own Display
/// Information page). Values are plain words; nothing identifying (no names, paths or serials).
package enum HostReport {
    package struct Module: Equatable, Sendable {
        package var title: String
        package var state: String
        package init(title: String, state: String) {
            self.title = title
            self.state = state
        }
    }

    /// `awake`: `AwakeModule.diagnosticsLines()` while Awake is enabled (already free of names and identifiers),
    /// nil otherwise; it becomes an "Awake" section.
    package static func sections(version: String, system: String, safeMode: Bool, modules: [Module],
                                 granted: Set<Permission>, commandLine: String,
                                 awake: [String]? = nil) -> [DiagnosticsSection] {
        var result = [
            DiagnosticsSection(title: L("Snaptic"), rows: [
                DiagnosticsRow(L("Version"), version),
                DiagnosticsRow(L("macOS"), system),
                DiagnosticsRow(L("Safe Mode"), safeMode ? L("On") : L("Off")),
                DiagnosticsRow(L("Command-line control"), commandLine),
            ]),
            DiagnosticsSection(title: L("Modules"), rows: modules.map { DiagnosticsRow($0.title, $0.state) }),
            DiagnosticsSection(title: L("Permissions"), rows: Permission.allCases.map {
                DiagnosticsRow(permissionName($0), granted.contains($0) ? L("Allowed") : L("Not allowed"))
            }),
        ]
        if let awake { result.append(DiagnosticsSection(title: L("Awake"), rows: awake.compactMap(row))) }
        return result
    }

    /// "Label: value" lines keep their label; other lines become a "Note"; blank lines are dropped.
    package static func row(_ line: String) -> DiagnosticsRow? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let range = text.range(of: ": "), range.lowerBound != text.startIndex {
            let value = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return DiagnosticsRow(String(text[..<range.lowerBound]), value)
        }
        return DiagnosticsRow(L("Note"), text)
    }

    package static func permissionName(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: return L("Accessibility")
        case .screenRecording: return L("Screen Recording")
        }
    }
}

/// Choices on the Window Switcher page and its sheets (§4.3): the stored value reads as what the switcher actually
/// does. The per-shortcut "Windows from" and "Include apps with no open windows" are the only controls for other
/// Spaces and windowless apps: choosing one turns its feature on (review ux M3; no separate feature switch).
package enum SwitcherPageRules {
    /// The three "Windows from" choices, in order (raw values of the app's `SpacesFilter`).
    package static let spaces = ["all", "current", "others"]
    /// The three styles (raw values of the app's `SwitcherStyle`).
    package static let styles = ["thumbnails", "icons", "titles"]

    package static func effectiveSpace(_ raw: String, otherSpacesOn: Bool) -> String {
        otherSpacesOn ? raw : "current"
    }

    /// Choosing All Spaces or Other Spaces turns the other-Spaces feature on; Current Space leaves it as it is.
    package static func spaceChoiceTurnsOnOtherSpaces(_ raw: String) -> Bool {
        spaces.contains(raw) && raw != "current"
    }

    /// The per-shortcut windowless switch reads on only while the feature is on too.
    package static func effectiveWindowless(_ stored: Bool, featureOn: Bool) -> Bool {
        stored && featureOn
    }

    /// Turning the per-shortcut switch on turns the feature on; turning it off leaves the feature alone (other
    /// shortcuts may use it).
    package static func windowlessChoiceTurnsOnFeature(_ on: Bool) -> Bool { on }

    /// Choosing "Windows from" `raw` for the shortcut at `changed` (review round 2 ui F2, parity Q1): the stored values
    /// to write for every shortcut, and whether the other-Spaces feature turns on. When the choice turns the feature
    /// on, every other shortcut gets the value it showed until now (Current Space) written explicitly, so its stored
    /// All/Other Spaces doesn't silently take effect. When the feature is already on (or stays off), only the chosen
    /// shortcut changes.
    package static func spacesChoice(_ stored: [String], changed: Int, to raw: String,
                                      otherSpacesOn: Bool) -> (spaces: [String], turnsOn: Bool) {
        guard stored.indices.contains(changed) else { return (stored, false) }
        let turnsOn = !otherSpacesOn && spaceChoiceTurnsOnOtherSpaces(raw)
        var out = stored
        if turnsOn {
            for i in out.indices where i != changed {
                out[i] = effectiveSpace(stored[i], otherSpacesOn: otherSpacesOn)
            }
        }
        out[changed] = raw
        return (out, turnsOn)
    }

    /// Turning "Include apps with no open windows" on or off for the shortcut at `changed`: the stored values to
    /// write and whether the windowless feature turns on. When it turns on, every other shortcut keeps reading as it
    /// did (off: its stored "on" was masked by the feature) by writing that value explicitly.
    package static func windowlessChoice(_ stored: [Bool], changed: Int, to on: Bool,
                                         featureOn: Bool) -> (values: [Bool], turnsOn: Bool) {
        guard stored.indices.contains(changed) else { return (stored, false) }
        let turnsOn = !featureOn && windowlessChoiceTurnsOnFeature(on)
        var out = stored
        if turnsOn {
            for i in out.indices where i != changed {
                out[i] = effectiveWindowless(stored[i], featureOn: featureOn)
            }
        }
        out[changed] = on
        return (out, turnsOn)
    }

    /// With window thumbnails off, a Thumbnails shortcut shows icons.
    package static func styleChoiceEnabled(_ raw: String, thumbnailsOn: Bool) -> Bool {
        thumbnailsOn || raw != "thumbnails"
    }

    package static func effectiveStyle(_ raw: String, thumbnailsOn: Bool) -> String {
        !thumbnailsOn && raw == "thumbnails" ? "icons" : raw
    }

    /// The subordinate rows under Style = Thumbnails.
    package static func showsThumbnailOptions(style raw: String, thumbnailsOn: Bool) -> Bool {
        effectiveStyle(raw, thumbnailsOn: thumbnailsOn) == "thumbnails"
    }
}

/// The one wording for anything turned off by a `defaults write` kill switch (`Modules.disable.<id>`,
/// `Displays.disable.<feature>`, `Awake.disable.<feature>`; review ux m9): who did it in user words, and the exact
/// command that undoes it. Shown by `DefaultsLockRow` (pages), `ModuleSwitchRow` and the diagnostics report.
package enum DefaultsLock {
    /// The status line, everywhere a kill switch is the reason.
    package static var text: String { L("Turned off for this Mac by an administrator or a Terminal command.") }

    /// The same as a value in a list or report ("Window Switcher: …"), naming the key.
    package static func state(key: String) -> String {
        L("Turned off by an administrator or a Terminal command (\(key))")
    }

    /// The Terminal command that removes the kill switch.
    package static func command(domain: String, key: String) -> String {
        "defaults delete \(quoted(domain)) \(quoted(key))"
    }

    /// The (i) popover text: what turns it back on.
    package static func details(domain: String, key: String) -> String {
        L("To turn it back on, run this command in Terminal, then quit and open Snaptic again:")
            + "\n\n" + command(domain: domain, key: key) + "\n\n"
            + L("If your organization manages this Mac, ask its administrator instead.")
    }

    /// Plain identifiers stay as they are; anything else is single-quoted for the shell.
    private static func quoted(_ s: String) -> String {
        let plain = !s.isEmpty && s.unicodeScalars.allSatisfy {
            ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x41 && $0.value <= 0x5A)
                || ($0.value >= 0x61 && $0.value <= 0x7A) || $0 == "." || $0 == "_" || $0 == "-"
        }
        return plain ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

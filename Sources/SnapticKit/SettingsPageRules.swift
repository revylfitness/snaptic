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
            "2 " + L("The command or its options weren't understood."),
            "3 " + L("Nothing matched."),
            "4 " + L("Not allowed."),
            "5 " + L("Unavailable: Snaptic isn't running, command-line control is off, or the feature is off."),
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

    package static func sections(version: String, system: String, safeMode: Bool, modules: [Module],
                                 granted: Set<Permission>, commandLine: String) -> [DiagnosticsSection] {
        [
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
    }

    package static func permissionName(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: return L("Accessibility")
        case .screenRecording: return L("Screen Recording")
        }
    }
}

/// Choice gating on the Window Switcher page (§4.3): a choice that needs a feature that's off is shown but can't be
/// chosen, and the stored value reads as what the switcher actually does.
package enum SwitcherPageRules {
    /// The three "Windows from" choices, in order (raw values of the app's `SpacesFilter`).
    package static let spaces = ["all", "current", "others"]
    /// The three styles (raw values of the app's `SwitcherStyle`).
    package static let styles = ["thumbnails", "icons", "titles"]

    /// With "Windows on other Spaces" off, only the current Space can be listed.
    package static func spaceChoiceEnabled(_ raw: String, otherSpacesOn: Bool) -> Bool {
        otherSpacesOn || raw == "current"
    }

    package static func effectiveSpace(_ raw: String, otherSpacesOn: Bool) -> String {
        otherSpacesOn ? raw : "current"
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

    /// Writing a choice the user can't make keeps the stored value (the control was disabled).
    package static func write(_ chosen: String, current: String, enabled: Bool) -> String {
        enabled ? chosen : current
    }
}

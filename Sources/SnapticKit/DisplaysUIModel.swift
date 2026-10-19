import Foundation

// Pure logic behind the Displays UI shell (owner: F): feature names, the
// onboarding chips (PLAN §3.7, R5.8), the display icon choices, the EDID view's text,
// MCCS input names and the diagnostics report text with masked identifiers (PLAN §12).

// MARK: - Names

package enum DisplaysUIText {
    /// A feature's name in user words, as the 0.3 pages label its switch (PLAN 0.3 §4.2 copy rules and Apple terms;
    /// never "monitor", "DDC", "OSD", "HiDPI" or "on/off"). Shown in "Also turned on: …", "This also turns off …",
    /// "Needs …", "Skipped while … is off.", onboarding's summary and Display Information's Unavailable list.
    package static func title(_ feature: DisplayFeature) -> String {
        switch feature {
        case .overview: return L("Displays panel and names")
        case .diagnostics: return L("Display Information")
        case .resolution: return L("Resolution control")
        case .hiddenModes: return L("Show all resolutions")
        case .scaleMatch: return L("Match text size")
        case .brightness: return L("Brightness control")
        case .brightnessApple: return L("Apple native brightness")
        case .brightnessDDC: return L("Hardware brightness")
        case .brightnessGamma: return L("Color table dimming")
        case .brightnessOverlay: return L("Overlay dimming")
        case .brightnessRestore: return L("Restore brightness")
        case .dimToBlack: return L("Dim all the way to black")
        case .dimOnLock: return L("Dim when the screen locks")
        case .nits: return L("Show brightness in nits")
        case .xdr: return L("Extra brightness")
        case .sync: return L("Sync brightness")
        case .autoBrightness: return L("Automatically adjust brightness")
        case .color: return L("Color adjustments")
        case .colorProfiles: return L("Color profiles")
        case .nightShift: return L("Night Shift controls")
        case .applePresets: return L("Apple display presets")
        case .ddcControls: return L("Hardware controls")
        case .ddcInput: return L("Input switching")
        case .ddcPower: return L("Turn displays off and on")
        case .ddcCustom: return L("Custom hardware controls")
        case .brightnessKeys: return L("Brightness keys")
        case .volumeKeys: return L("Volume keys")
        case .shortcuts: return L("Keyboard shortcuts")
        case .osd: return L("Brightness indicator")
        case .osdBroadcast: return L("Brightness broadcast")
        case .mainDisplay: return L("Main display")
        case .arrangement: return L("Arrangement")
        case .mirroring: return L("Mirroring")
        case .rotation: return L("Rotation")
        case .underscan: return L("Underscan")
        case .hdrToggle: return L("High Dynamic Range")
        case .disconnect: return L("Disconnect displays")
        case .autoDisconnectBuiltin: return L("Turn off the built-in display automatically")
        case .protection: return L("Protect the current arrangement")
        case .layouts: return L("Saved layouts")
        case .virtualScreens: return L("Virtual displays")
        case .smartHiDPI: return L("Sharper text")
        case .hdrVirtual: return L("HDR virtual modes")
        case .pip: return L("Picture in Picture")
        case .pipFilters: return L("Picture in Picture filters")
        case .menuBarOverlays: return L("Menu bar overlays")
        case .hooks: return L("Event hooks")
        case .customActions: return L("Custom actions")
        }
    }

    /// The feature's name inside running text ("Needs saved layouts.", "Turn off virtual displays?").
    package static func inSentence(_ feature: DisplayFeature) -> String { SentenceText.inSentence(title(feature)) }

    /// Names joined for a sentence, each lowercased as `inSentence` does: "sharper text and HDR virtual modes".
    package static func list(_ features: [DisplayFeature]) -> String { SentenceText.list(features.map(inSentence)) }

    /// Whether the feature's name takes a plural verb ("Keyboard shortcuts are off.").
    package static func isPlural(_ feature: DisplayFeature) -> Bool {
        switch feature {
        case .overview, .color, .colorProfiles, .nightShift, .applePresets, .ddcControls, .ddcCustom, .brightnessKeys,
             .volumeKeys, .shortcuts, .layouts, .virtualScreens, .hdrVirtual, .pipFilters, .menuBarOverlays, .hooks,
             .customActions:
            return true
        case .diagnostics, .resolution, .hiddenModes, .scaleMatch, .brightness, .brightnessApple, .brightnessDDC,
             .brightnessGamma, .brightnessOverlay, .brightnessRestore, .dimToBlack, .dimOnLock, .nits, .xdr, .sync,
             .autoBrightness, .ddcInput, .ddcPower, .osd, .osdBroadcast, .mainDisplay, .arrangement, .mirroring,
             .rotation, .underscan, .hdrToggle, .disconnect, .autoDisconnectBuiltin, .protection, .smartHiDPI, .pip:
            return false
        }
    }

    /// "Keyboard shortcuts are off." / "Brightness control is off."
    package static func isOff(_ feature: DisplayFeature) -> String {
        isPlural(feature) ? L("\(title(feature)) are off.") : L("\(title(feature)) is off.")
    }

    /// "Hardware controls aren’t available right now." / "Brightness control isn’t available right now."
    package static func notAvailableNow(_ feature: DisplayFeature) -> String {
        isPlural(feature) ? L("\(title(feature)) aren’t available right now.")
            : L("\(title(feature)) isn’t available right now.")
    }

    /// "Skipped while saved layouts are off."
    package static func skippedWhileOff(_ feature: DisplayFeature) -> String {
        isPlural(feature) ? L("Skipped while \(inSentence(feature)) are off.")
            : L("Skipped while \(inSentence(feature)) is off.")
    }

    /// "Needs hardware controls."
    package static func needs(_ feature: DisplayFeature) -> String { L("Needs \(inSentence(feature)).") }

    /// The permission's name as System Settings shows it on this macOS version
    /// (macOS 27 renamed the Accessibility pane, macos27.md §1a).
    package static func permissionName(_ permission: Permission, osMajor: Int) -> String {
        switch permission {
        case .accessibility: return osMajor >= 27 ? L("Device Control and Data Access") : L("Accessibility")
        case .screenRecording: return L("Screen & System Audio Recording")
        }
    }

    /// MCCS input source names (VCP 0x60 values).
    package static func inputName(_ code: UInt16) -> String {
        switch code & 0xFF {
        case 0x01: return L("VGA 1")
        case 0x02: return L("VGA 2")
        case 0x03: return L("DVI 1")
        case 0x04: return L("DVI 2")
        case 0x05: return L("Composite 1")
        case 0x06: return L("Composite 2")
        case 0x07: return L("S-Video 1")
        case 0x08: return L("S-Video 2")
        case 0x09: return L("Tuner 1")
        case 0x0A: return L("Tuner 2")
        case 0x0B: return L("Tuner 3")
        case 0x0C: return L("Component 1")
        case 0x0D: return L("Component 2")
        case 0x0E: return L("Component 3")
        case 0x0F: return L("DisplayPort 1")
        case 0x10: return L("DisplayPort 2")
        case 0x11: return L("HDMI 1")
        case 0x12: return L("HDMI 2")
        case 0x1B: return L("USB-C")
        default: return String(format: L("Input 0x%02X"), Int(code & 0xFF))
        }
    }

    /// Inputs offered when the monitor's capabilities don't list any.
    package static let commonInputs: [UInt16] = [0x0F, 0x10, 0x11, 0x12, 0x1B]

    /// "1920 × 1080 HiDPI, 60 Hz".
    package static func modeLabel(_ mode: ModeRef) -> String {
        var s = "\(mode.pointWidth) × \(mode.pointHeight)"
        if mode.isHiDPI { s += " " + L("HiDPI") }
        if mode.refreshMilliHz > 0 { s += ", " + refreshLabel(mode.refreshMilliHz) }
        return s
    }

    /// "60 Hz", "59.94 Hz".
    package static func refreshLabel(_ milliHz: Int) -> String {
        let whole = milliHz / 1000
        let frac = milliHz % 1000
        if frac == 0 { return "\(whole) Hz" }
        let hundredths = (frac + 5) / 10
        if hundredths >= 100 { return "\(whole + 1) Hz" }
        return hundredths % 10 == 0 ? "\(whole).\(hundredths / 10) Hz" : String(format: "%d.%02d Hz", whole, hundredths)
    }

    /// Diagonal in inches from the physical size in millimetres; nil when unknown.
    package static func diagonalInches(widthMM: Double, heightMM: Double) -> Double? {
        guard widthMM > 0, heightMM > 0, widthMM.isFinite, heightMM.isFinite else { return nil }
        return (widthMM * widthMM + heightMM * heightMM).squareRoot() / 25.4
    }

    /// The curated icons offered on the Display Names page (SF Symbols that exist on
    /// macOS 14). Each passes PerDisplayIdentity's symbol rule.
    package static let displaySymbols: [DisplaySymbolChoice] = [
        DisplaySymbolChoice("display", L("Display")),
        DisplaySymbolChoice("display.2", L("Two displays")),
        DisplaySymbolChoice("laptopcomputer", L("Laptop")),
        DisplaySymbolChoice("desktopcomputer", L("Desktop computer")),
        DisplaySymbolChoice("pc", L("PC")),
        DisplaySymbolChoice("tv", L("TV")),
        DisplaySymbolChoice("4k.tv", L("4K TV")),
        DisplaySymbolChoice("play.tv", L("Media TV")),
        DisplaySymbolChoice("ipad.landscape", L("iPad")),
        DisplaySymbolChoice("airplayvideo", L("AirPlay")),
        DisplaySymbolChoice("rectangle.dashed", L("Virtual")),
        DisplaySymbolChoice("macwindow", L("Window")),
        DisplaySymbolChoice("gamecontroller", L("Games")),
        DisplaySymbolChoice("paintpalette", L("Design")),
        DisplaySymbolChoice("film", L("Video")),
        DisplaySymbolChoice("chevron.left.forwardslash.chevron.right", L("Code")),
        DisplaySymbolChoice("star", L("Favorite")),
    ]

    /// True when `symbol` is one of the curated icons.
    package static func isCuratedSymbol(_ symbol: String?) -> Bool {
        guard let symbol else { return false }
        return displaySymbols.contains { $0.symbol == symbol }
    }
}

/// One icon offered for a display (an SF Symbol name and what it shows).
package struct DisplaySymbolChoice: Equatable, Hashable, Sendable {
    package let symbol: String
    package let title: String
    package init(_ symbol: String, _ title: String) {
        self.symbol = symbol
        self.title = title
    }
}

// MARK: - Mode checks (onboarding)

package enum DisplayModeChoices {
    /// True when a HiDPI mode looks at least ~55% as wide as the panel's pixels, i.e. text
    /// can be sharp at a usable size without `smartHiDPI` (onboarding's "Sharper text").
    package static func hasHiDPINearNative(_ modes: [ModeRef], nativePixelWidth: Int) -> Bool {
        guard nativePixelWidth > 0 else { return true }
        return modes.contains { $0.isHiDPI && Double($0.pointWidth) >= 0.55 * Double(nativePixelWidth) }
    }
}

// MARK: - Onboarding chips (PLAN §3.7, R5.8)

package enum OnboardingChip: String, Codable, CaseIterable, Sendable {
    case basics, keys, sharperText, virtualScreens, pip, extraBrightness, more
}

package enum DisplaysOnboardingPlan {
    private static let brightnessFlags: [DisplayFeature] = [
        .brightness, .brightnessApple, .brightnessDDC, .brightnessGamma, .brightnessOverlay, .brightnessRestore,
    ]
    private static let basicsFlags: [DisplayFeature] = brightnessFlags + [
        .resolution, .ddcControls, .osd, .shortcuts, .mainDisplay, .arrangement, .mirroring,
    ]

    /// Preselected chips.
    package static let defaultChips: Set<OnboardingChip> = [.basics]

    package static func title(_ chip: OnboardingChip) -> String {
        switch chip {
        case .basics: return L("Basics")
        case .keys: return L("Brightness and volume keys")
        case .sharperText: return L("Sharper text")
        case .virtualScreens: return L("Virtual displays")
        case .pip: return L("Picture in Picture")
        case .extraBrightness: return L("Extra brightness")
        case .more: return L("More")
        }
    }

    package static func summary(_ chip: OnboardingChip) -> String {
        switch chip {
        case .basics: return L("Brightness, resolution, hardware controls, arrangement, and the brightness indicator.")
        case .keys: return L("Use the keyboard’s brightness and volume keys with external displays.")
        case .sharperText: return L("Resolution control, and sharper text on displays that have no sharp mode.")
        case .virtualScreens: return L("Displays that exist only in software. Beta.")
        case .pip: return L("A display or window in a floating window. Needs Screen Recording.")
        case .extraBrightness: return L("Brighter than SDR on XDR and HDR displays. Beta.")
        case .more: return L("Basics plus color, brightness in nits, saved layouts, and menu bar overlays. No Beta features.")
        }
    }

    /// The flags a chip asks for, before graph closure.
    package static func flags(_ chip: OnboardingChip) -> [DisplayFeature] {
        switch chip {
        case .basics: return basicsFlags
        case .keys: return brightnessFlags + [.brightnessKeys, .volumeKeys, .ddcControls, .osd]
        case .sharperText: return [.resolution]
        case .virtualScreens: return [.virtualScreens]
        case .pip: return [.pip]
        case .extraBrightness: return [.xdr, .brightnessKeys]
        case .more: return basicsFlags + [.color, .nits, .layouts, .menuBarOverlays]
        }
    }

    /// The note under "Turn on Sharper Text (Beta)" for the displays that have no sharp mode (singular or plural).
    package static func sharperTextNote(_ names: [String]) -> String {
        if names.count == 1, let name = names.first {
            return L("\(name) has no sharp mode at a usable size. Sharper text draws at twice the resolution and scales down. It turns off HDR on that display and uses more graphics memory.")
        }
        return L("\(SentenceText.list(names)) have no sharp mode at a usable size. Sharper text draws at twice the resolution and scales down. It turns off HDR on those displays and uses more graphics memory.")
    }

    /// "Extra brightness" is only offered when some display has EDR headroom.
    package static func isOffered(_ chip: OnboardingChip, maxEDRPotential: Double) -> Bool {
        chip != .extraBrightness || maxEDRPotential > 1
    }

    /// The raw feature choices for a selection: every user-switchable feature is written,
    /// on if it is in the union of the chosen chips (plus `extra`, e.g. `smartHiDPI` from the
    /// Sharper text offer) closed over the graph, off otherwise.
    package static func raw(chips: Set<OnboardingChip>, extra: Set<DisplayFeature> = [], maxEDRPotential: Double,
                            available: Set<DisplayFeature>) -> [DisplayFeature: Bool] {
        var result: [DisplayFeature: Bool] = [:]
        for feature in DisplayFeature.allCases where FeatureGraph.spec(feature).defaultState != .always {
            result[feature] = false
        }
        var wanted: [DisplayFeature] = []
        for chip in OnboardingChip.allCases where chips.contains(chip) && isOffered(chip, maxEDRPotential: maxEDRPotential) {
            wanted += flags(chip)
        }
        wanted += DisplayFeature.allCases.filter { extra.contains($0) }
        for feature in wanted where FeatureGraph.spec(feature).defaultState != .always {
            result = FeatureGraph.enabling(feature, raw: result, available: available)
        }
        return result
    }

    /// Features that a raw map turns on, in declaration order.
    package static func turnedOn(_ raw: [DisplayFeature: Bool]) -> [DisplayFeature] {
        DisplayFeature.allCases.filter { raw[$0] == true }
    }

    /// Permissions needed afterwards, only for what was chosen.
    package static func permissions(_ raw: [DisplayFeature: Bool]) -> Set<Permission> {
        turnedOn(raw).reduce(into: Set<Permission>()) { $0.formUnion(FeatureGraph.permissions($1)) }
    }
}

// MARK: - Turning a feature off (FIXES-R2 W7)

package enum FeatureTurnOff {
    /// What "Also turns off: …" lists: features that stop with `feature`, whether they run
    /// now or are only switched on (paused, waiting for a permission). Never Always-on
    /// features, never `feature` itself; declaration order.
    package static func dependents(of feature: DisplayFeature, raw: [DisplayFeature: Bool],
                                   effective: Set<DisplayFeature>) -> [DisplayFeature] {
        let rawOn = Set(DisplayFeature.allCases.filter { FeatureGraph.rawState($0, in: raw) })
        let stopping = FeatureGraph.dependents(of: feature, effective: effective)
            .union(FeatureGraph.dependents(of: feature, effective: rawOn))
        return DisplayFeature.allCases.filter {
            $0 != feature && stopping.contains($0) && FeatureGraph.spec($0).defaultState != .always
        }
    }

    /// The raw flags to write: the feature and every listed dependent off, so turning the
    /// feature on again later doesn't silently bring the dependents back.
    package static func changes(_ feature: DisplayFeature, dependents: [DisplayFeature]) -> [DisplayFeature: Bool] {
        var result: [DisplayFeature: Bool] = [:]
        for f in [feature] + dependents where FeatureGraph.spec(f).defaultState != .always { result[f] = false }
        return result
    }
}

// MARK: - Display block disclosure in the menu (FIXES-R2 W17a)

/// The header row is a label (name and badges) that never acts when clicked; collapsing
/// and expanding go through a dedicated "Collapse/Expand in Menu" item in its submenu.
package enum DisplayBlockDisclosure: Equatable, Sendable {
    /// No control (the floating panel's "More options" menu, single display without header).
    case none
    /// The block is collapsed: its submenu starts with "Expand in Menu".
    case expand
    /// The block is expanded: its submenu offers "Collapse in Menu".
    case collapse

    package static func control(showHeader: Bool, forceExpanded: Bool, collapsed: Bool) -> DisplayBlockDisclosure {
        guard showHeader, !forceExpanded else { return .none }
        return collapsed ? .expand : .collapse
    }
}

// MARK: - EDID view (Display Names page only; never in the diagnostics report)

package enum EDIDText {
    /// Uppercase hex, `perLine` bytes per line, bytes separated by spaces.
    package static func hex(_ bytes: [UInt8], perLine: Int = 16) -> String {
        let width = max(1, perLine)
        var lines: [String] = []
        var index = 0
        while index < bytes.count {
            let line = bytes[index..<min(index + width, bytes.count)]
            lines.append(line.map { String(format: "%02X", Int($0)) }.joined(separator: " "))
            index += width
        }
        return lines.joined(separator: "\n")
    }

    package static func base64(_ bytes: [UInt8]) -> String { Data(bytes).base64EncodedString() }

    /// "Week 12, 2021", "2021" (week 0), "Model year 2021" (week 0xFF), nil when unknown.
    package static func manufactured(week: Int, year: Int) -> String? {
        guard year > 0 else { return nil }
        if week == 0xFF { return L("Model year \(year)") }
        if (1...54).contains(week) { return L("Week \(week), \(year)") }
        return "\(year)"
    }

    /// The decoded summary rows. The serial is masked: the page shows it, copies don't need it.
    package static func summary(_ info: EDIDInfo, byteCount: Int) -> [DiagnosticsRow] {
        var rows: [DiagnosticsRow] = []
        rows.append(DiagnosticsRow(L("Manufacturer"), info.manufacturerID.isEmpty ? L("Unknown") : info.manufacturerID))
        rows.append(DiagnosticsRow(L("Product code"), String(format: "0x%04X", Int(info.productCode))))
        if let name = info.name, !name.isEmpty { rows.append(DiagnosticsRow(L("Product name"), name)) }
        if let serial = info.serialString, !serial.isEmpty {
            rows.append(DiagnosticsRow(L("Serial number"), DiagnosticsText.mask(serial)))
        } else if info.serialNumber != 0 {
            rows.append(DiagnosticsRow(L("Serial number"), DiagnosticsText.mask(String(info.serialNumber))))
        }
        if let made = manufactured(week: info.week, year: info.year) { rows.append(DiagnosticsRow(L("Manufactured"), made)) }
        rows.append(DiagnosticsRow(L("EDID version"), "\(info.version).\(info.revision)"))
        rows.append(DiagnosticsRow(L("Input"), info.isDigital ? L("Digital") : L("Analog")))
        if info.physicalWidthMM > 0, info.physicalHeightMM > 0 {
            var size = "\(info.physicalWidthMM) × \(info.physicalHeightMM) mm"
            if let inches = DisplaysUIText.diagonalInches(widthMM: Double(info.physicalWidthMM),
                                                          heightMM: Double(info.physicalHeightMM)) {
                size += String(format: " (%.1f″)", inches)
            }
            rows.append(DiagnosticsRow(L("Image size"), size))
        }
        if let w = info.nativePixelWidth, let h = info.nativePixelHeight {
            rows.append(DiagnosticsRow(L("Preferred timing"), "\(w) × \(h)"))
        }
        if let c = info.chromaticity, c.isPlausible {
            let f = { (x: Double, y: Double) in String(format: "%.3f, %.3f", x, y) }
            rows.append(DiagnosticsRow(L("Red"), f(c.redX, c.redY)))
            rows.append(DiagnosticsRow(L("Green"), f(c.greenX, c.greenY)))
            rows.append(DiagnosticsRow(L("Blue"), f(c.blueX, c.blueY)))
            rows.append(DiagnosticsRow(L("White point"), f(c.whiteX, c.whiteY)))
        }
        rows.append(DiagnosticsRow(L("HDR static metadata"), info.hasHDRStaticMetadata ? L("Yes") : L("No")))
        rows.append(DiagnosticsRow(L("Extension blocks"), "\(info.extensionCount)"))
        rows.append(DiagnosticsRow(L("Checksums"), info.checksumValid ? L("Valid") : L("Invalid")))
        rows.append(DiagnosticsRow(L("Size"), L("\(byteCount) bytes")))
        return rows
    }

    /// A file name for "Export .bin…": the display name reduced to safe characters.
    package static func exportFileName(displayName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(String.UnicodeScalarView(displayName.unicodeScalars.filter { allowed.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "Display" : String(cleaned.prefix(48))
        return base + " EDID.bin"
    }
}

// MARK: - Diagnostics text (PLAN §12; never serials, EDID, titles or app names)

package struct DiagnosticsSection: Equatable, Sendable {
    package var title: String
    package var rows: [DiagnosticsRow]
    package init(title: String, rows: [DiagnosticsRow]) {
        self.title = title
        self.rows = rows
    }
}

package struct DiagnosticsRow: Equatable, Sendable {
    package var label: String
    package var value: String
    package init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

package enum DiagnosticsText {
    /// Row labels whose value is an identifier and is always masked.
    private static let identifierWords = ["serial", "uuid", "edid", "identifier", "displaykey", "salt", "fingerprint"]
    package static let maxValueLength = 512

    /// "••••7f": only the last two characters survive.
    package static func mask(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return "••••" }
        return "••••" + String(trimmed.suffix(2))
    }

    /// A DisplayKey shortened for reports and pages: "3fa9…".
    package static func shortKey(_ key: DisplayKey) -> String { String(key.rawValue.prefix(4)) + "…" }

    /// Masks a row: identifier rows entirely; elsewhere UUIDs and long hex runs (keys,
    /// fingerprints) are masked in place, control characters removed, length capped.
    package static func scrub(label: String, value: String) -> DiagnosticsRow {
        let cleanLabel = clean(label)
        let lower = cleanLabel.lowercased().replacingOccurrences(of: " ", with: "")
        if identifierWords.contains(where: { lower.contains($0) }) {
            return DiagnosticsRow(cleanLabel, value.isEmpty ? value : mask(value))
        }
        return DiagnosticsRow(cleanLabel, scrubText(value))
    }

    /// Masks UUIDs and runs of 16+ hex digits inside free text.
    package static func scrubText(_ text: String) -> String {
        var s = clean(text)
        for pattern in [
            "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
            "(?<![0-9A-Za-z])(?:0x)?[0-9A-Fa-f]{16,}(?![0-9A-Za-z])",
        ] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = s as NSString
            var out = ""
            var last = 0
            for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                out += mask(ns.substring(with: match.range))
                last = match.range.location + match.range.length
            }
            out += ns.substring(from: last)
            s = out
        }
        return s
    }

    private static func clean(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar -> Character in
            if scalar == "\n" || scalar == "\t" { return " " }
            if scalar.value < 0x20 || scalar.value == 0x7F { return "?" }
            return Character(scalar)
        }
        return String(String(scalars).prefix(maxValueLength))
    }

    /// Plain-text report: sections, then the event tail (already formatted lines).
    package static func report(header: String, sections: [DiagnosticsSection], events: [String]) -> String {
        var lines: [String] = [header, ""]
        for section in sections {
            lines.append("## " + clean(section.title))
            if section.rows.isEmpty { lines.append("(none)") }
            for row in section.rows { lines.append("- \(row.label): \(row.value)") }
            lines.append("")
        }
        lines.append("## " + L("Recent events") + " (\(events.count))")
        lines += events.map(scrubText)
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - 0.3 Displays root page (PLAN 0.3 §4.3; owner F)

package enum DisplaysRootText {
    /// The header's status line: "No displays", "1 display", "2 displays".
    package static func status(displayCount: Int) -> String {
        switch displayCount {
        case ..<1: return L("No displays")
        case 1: return L("1 display")
        default: return L("\(displayCount) displays")
        }
    }

    /// A navigation row's trailing value: only rows whose sub-page has a feature switch show one (consistency m14).
    package static func navigationValue(isOn: Bool?) -> String? {
        guard let isOn else { return nil }
        return isOn ? L("On") : L("Off")
    }
}

/// One switch of Displays › Advanced (the "Use Snaptic for" and Experimental groups). `features` are written
/// together; the first one is the switch's state (mixed 0.2 values stay raw until the switch is touched).
package struct DisplayFeatureSwitch: Equatable, Sendable {
    package enum Badge: Equatable, Sendable { case beta, experimental }

    /// The control id's last component ("brightness" → "displays.advanced.useFor.brightness").
    package let id: String
    package let title: String
    package let help: String
    package let features: [DisplayFeature]
    package let badge: Badge?

    package init(_ id: String, _ title: String, help: String, features: [DisplayFeature], badge: Badge? = nil) {
        self.id = id
        self.title = title
        self.help = help
        self.features = features
        self.badge = badge
    }

    /// The feature whose raw state the switch shows.
    package var shown: DisplayFeature { features[0] }

    package func isOn(raw: [DisplayFeature: Bool]) -> Bool { FeatureGraph.rawState(shown, in: raw) }

    /// True when the features it writes disagree (a 0.2 config set them separately).
    package func isMixed(raw: [DisplayFeature: Bool]) -> Bool {
        Set(features.map { FeatureGraph.rawState($0, in: raw) }).count > 1
    }
}

package enum DisplaysFeatureGroupsModel {
    /// Displays › Advanced › Use Snaptic for: feature switches without a sub-page switch of their own, in plain words.
    package static let useSnapticFor: [DisplayFeatureSwitch] = [
        DisplayFeatureSwitch("brightness", L("Brightness control"),
                             help: L("One brightness slider per display, here and in the menu."),
                             features: [.brightness]),
        DisplayFeatureSwitch("resolution", L("Resolution control"),
                             help: L("Choose resolutions and refresh rates, with favorites and undo."),
                             features: [.resolution]),
        DisplayFeatureSwitch("arrangement", L("Arrangement and mirroring"),
                             help: L("Arrange displays, choose the main display, and mirror displays."),
                             features: [.arrangement, .mainDisplay, .mirroring]),
        DisplayFeatureSwitch("rotation", L("Rotation"),
                             help: L("Rotate a display from here, the menu, or a shortcut."),
                             features: [.rotation]),
        DisplayFeatureSwitch("shortcuts", L("Keyboard shortcuts"),
                             help: L("Your own shortcuts for display actions."),
                             features: [.shortcuts]),
        DisplayFeatureSwitch("indicator", L("Brightness indicator"),
                             help: L("Shows brightness and volume changes on screen."),
                             features: [.osd]),
        DisplayFeatureSwitch("disconnect", L("Disconnect displays"),
                             help: L("Turns a display off without unplugging it."),
                             features: [.disconnect], badge: .beta),
    ]

    /// Displays › Advanced › Experimental (F lists them; their owners implement them).
    package static let experimental: [DisplayFeatureSwitch] = [
        DisplayFeatureSwitch("hdr", L("High Dynamic Range switch"),
                             help: L("Turns HDR on or off for displays that support it."),
                             features: [.hdrToggle], badge: .experimental),
        DisplayFeatureSwitch("underscan", L("Underscan"),
                             help: L("Shrinks the picture to fit TVs that cut off its edges."),
                             features: [.underscan], badge: .experimental),
        DisplayFeatureSwitch("autoBrightness", L("Built-in auto-brightness"),
                             help: L("Turns the built-in display’s automatic brightness on or off here."),
                             features: [.autoBrightness], badge: .experimental),
        DisplayFeatureSwitch("broadcast", L("Brightness broadcast"),
                             help: L("Tells other apps when Snaptic changes brightness or volume."),
                             features: [.osdBroadcast], badge: .experimental),
        DisplayFeatureSwitch("allResolutions", L("Show all resolutions"),
                             help: L("Also lists resolutions macOS hides, in the Resolution pop-up."),
                             features: [.hiddenModes], badge: .experimental),
    ]

    /// The raw flags a switch writes: every feature it covers, on or off.
    package static func changes(_ item: DisplayFeatureSwitch, on: Bool) -> [DisplayFeature: Bool] {
        var result: [DisplayFeature: Bool] = [:]
        for f in item.features where FeatureGraph.spec(f).defaultState != .always { result[f] = on }
        return result
    }
}

// MARK: - Live resolution choices (Displays root page and floating panel; PLAN 0.3 §4.3, §5.6)

/// One entry of the Resolution pop-up: a size (points and HiDPI), applied at the refresh rate closest to the
/// current one.
package struct ResolutionSizeChoice: Equatable, Hashable, Sendable {
    package var pointWidth: Int
    package var pointHeight: Int
    package var isHiDPI: Bool
    package var isDefault: Bool
    package var isNative: Bool
    package var isFavorite: Bool
    /// "Default — 1512 × 982", "1800 × 1169"; a low-resolution twin of a HiDPI size says so.
    package var title: String

    package var id: String { LiveResolution.sizeID(pointWidth: pointWidth, pointHeight: pointHeight, hiDPI: isHiDPI) }
}

/// One entry of the Refresh rate pop-up.
package struct RefreshChoice: Equatable, Hashable, Sendable {
    package var milliHz: Int
    package var title: String
}

package enum LiveResolution {
    /// Refresh rates closer than this are one choice (59.94 and 60 stay apart; rounding noise doesn't).
    package static let refreshTolerance = 10

    package static func sizeID(pointWidth: Int, pointHeight: Int, hiDPI: Bool) -> String {
        "\(pointWidth)x\(pointHeight)" + (hiDPI ? "h" : "l")
    }

    package static func sizeID(of mode: ModeRef) -> String {
        sizeID(pointWidth: mode.pointWidth, pointHeight: mode.pointHeight, hiDPI: mode.isHiDPI)
    }

    /// The Resolution pop-up: the default size first, then every other size from largest to smallest (width, then
    /// height; HiDPI before its low-resolution twin). The current size is always listed. Modes with a zero size
    /// are ignored.
    package static func sizes(_ modes: [DisplayModeDescriptor], current: ModeRef?,
                              favorites: [ModeRef] = []) -> [ResolutionSizeChoice] {
        var byID: [String: ResolutionSizeChoice] = [:]
        var order: [String] = []
        let favoriteIDs = Set(favorites.map(sizeID(of:)))
        let hiDPISizes = Set(modes.filter { $0.ref.isHiDPI }.map { "\($0.ref.pointWidth)x\($0.ref.pointHeight)" })
        var all = modes.map { ($0.ref, $0.isDefault, $0.isNative) }
        if let current, !modes.contains(where: { sizeID(of: $0.ref) == sizeID(of: current) }) {
            all.append((current, false, false))
        }
        for (ref, isDefault, isNative) in all where ref.pointWidth > 0 && ref.pointHeight > 0 {
            let id = sizeID(of: ref)
            if var existing = byID[id] {
                existing.isDefault = existing.isDefault || isDefault
                existing.isNative = existing.isNative || isNative
                byID[id] = existing
                continue
            }
            order.append(id)
            byID[id] = ResolutionSizeChoice(pointWidth: ref.pointWidth, pointHeight: ref.pointHeight, isHiDPI: ref.isHiDPI,
                                            isDefault: isDefault, isNative: isNative, isFavorite: favoriteIDs.contains(id),
                                            title: "")
        }
        var list = order.compactMap { byID[$0] }
        // One default at most: the HiDPI one wins over a low-resolution twin.
        if let firstDefault = list.firstIndex(where: { $0.isDefault && $0.isHiDPI }) ?? list.firstIndex(where: \.isDefault) {
            for i in list.indices where i != firstDefault { list[i].isDefault = false }
        }
        list.sort { a, b in
            if a.isDefault != b.isDefault { return a.isDefault }
            if a.pointWidth != b.pointWidth { return a.pointWidth > b.pointWidth }
            if a.pointHeight != b.pointHeight { return a.pointHeight > b.pointHeight }
            return a.isHiDPI && !b.isHiDPI
        }
        for i in list.indices {
            let c = list[i]
            var title = "\(c.pointWidth) × \(c.pointHeight)"
            if !c.isHiDPI && hiDPISizes.contains("\(c.pointWidth)x\(c.pointHeight)") { title += " " + L("(low resolution)") }
            if c.isDefault { title = L("Default — \(title)") }
            list[i].title = title
        }
        return list
    }

    /// The mode a size choice applies: that size at the refresh rate closest to the current one (the current mode
    /// itself when it already has that size), then the deeper color, then the lower mode id for a stable answer.
    package static func mode(forSize id: String, in modes: [DisplayModeDescriptor], current: ModeRef?) -> ModeRef? {
        if let current, sizeID(of: current) == id { return current }
        let target = current?.refreshMilliHz ?? 0
        let candidates = modes.filter { sizeID(of: $0.ref) == id }
        return candidates.min { a, b in
            let da = abs(a.ref.refreshMilliHz - target), db = abs(b.ref.refreshMilliHz - target)
            if da != db { return da < db }
            if a.bitDepth != b.bitDepth { return a.bitDepth > b.bitDepth }
            if a.ref.refreshMilliHz != b.ref.refreshMilliHz { return a.ref.refreshMilliHz > b.ref.refreshMilliHz }
            return a.ref.ioModeID < b.ref.ioModeID
        }?.ref
    }

    /// The Refresh rate pop-up for the current size: one entry per distinct rate, highest first. Empty without a
    /// current mode; the caller hides the row unless there are two or more.
    package static func refreshRates(_ modes: [DisplayModeDescriptor], current: ModeRef?) -> [RefreshChoice] {
        guard let current else { return [] }
        let id = sizeID(of: current)
        var rates: [Int] = []
        for m in modes where sizeID(of: m.ref) == id && m.ref.refreshMilliHz > 0 {
            if !rates.contains(where: { abs($0 - m.ref.refreshMilliHz) <= refreshTolerance }) { rates.append(m.ref.refreshMilliHz) }
        }
        if current.refreshMilliHz > 0, !rates.contains(where: { abs($0 - current.refreshMilliHz) <= refreshTolerance }) {
            rates.append(current.refreshMilliHz)
        }
        return rates.sorted(by: >).map { RefreshChoice(milliHz: $0, title: DisplaysUIText.refreshLabel($0)) }
    }

    /// The listed rate that stands for `milliHz` (within the tolerance), for the pop-up's selection.
    package static func choice(for milliHz: Int, in rates: [RefreshChoice]) -> Int? {
        rates.first { abs($0.milliHz - milliHz) <= refreshTolerance }?.milliHz
    }

    /// The mode with the current size at `milliHz` (deeper color first).
    package static func mode(forRefresh milliHz: Int, in modes: [DisplayModeDescriptor], current: ModeRef?) -> ModeRef? {
        guard let current else { return nil }
        if abs(current.refreshMilliHz - milliHz) <= refreshTolerance { return current }
        let id = sizeID(of: current)
        return modes.filter { sizeID(of: $0.ref) == id && abs($0.ref.refreshMilliHz - milliHz) <= refreshTolerance }
            .min { a, b in
                if a.bitDepth != b.bitDepth { return a.bitDepth > b.bitDepth }
                return a.ref.ioModeID < b.ref.ioModeID
            }?.ref
    }
}

// MARK: - Diagnostics events (PLAN 0.3 §3.6)

extension DiagnosticsText {
    /// The diagnostics report's event tail: the last `limit` entries whose category is exported (Awake's events
    /// never are), oldest first.
    package static func exportedEvents<Entry>(_ entries: [Entry], category: (Entry) -> EventCategory,
                                              limit: Int) -> [Entry] {
        guard limit > 0 else { return [] }
        return Array(entries.filter { category($0).isExportedInDiagnostics }.suffix(limit))
    }
}

// MARK: - Display Information (PLAN 0.3 §4.3 "Display Information", §3.6; owner F)

extension DiagnosticsText {
    /// What a display name becomes in a copied or exported report.
    package static let namePlaceholder = "[display name]"
    /// Names shorter than this are left alone: they would erase ordinary words.
    package static let minRedactedNameLength = 3
    /// Most names looked at: two per remembered display (`LossyMap` keeps ≤ 256) plus the connected ones.
    package static let maxRedactedNames = 1_024

    /// The names to remove from a report: trimmed, at least `minRedactedNameLength` characters, unique ignoring case,
    /// longest first (so "DELL U2720Q 2" goes before "DELL U2720Q").
    package static func redactableNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names.prefix(maxRedactedNames) {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= minRedactedNameLength, name.utf8.count <= maxValueLength else { continue }
            guard seen.insert(name.lowercased()).inserted else { continue }
            result.append(name)
        }
        return result.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
    }

    /// Replaces every whole-word occurrence of a display name (system, custom or remembered), ignoring case, with
    /// `namePlaceholder`. A name is whole when no letter or digit touches either end, so "Studio" doesn't eat
    /// "Studios".
    package static func redacting(_ text: String, names: [String]) -> String {
        let list = redactableNames(names)
        guard !list.isEmpty else { return text }
        // One pass over one alternation, longest name first, so a placeholder is never matched again.
        let alternatives = list.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:" + alternatives + ")(?![\\p{L}\\p{N}])",
                                                   options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: namePlaceholder))
    }

    /// `redacting` over every title, label and value.
    package static func redacting(_ sections: [DiagnosticsSection], names: [String]) -> [DiagnosticsSection] {
        let list = redactableNames(names)
        guard !list.isEmpty else { return sections }
        return sections.map { section in
            DiagnosticsSection(title: redacting(section.title, names: list), rows: section.rows.map {
                DiagnosticsRow(redacting($0.label, names: list), redacting($0.value, names: list))
            })
        }
    }

    /// A display's section title in the report: its number in the menu order and its kind, never its name.
    package static func displayTitle(number: Int, isBuiltin: Bool) -> String {
        isBuiltin ? "Display \(number) (built-in)" : "Display \(number)"
    }

    /// Awake's diagnostics lines (`DisplaysContext.awakeDiagnosticsLines()`) as the report's "Awake" section, or nil
    /// when Awake has nothing to say (it isn't running).
    package static func awakeSection(_ lines: [String]) -> DiagnosticsSection? {
        let rows = lines.compactMap(HostReport.row).map { scrub(label: $0.label, value: $0.value) }
        return rows.isEmpty ? nil : DiagnosticsSection(title: "Awake", rows: rows)
    }
}

extension DisplaysUIText {
    /// How a display connects, in words ("Cable", "AirPlay").
    package static func transportName(_ transport: Transport) -> String {
        switch transport {
        case .builtin: return L("Built-in")
        case .wired: return L("Cable")
        case .displayLink: return L("DisplayLink")
        case .airplay: return L("AirPlay")
        case .sidecar: return L("Sidecar")
        case .snapticVirtual: return L("Snaptic virtual display")
        case .foreignVirtual: return L("Virtual display (other app)")
        }
    }
}

/// Display Information's lists (owner F): the remembered displays and their resolutions, in a stable order.
package enum DisplayInformationText {
    /// Displays Snaptic keeps settings for that aren't connected now, by key.
    package static func remembered(stored: [DisplayKey], online: Set<DisplayKey>) -> [DisplayKey] {
        Array(Set(stored).subtracting(online)).sorted { $0.rawValue < $1.rawValue }
    }

    /// A remembered display's name: the user's, the last one seen, or its short key.
    package static func name(_ key: DisplayKey, identity: PerDisplayIdentity?) -> String {
        if let custom = identity?.customName, !custom.isEmpty { return custom }
        if let known = identity?.lastKnownName, !known.isEmpty { return known }
        return L("Display \(DiagnosticsText.shortKey(key))")
    }

    /// "1 resolution", "3 resolutions".
    package static func resolutionCount(_ count: Int) -> String {
        count == 1 ? L("1 resolution") : L("\(count) resolutions")
    }

    /// The undo journal in words.
    package static func journal(hasSessionJournal: Bool, permanentSteps: Int) -> String {
        let session = hasSessionJournal ? L("A change can be undone") : L("Empty")
        guard permanentSteps > 0 else { return session }
        return permanentSteps == 1 ? L("\(session); 1 rotation or HDR step to confirm")
                                   : L("\(session); \(permanentSteps) rotation or HDR steps to confirm")
    }
}

// MARK: - Display Details › Copy settings from (ux N3; owner F)

/// "Copy settings from" is a real copy: this display takes a remembered display's brightness, color, resolution,
/// hardware control tuning (DDC timing, custom controls, input names, unlocked codes), keys (with their audio
/// device) and connection settings, and the remembered display stays as it was. This display keeps what is its own:
/// name, icon and fingerprint, what Snaptic measured about its panel (the gamma and XDR answers, the learned DDC
/// framing), and its Picture in Picture setups (their ids name Keyboard Shortcuts actions, so they are never
/// duplicated). `movePIP` (off by default, review round 3 parity R1) also moves the remembered display's setups here,
/// as 0.2's transfer did: appended after this display's own, up to `PerDisplayPIP.maxConfigurations`, and removed
/// from the remembered display, so every id stays in one place. A moved stream that pointed at this display has no
/// target anymore (a display can't stream onto itself).
package enum DisplaySettingsCopy {
    /// The new per-display map, or nil when there is nothing to copy (no such source, the same display, or this
    /// display already has those settings and nothing moves). Every other entry is unchanged; the source's changes
    /// only when its Picture in Picture setups move.
    package static func copying(from source: DisplayKey, to target: DisplayKey,
                                in perDisplay: LossyMap<DisplayKey, PerDisplayConfig>,
                                movePIP: Bool = false) -> LossyMap<DisplayKey, PerDisplayConfig>? {
        guard source != target, var settings = perDisplay[source] else { return nil }
        let own = perDisplay[target] ?? PerDisplayConfig()
        var copied = settings
        copied.identity = own.identity
        copied.pip = own.pip
        copied.brightness.gammaWorks = own.brightness.gammaWorks
        copied.brightness.xdrOverlayWorks = own.brightness.xdrOverlayWorks
        copied.brightness.xdrGammaWorks = own.brightness.xdrGammaWorks
        copied.ddc.framing = own.ddc.framing
        var moved = false
        if movePIP {
            let present = Set(copied.pip.configurations.map(\.id))
            var kept: [PIPConfiguration] = []
            for var item in settings.pip.configurations {
                guard copied.pip.configurations.count < PerDisplayPIP.maxConfigurations,
                      !present.contains(item.id) else {
                    kept.append(item)
                    continue
                }
                if item.target == target { item.target = nil }
                copied.pip.configurations.append(item)
                moved = true
            }
            settings.pip.configurations = kept
        }
        guard moved || copied != own else { return nil }
        var result = perDisplay
        result[target] = copied
        if moved { result[source] = settings }
        return result
    }

    /// How many of the remembered display's Picture in Picture setups `movePIP` would move here (0 = don't offer it).
    package static func movablePIPCount(from source: DisplayKey, to target: DisplayKey,
                                        in perDisplay: LossyMap<DisplayKey, PerDisplayConfig>) -> Int {
        guard source != target, let settings = perDisplay[source] else { return 0 }
        let own = perDisplay[target]?.pip.configurations ?? []
        let present = Set(own.map(\.id))
        let candidates = settings.pip.configurations.filter { !present.contains($0.id) }.count
        return min(candidates, max(0, PerDisplayPIP.maxConfigurations - own.count))
    }

    /// The "Copy settings from" row's help: what is replaced.
    package static var help: String {
        L("Replaces this display’s brightness, color, resolution, hardware control tuning, keys, and connection settings with a remembered display’s.")
    }

    /// The confirmation's title, naming the remembered display.
    package static func question(source: String) -> String { L("Copy the settings of “\(source)” to this display?") }

    /// The confirmation's message: what is replaced, and that the remembered display stays.
    package static func message(source: String) -> String {
        L("This display’s brightness, color, resolution, hardware control tuning (such as DDC timing and custom controls), keys (with their audio device) and connection settings are replaced. Snaptic keeps remembering “\(source)”.")
    }

    /// The confirmation's checkbox, shown when the remembered display has setups that can move (off by default).
    package static var movePIPTitle: String { L("Also move its Picture in Picture setups") }
}

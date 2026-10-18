import Foundation

// PIP and full-screen stream settings (owner E; PLAN §10, §4.10(3,5)).
// Saved configurations of a display source live in PerDisplayPIP (keyed by the
// source's DisplayKey); configurations whose source is a window picked per session
// live in PIPConfig.windowConfigurations.

/// A floating PIP window or a full-screen stream onto another display.
package enum PIPKind: String, Codable, CaseIterable, Sendable { case window, fullScreen }

/// PIP window level: normal, floating, or above everything (`.statusBar`).
package enum PIPLevel: String, Codable, CaseIterable, Sendable { case normal, floating, aboveAll }

/// How a full-screen stream fits the target.
package enum PIPScaling: String, Codable, CaseIterable, Sendable { case fit, fill, oneToOne, integer }

/// Where a configuration's pixels come from.
package enum PIPSourceRef: Hashable, Sendable {
    case display(DisplayKey)
    /// Chosen with the system content-sharing picker each session.
    case window
}

/// A rectangle in plain numbers (Codable, clampable).
package struct PIPRect: Codable, Equatable, Sendable {
    package var x: Double
    package var y: Double
    package var width: Double
    package var height: Double

    package init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package var isFinite: Bool { x.isFinite && y.isFinite && width.isFinite && height.isFinite }

    /// A crop in normalized source coordinates (top-left origin), or nil if it can't be one.
    package func normalizedCrop() -> PIPRect? {
        guard isFinite else { return nil }
        let minSide = PIPConfiguration.minCropFraction
        let nx = Swift.min(Swift.max(x, 0), 1 - minSide)
        let ny = Swift.min(Swift.max(y, 0), 1 - minSide)
        let nw = Swift.min(Swift.max(width, minSide), 1 - nx)
        let nh = Swift.min(Swift.max(height, minSide), 1 - ny)
        let r = PIPRect(x: nx, y: ny, width: nw, height: nh)
        // A crop of (nearly) everything is no crop.
        if r.width >= 0.999, r.height >= 0.999 { return nil }
        return r
    }

    /// A window frame in global points, or nil if it can't be one.
    package func windowFrame() -> PIPRect? {
        guard isFinite else { return nil }
        let w = Swift.min(Swift.max(width, PIPConfiguration.minWindowSide), PIPConfiguration.maxWindowSide)
        let h = Swift.min(Swift.max(height, PIPConfiguration.minWindowSide), PIPConfiguration.maxWindowSide)
        let limit = PIPConfiguration.maxWindowOrigin
        return PIPRect(x: Swift.min(Swift.max(x, -limit), limit), y: Swift.min(Swift.max(y, -limit), limit),
                       width: w, height: h)
    }
}

/// One saved PIP or stream configuration.
package struct PIPConfiguration: Codable, Equatable, Sendable, Identifiable {
    package static let maxFilters = FilterSpec.maxFiltersPerChain
    package static let minCropFraction = 0.02
    package static let minWindowSide = 80.0
    package static let maxWindowSide = 16384.0
    package static let maxWindowOrigin = 100_000.0
    package static let maxNameScalars = 64
    package static let fpsRange = 1...120
    package static let underscanRange = 10...200
    package static let opacityRange = 0.1...1.0

    package var id: StableID
    package var name: String
    package var kind: PIPKind
    /// The display a full-screen stream covers (ignored for window PIPs).
    package var target: DisplayKey?

    // Window
    package var level: PIPLevel
    package var opacity: Double
    package var clickThrough: Bool
    package var lockPosition: Bool
    package var lockAspect: Bool
    package var integerScaling: Bool
    package var showTitleBar: Bool
    package var snapToQuarters: Bool
    package var shadow: Bool
    /// Last window frame in global points (AppKit coordinates).
    package var windowFrame: PIPRect?

    // Capture
    /// 0 = the source display's refresh rate.
    package var fps: Int
    /// Normalized source rectangle, top-left origin; nil = everything.
    package var crop: PIPRect?
    package var showCursor: Bool
    package var warpOnCommandClick: Bool

    // Geometry
    package var flipHorizontal: Bool
    package var flipVertical: Bool
    /// Clockwise degrees: 0, 90, 180 or 270.
    package var rotation: Int

    // Full screen
    package var scaling: PIPScaling
    /// 100 = edge to edge; below shrinks, above zooms.
    package var underscanPercent: Int
    /// Switch the target to its native mode while streaming (a trial).
    package var nativeModeWhileStreaming: Bool

    // Filters
    package var filters: [FilterInstance]
    package var lutID: StableID?

    /// Offer to start when the source connects (and at launch). Never unattended.
    package var autoStart: Bool

    package init(id: StableID = StableID(), name: String = L("Picture in Picture"), kind: PIPKind = .window) {
        self.id = id
        self.name = name
        self.kind = kind
        target = nil
        level = .floating
        opacity = 1
        clickThrough = false
        lockPosition = false
        lockAspect = true
        integerScaling = false
        showTitleBar = true
        snapToQuarters = false
        shadow = true
        windowFrame = nil
        fps = 30
        crop = nil
        showCursor = true
        warpOnCommandClick = true
        flipHorizontal = false
        flipVertical = false
        rotation = 0
        scaling = .fit
        underscanPercent = 100
        nativeModeWhileStreaming = false
        filters = []
        lutID = nil
        autoStart = false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, target, level, opacity, clickThrough, lockPosition, lockAspect, integerScaling,
             showTitleBar, snapToQuarters, shadow, windowFrame, fps, crop, showCursor, warpOnCommandClick,
             flipHorizontal, flipVertical, rotation, scaling, underscanPercent, nativeModeWhileStreaming,
             filters, lutID, autoStart
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PIPConfiguration()
        id = c.lossy(.id, StableID())
        name = c.lossy(.name, d.name)
        kind = c.lossy(.kind, d.kind)
        target = c.lossy(.target, nil)
        level = c.lossy(.level, d.level)
        opacity = c.lossy(.opacity, d.opacity)
        clickThrough = c.lossy(.clickThrough, d.clickThrough)
        lockPosition = c.lossy(.lockPosition, d.lockPosition)
        lockAspect = c.lossy(.lockAspect, d.lockAspect)
        integerScaling = c.lossy(.integerScaling, d.integerScaling)
        showTitleBar = c.lossy(.showTitleBar, d.showTitleBar)
        snapToQuarters = c.lossy(.snapToQuarters, d.snapToQuarters)
        shadow = c.lossy(.shadow, d.shadow)
        windowFrame = c.lossy(.windowFrame, nil)
        fps = c.lossy(.fps, d.fps)
        crop = c.lossy(.crop, nil)
        showCursor = c.lossy(.showCursor, d.showCursor)
        warpOnCommandClick = c.lossy(.warpOnCommandClick, d.warpOnCommandClick)
        flipHorizontal = c.lossy(.flipHorizontal, d.flipHorizontal)
        flipVertical = c.lossy(.flipVertical, d.flipVertical)
        rotation = c.lossy(.rotation, d.rotation)
        scaling = c.lossy(.scaling, d.scaling)
        underscanPercent = c.lossy(.underscanPercent, d.underscanPercent)
        nativeModeWhileStreaming = c.lossy(.nativeModeWhileStreaming, d.nativeModeWhileStreaming)
        filters = c.lossyArray(.filters, [])
        lutID = c.lossy(.lutID, nil)
        autoStart = c.lossy(.autoStart, d.autoStart)
    }

    package static func cleanName(_ raw: String) -> String {
        let cleaned = TextSanitizer.clean(raw, maxScalars: maxNameScalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? L("Picture in Picture") : cleaned
    }

    package static func normalizedRotation(_ degrees: Int) -> Int {
        let r = ((degrees % 360) + 360) % 360
        return ((r + 45) / 90 % 4) * 90
    }

    package func sanitized() -> PIPConfiguration {
        var c = self
        c.name = Self.cleanName(name)
        c.opacity = opacity.isFinite ? Swift.min(Swift.max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound) : 1
        c.windowFrame = windowFrame?.windowFrame()
        c.fps = fps == 0 ? 0 : Swift.min(Swift.max(fps, Self.fpsRange.lowerBound), Self.fpsRange.upperBound)
        c.crop = crop?.normalizedCrop()
        c.rotation = Self.normalizedRotation(rotation)
        c.underscanPercent = Swift.min(Swift.max(underscanPercent, Self.underscanRange.lowerBound), Self.underscanRange.upperBound)
        c.filters = Array(filters.prefix(Self.maxFilters)).map { $0.sanitized() }
        if kind == .window { c.nativeModeWhileStreaming = false }
        return c
    }

    /// The rotation swaps width and height.
    package var isQuarterTurn: Bool { rotation == 90 || rotation == 270 }
}

/// An imported `.cube` file (the table itself is stored in Snaptic's support folder).
package struct PIPLUTReference: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var name: String
    package var size: Int

    package init(id: StableID = StableID(), name: String, size: Int) {
        self.id = id
        self.name = name
        self.size = size
    }

    package func sanitized() -> PIPLUTReference? {
        guard size >= CubeLUT.minSize, size <= CubeLUT.maxSize else { return nil }
        var r = self
        let cleaned = TextSanitizer.clean(name, maxScalars: PIPConfiguration.maxNameScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        r.name = cleaned.isEmpty ? L("LUT") : cleaned
        return r
    }
}

/// Global PIP settings.
package struct PIPConfig: ConfigModel {
    package static let maxWindowConfigurations = 8
    package static let maxLUTs = 32
    package static let maxProtectedPrefixes = 64
    /// Running sessions at once (windows plus streams).
    package static let maxConcurrentSessions = 8

    package var windowConfigurations: [PIPConfiguration]
    package var luts: [PIPLUTReference]
    /// Apps whose windows never appear in a display capture (bundle id or prefix).
    package var protectedBundlePrefixes: [String]
    /// The first-run explanation (Screen Recording, monthly prompts, relaunch) was read.
    package var firstRunAcknowledged: Bool
    package var pauseWhenOccluded: Bool
    /// ⌃⌥⌘P stops streams and leaves click-through.
    package var stopHotkeyEnabled: Bool

    package init() {
        windowConfigurations = []
        luts = []
        protectedBundlePrefixes = PIPPrivacy.defaultProtectedPrefixes
        firstRunAcknowledged = false
        pauseWhenOccluded = true
        stopHotkeyEnabled = true
    }

    private enum CodingKeys: String, CodingKey {
        case windowConfigurations, luts, protectedBundlePrefixes, firstRunAcknowledged, pauseWhenOccluded, stopHotkeyEnabled
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PIPConfig()
        windowConfigurations = c.lossyArray(.windowConfigurations, [])
        luts = c.lossyArray(.luts, [])
        protectedBundlePrefixes = c.lossy(.protectedBundlePrefixes, d.protectedBundlePrefixes)
        firstRunAcknowledged = c.lossy(.firstRunAcknowledged, d.firstRunAcknowledged)
        pauseWhenOccluded = c.lossy(.pauseWhenOccluded, d.pauseWhenOccluded)
        stopHotkeyEnabled = c.lossy(.stopHotkeyEnabled, d.stopHotkeyEnabled)
    }

    package func sanitized() -> PIPConfig {
        var c = self
        c.windowConfigurations = PIPConfig.sanitizedList(windowConfigurations, max: Self.maxWindowConfigurations)
        var seen = Set<StableID>()
        c.luts = luts.compactMap { $0.sanitized() }.filter { seen.insert($0.id).inserted }
        c.luts = Array(c.luts.prefix(Self.maxLUTs))
        c.protectedBundlePrefixes = PIPPrivacy.sanitizedPrefixes(protectedBundlePrefixes)
        return c
    }

    /// Sanitized, unique ids, at most `max` entries.
    package static func sanitizedList(_ list: [PIPConfiguration], max: Int) -> [PIPConfiguration] {
        var seen = Set<StableID>()
        var out: [PIPConfiguration] = []
        for item in list {
            guard seen.insert(item.id).inserted else { continue }
            out.append(item.sanitized())
            if out.count == max { break }
        }
        return out
    }

    // MARK: Access across displays

    /// Every saved configuration with its source. Display sources come first, sorted
    /// by key; an id that appears twice keeps its first entry.
    package static func entries(in config: DisplaysConfig) -> [PIPEntry] {
        var out: [PIPEntry] = []
        var seen = Set<StableID>()
        for key in config.perDisplay.values.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            for item in config.perDisplay.values[key]?.pip.configurations ?? [] where seen.insert(item.id).inserted {
                out.append(PIPEntry(source: .display(key), configuration: item))
            }
        }
        for item in config.pip.windowConfigurations where seen.insert(item.id).inserted {
            out.append(PIPEntry(source: .window, configuration: item))
        }
        return out
    }

    package static func entry(_ id: StableID, in config: DisplaysConfig) -> PIPEntry? {
        entries(in: config).first { $0.configuration.id == id }
    }

    /// Adds a configuration for a source. False when that source is full.
    @discardableResult
    package static func add(_ item: PIPConfiguration, source: PIPSourceRef, to config: inout DisplaysConfig) -> Bool {
        switch source {
        case .display(let key):
            var per = config.perDisplay[key] ?? PerDisplayConfig()
            guard per.pip.configurations.count < PerDisplayPIP.maxConfigurations else { return false }
            per.pip.configurations.append(item.sanitized())
            config.perDisplay[key] = per
        case .window:
            guard config.pip.windowConfigurations.count < maxWindowConfigurations else { return false }
            config.pip.windowConfigurations.append(item.sanitized())
        }
        return true
    }

    /// Changes one configuration in place. False if no configuration has that id.
    @discardableResult
    package static func update(_ id: StableID, in config: inout DisplaysConfig,
                               _ body: (inout PIPConfiguration) -> Void) -> Bool {
        if let i = config.pip.windowConfigurations.firstIndex(where: { $0.id == id }) {
            body(&config.pip.windowConfigurations[i])
            config.pip.windowConfigurations[i] = config.pip.windowConfigurations[i].sanitized()
            config.pip.windowConfigurations[i].id = id
            return true
        }
        for key in config.perDisplay.values.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var per = config.perDisplay[key],
                  let i = per.pip.configurations.firstIndex(where: { $0.id == id }) else { continue }
            body(&per.pip.configurations[i])
            per.pip.configurations[i] = per.pip.configurations[i].sanitized()
            per.pip.configurations[i].id = id
            config.perDisplay[key] = per
            return true
        }
        return false
    }

    @discardableResult
    package static func remove(_ id: StableID, from config: inout DisplaysConfig) -> Bool {
        var removed = false
        let before = config.pip.windowConfigurations.count
        config.pip.windowConfigurations.removeAll { $0.id == id }
        removed = before != config.pip.windowConfigurations.count
        for key in Array(config.perDisplay.values.keys) {
            guard var per = config.perDisplay[key], per.pip.configurations.contains(where: { $0.id == id }) else { continue }
            per.pip.configurations.removeAll { $0.id == id }
            config.perDisplay[key] = per
            removed = true
        }
        return removed
    }

    /// Removes a LUT and every reference to it.
    package static func removeLUT(_ id: StableID, from config: inout DisplaysConfig) {
        config.pip.luts.removeAll { $0.id == id }
        for i in config.pip.windowConfigurations.indices where config.pip.windowConfigurations[i].lutID == id {
            config.pip.windowConfigurations[i].lutID = nil
        }
        for key in Array(config.perDisplay.values.keys) {
            guard var per = config.perDisplay[key], per.pip.configurations.contains(where: { $0.lutID == id }) else { continue }
            for i in per.pip.configurations.indices where per.pip.configurations[i].lutID == id {
                per.pip.configurations[i].lutID = nil
            }
            config.perDisplay[key] = per
        }
    }
}

package struct PIPEntry: Equatable, Sendable {
    package let source: PIPSourceRef
    package let configuration: PIPConfiguration

    package init(source: PIPSourceRef, configuration: PIPConfiguration) {
        self.source = source
        self.configuration = configuration
    }
}

/// Saved configurations whose source is this display.
package struct PerDisplayPIP: ConfigModel {
    package static let maxConfigurations = 8

    package var configurations: [PIPConfiguration]

    package init() { configurations = [] }

    private enum CodingKeys: String, CodingKey { case configurations }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configurations = c.lossyArray(.configurations, [])
    }

    package func sanitized() -> PerDisplayPIP {
        var c = self
        c.configurations = PIPConfig.sanitizedList(configurations, max: Self.maxConfigurations)
        return c
    }
}

// MARK: - Settings (0.3 §4.3 "Picture in Picture")

/// Names, subtitles and limits the Picture in Picture page and editor show. Plain text, so it's tested here.
package enum PIPSettingsText {
    /// A new configuration's name: "Built-in Display PIP", "Window PIP", "Built-in Display → DELL U2720Q".
    package static func defaultName(sourceName: String?, kind: PIPKind, targetName: String?) -> String {
        let source = sourceName.map { PIPConfiguration.cleanName($0) } ?? L("Window")
        if kind == .fullScreen, let targetName {
            return PIPConfiguration.cleanName(L("\(source) → \(PIPConfiguration.cleanName(targetName))"))
        }
        return PIPConfiguration.cleanName(L("\(source) PIP"))
    }

    /// The saved list's subtitle: where it comes from, then what's special about it, in a fixed order.
    /// `sourceName` nil = a window picked when it starts; `targetName` nil for a stream = nowhere to stream yet.
    package static func subtitle(_ c: PIPConfiguration, sourceName: String?, targetName: String?) -> String {
        var parts: [String] = []
        parts.append(sourceName ?? L("A window you choose"))
        if c.kind == .fullScreen {
            parts.append(targetName.map { L("Full screen on \($0)") } ?? L("Choose a display to stream onto"))
        }
        if c.fps != 0 { parts.append(L("\(c.fps) fps")) }
        if c.crop != nil { parts.append(L("Cropped")) }
        if c.rotation != 0 { parts.append(L("Rotated \(c.rotation)°")) }
        if c.flipHorizontal || c.flipVertical { parts.append(L("Flipped")) }
        if !c.filters.filter(\.enabled).isEmpty || c.lutID != nil { parts.append(L("Filters")) }
        if c.autoStart { parts.append(L("Offers to start")) }
        return parts.joined(separator: " · ")
    }

    /// "50% × 40% at 10%, 20%" for a crop, "None" without one.
    package static func crop(_ crop: PIPRect?) -> String {
        guard let c = crop?.normalizedCrop() else { return L("None") }
        func pct(_ v: Double) -> Int { Int((v * 100).rounded()) }
        return L("\(pct(c.width))% × \(pct(c.height))% at \(pct(c.x))%, \(pct(c.y))%")
    }

    /// Room for one more saved configuration of this source.
    package static func canAdd(source: PIPSourceRef, in config: DisplaysConfig) -> Bool {
        switch source {
        case .display(let key):
            return (config.perDisplay[key]?.pip.configurations.count ?? 0) < PerDisplayPIP.maxConfigurations
        case .window:
            return config.pip.windowConfigurations.count < PIPConfig.maxWindowConfigurations
        }
    }

    /// Why a new configuration can't be added as drafted, or nil: the source is full, or a stream has nowhere to
    /// go (no target, or the target is its own source).
    package static func addRefusal(_ c: PIPConfiguration, source: PIPSourceRef, in config: DisplaysConfig) -> String? {
        guard canAdd(source: source, in: config) else {
            return L("This source already has the most saved pictures in picture. Delete one first.")
        }
        if c.kind == .fullScreen {
            guard let target = c.target else { return L("Choose a display to stream onto.") }
            if case .display(let key) = source, key == target {
                return L("A display can’t stream onto itself.")
            }
        }
        return nil
    }
}

// MARK: - Privacy (PLAN §4.10(5))

package enum PIPPrivacy {
    /// Never captured, whatever the settings say.
    package static let alwaysExcludedBundleIDs = ["com.apple.notificationcenterui"]

    package static let defaultProtectedPrefixes = [
        "com.1password",
        "com.agilebits",
        "com.bitwarden",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "in.sinew.Enpass-Desktop",
        "com.dashlane",
        "com.lastpass",
        "org.keepassxc",
        "org.torproject",
    ]

    /// Browsers: an untitled browser window may be a private one (titles we can't read).
    package static let browserPrefixes = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.", "com.microsoft.edgemac",
        "com.brave.Browser", "company.thebrowser.", "com.operasoftware.", "com.vivaldi.",
        "org.torproject.", "com.duckduckgo.", "com.kagi.", "app.zen-browser.",
    ]

    /// A plausible reverse-DNS prefix with at least two parts, so an entry can't
    /// match nearly every app.
    package static func isValidPrefix(_ entry: String) -> Bool {
        let parts = entry.split(separator: ".", omittingEmptySubsequences: false)
        guard entry.utf8.count <= 255, parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        return entry.unicodeScalars.allSatisfy {
            ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x41 && $0.value <= 0x5A)
                || ($0.value >= 0x30 && $0.value <= 0x39) || $0 == "." || $0 == "-" || $0 == "_"
        }
    }

    /// Valid entries only, each once, in order, at most `PIPConfig.maxProtectedPrefixes` (the config's sanitizer and
    /// Settings' "Never capture these apps" list).
    package static func sanitizedPrefixes(_ list: [String]) -> [String] {
        var prefixes: [String] = []
        for p in list where isValidPrefix(p) && !prefixes.contains(p) {
            prefixes.append(p)
            if prefixes.count == PIPConfig.maxProtectedPrefixes { break }
        }
        return prefixes
    }

    /// The list holds exactly the default entries (any order): Settings then hides "Restore Default Apps".
    package static func isDefaultList(_ list: [String]) -> Bool {
        Set(list) == Set(defaultProtectedPrefixes) && list.count == defaultProtectedPrefixes.count
    }

    /// The id itself, or anything under it (`com.lastpass` matches `com.lastpass.LastPass`).
    package static func matches(_ bundleID: String?, prefixes: [String]) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return prefixes.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    /// Whether an app's windows may appear in a display capture at all. Apps without
    /// a bundle id are allowed (system UI such as the menu bar and Dock).
    package static func isCaptureAllowed(bundleID: String?, ownBundleID: String?, protected: [String]) -> Bool {
        if let own = ownBundleID, !own.isEmpty, bundleID == own { return false }
        if matches(bundleID, prefixes: alwaysExcludedBundleIDs) { return false }
        return !matches(bundleID, prefixes: protected)
    }

    /// A window that must be excluded individually: a private-browsing title, or a
    /// browser window whose title can't be read.
    package static func isPrivateWindow(title: String?, bundleID: String?) -> Bool {
        if let title, TextSanitizer.hasPrivateMarker(title) { return true }
        let isBrowser = browserPrefixes.contains { (bundleID ?? "").hasPrefix($0) }
        return isBrowser && (title ?? "").isEmpty
    }
}

// MARK: - CLI (PLAN §4.10(3): saved configurations only, on console and unlocked)

package enum PIPCommand: Equatable, Sendable {
    case list
    case start(String)
    case stop(String)
    /// `start --display <selector>`: the saved configurations whose source is that
    /// display (the selector is resolved by `DisplaySelectorResolver` in the app).
    case startDisplay(String)
    /// `stop --display <selector>`: every session whose source or target is that display.
    case stopDisplay(String)
    case stopAll, hideAll, showAll, pauseAll, resumeAll

    package static let usage = "pip list | start <name|id> | start --display <display> | stop <name|id> | stop --display <display>"
        + " | stop-all | hide-all | show-all | pause-all | resume-all"

    /// The display flag: `--display <sel>`, `-d <sel>` or `--display=<sel>`.
    private static func displaySelector(_ rest: ArraySlice<String>) -> String?? {
        guard let first = rest.first else { return .none }
        let flag = first.lowercased()
        var tail: [String]
        if flag == "--display" || flag == "-d" {
            tail = Array(rest.dropFirst())
        } else if flag.hasPrefix("--display=") {
            tail = [String(first.dropFirst("--display=".count))] + rest.dropFirst()
        } else {
            return .none
        }
        tail = tail.filter { !$0.isEmpty }
        let text = tail.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        // ControlSelector refuses more than 128 UTF-8 bytes; so do we (no silent truncation).
        guard !text.isEmpty, text.utf8.count <= 128 else { return .some(nil) }
        return .some(text)
    }

    /// Nil for anything malformed (the caller prints `usage`).
    package static func parse(_ arguments: [String]) -> PIPCommand? {
        guard let verb = arguments.first?.lowercased(), arguments.count <= 32 else { return nil }
        let rest = arguments.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let query = TextSanitizer.clean(rest, maxScalars: 256)
        if verb == "start" || verb == "stop", let selector = displaySelector(arguments.dropFirst()) {
            guard let selector else { return nil }
            return verb == "start" ? .startDisplay(selector) : .stopDisplay(selector)
        }
        switch verb {
        case "list", "ls": return arguments.count == 1 ? .list : nil
        case "start": return query.isEmpty ? nil : .start(query)
        case "stop": return query.isEmpty ? nil : .stop(query)
        case "stop-all": return arguments.count == 1 ? .stopAll : nil
        case "hide-all": return arguments.count == 1 ? .hideAll : nil
        case "show-all": return arguments.count == 1 ? .showAll : nil
        case "pause-all": return arguments.count == 1 ? .pauseAll : nil
        case "resume-all": return arguments.count == 1 ? .resumeAll : nil
        default: return nil
        }
    }
}

package enum PIPLookup {
    package enum Match: Equatable, Sendable {
        case found(StableID)
        case notFound
        case ambiguous(Int)
    }

    /// By id, then exact name (case-insensitive), then a unique name prefix.
    package static func find(_ query: String, in items: [PIPConfiguration]) -> Match {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return .notFound }
        if let id = StableID(rawValue: q), items.contains(where: { $0.id == id }) { return .found(id) }
        let lowered = q.lowercased()
        let exact = items.filter { $0.name.lowercased() == lowered }
        if exact.count == 1 { return .found(exact[0].id) }
        if exact.count > 1 { return .ambiguous(exact.count) }
        let prefixed = items.filter { $0.name.lowercased().hasPrefix(lowered) }
        if prefixed.count == 1 { return .found(prefixed[0].id) }
        if prefixed.count > 1 { return .ambiguous(prefixed.count) }
        return .notFound
    }

    /// What `pip start --display` starts among a display's saved configurations: the
    /// first window PIP, else the first stream. Nothing is ever created from the CLI.
    package static func preferredForDisplay(_ items: [PIPConfiguration]) -> PIPConfiguration? {
        items.first { $0.kind == .window } ?? items.first
    }
}

// MARK: - Menu (0.3 §5.2: the Displays section's "Picture in Picture ›" submenu)

/// What the "Picture in Picture ›" submenu lists: saved configurations with a checkmark on the running ones (a
/// click starts or stops one), then Stop All. The submenu exists only while something is saved; it keeps to
/// `maxRows` saved rows (§5.1: ≤ ~12 items) and then ends with one "More…" that opens Settings.
package enum PIPMenuPlan {
    package static let maxRows = 10

    package struct Row: Equatable, Sendable {
        package let id: StableID
        package let name: String
        package let kind: PIPKind
        package let running: Bool
        /// False while its source (or a stream's target) display isn't connected and it isn't running.
        package let available: Bool

        package init(id: StableID, name: String, kind: PIPKind, running: Bool, available: Bool) {
            self.id = id
            self.name = name
            self.kind = kind
            self.running = running
            self.available = available
        }
    }

    package struct Plan: Equatable, Sendable {
        package let rows: [Row]
        /// Some saved configurations were left out: the submenu ends with "More…".
        package let truncated: Bool
        /// Stop All is enabled.
        package let anyRunning: Bool

        package init(rows: [Row], truncated: Bool, anyRunning: Bool) {
            self.rows = rows
            self.truncated = truncated
            self.anyRunning = anyRunning
        }
    }

    /// The submenu for `entries` (`PIPConfig.entries(in:)` order); nil when nothing is saved (no submenu).
    /// With more than `limit` entries the running ones are always kept (up to `limit`), the rest fill up in
    /// saved order, and the rows stay in saved order.
    package static func plan(entries: [PIPEntry], running: Set<StableID>, connected: Set<DisplayKey>,
                             limit: Int = maxRows) -> Plan? {
        guard !entries.isEmpty else { return nil }
        let limit = max(1, limit)
        var keep = Set<Int>()
        for (i, e) in entries.enumerated() where running.contains(e.configuration.id) && keep.count < limit {
            keep.insert(i)
        }
        for i in entries.indices where keep.count < limit { keep.insert(i) }
        let rows = entries.enumerated().filter { keep.contains($0.offset) }.map { pair -> Row in
            let c = pair.element.configuration
            let isRunning = running.contains(c.id)
            return Row(id: c.id, name: c.name, kind: c.kind, running: isRunning,
                       available: isRunning || isAvailable(pair.element, connected: connected))
        }
        let anyRunning = entries.contains { running.contains($0.configuration.id) }
        return Plan(rows: rows, truncated: rows.count < entries.count, anyRunning: anyRunning)
    }

    /// A saved configuration can start from the menu: its source display (if any) is connected, and a stream's
    /// target is connected and isn't its source. Deeper checks (mirroring, the session limit) run at start.
    package static func isAvailable(_ entry: PIPEntry, connected: Set<DisplayKey>) -> Bool {
        let c = entry.configuration
        if case .display(let key) = entry.source {
            guard connected.contains(key) else { return false }
            if c.kind == .fullScreen {
                guard let target = c.target, target != key, connected.contains(target) else { return false }
            }
            return true
        }
        if c.kind == .fullScreen {
            guard let target = c.target, connected.contains(target) else { return false }
        }
        return true
    }
}

// MARK: - Geometry (plain numbers: Kit can't use the CoreGraphics overlay)

package struct PIPSize: Equatable, Sendable {
    package var width: Double
    package var height: Double
    package init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
    package static let zero = PIPSize(width: 0, height: 0)
}

package struct PIPPoint: Equatable, Sendable {
    package var x: Double
    package var y: Double
    package init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

extension PIPRect {
    package var midX: Double { x + width / 2 }
    package var midY: Double { y + height / 2 }
    package var size: PIPSize { PIPSize(width: width, height: height) }
}

package enum PIPGeometry {
    package static let maxCaptureSide = 8192.0

    /// What the viewer sees of the source: after the crop, then the rotation.
    package static func visibleSize(source: PIPSize, crop: PIPRect?, rotation: Int) -> PIPSize {
        let c = crop?.normalizedCrop()
        let w = Double(source.width) * (c?.width ?? 1)
        let h = Double(source.height) * (c?.height ?? 1)
        let r = PIPConfiguration.normalizedRotation(rotation)
        return (r == 90 || r == 270) ? PIPSize(width: h, height: w) : PIPSize(width: w, height: h)
    }

    /// Where the (rotated) content sits inside `bounds` (points, origin bottom-left or
    /// top-left: the rect is centered either way). `contentPixels` is the visible size in
    /// source pixels; `backingScale` is the target's pixels per point.
    package static func contentRect(contentPixels: PIPSize, in bounds: PIPSize, scaling: PIPScaling,
                                    underscanPercent: Int, backingScale: Double) -> PIPRect {
        guard contentPixels.width > 0, contentPixels.height > 0, bounds.width > 0, bounds.height > 0 else {
            return PIPRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        }
        let scale = backingScale.isFinite && backingScale > 0 ? backingScale : 1
        let cw = Double(contentPixels.width), ch = Double(contentPixels.height)
        let bw = Double(bounds.width), bh = Double(bounds.height)
        var w: Double
        var h: Double
        switch scaling {
        case .fit:
            let k = Swift.min(bw / cw, bh / ch)
            w = cw * k
            h = ch * k
        case .fill:
            let k = Swift.max(bw / cw, bh / ch)
            w = cw * k
            h = ch * k
        case .oneToOne:
            w = cw / scale
            h = ch / scale
        case .integer:
            let k = floor(Swift.min(bw * scale / cw, bh * scale / ch))
            if k >= 1 {
                w = cw * k / scale
                h = ch * k / scale
            } else {
                let f = Swift.min(bw / cw, bh / ch)
                w = cw * f
                h = ch * f
            }
        }
        let u = Double(Swift.min(Swift.max(underscanPercent, PIPConfiguration.underscanRange.lowerBound),
                                 PIPConfiguration.underscanRange.upperBound)) / 100
        w *= u
        h *= u
        return PIPRect(x: (bw - w) / 2, y: (bh - h) / 2, width: w, height: h)
    }

    /// Snaps a window content size to 25% steps of the visible source size, keeping
    /// the source aspect. Never below one step.
    package static func snapped(_ size: PIPSize, visible: PIPSize) -> PIPSize {
        guard visible.width > 0, visible.height > 0, size.width > 0 else { return size }
        let ratio = Double(size.width) / Double(visible.width)
        let steps = Swift.max(1, (ratio / 0.25).rounded())
        let k = steps * 0.25
        return PIPSize(width: Double(visible.width) * k, height: Double(visible.height) * k)
    }

    /// Pixel size to ask the capture for: the cropped source fitted into the view's
    /// pixels (never upscaled), or the full source size for integer scaling. Even,
    /// at least 16 and at most `maxCaptureSide` per side. Both sizes unrotated.
    package static func captureSize(sourcePixels: PIPSize, viewPixels: PIPSize, fullResolution: Bool) -> PIPSize {
        let sw = Swift.max(1, Double(sourcePixels.width).isFinite ? Double(sourcePixels.width) : 1)
        let sh = Swift.max(1, Double(sourcePixels.height).isFinite ? Double(sourcePixels.height) : 1)
        var k = 1.0
        if !fullResolution, viewPixels.width > 0, viewPixels.height > 0 {
            k = Swift.min(1, Swift.max(Double(viewPixels.width) / sw, Double(viewPixels.height) / sh))
        }
        k = Swift.min(k, maxCaptureSide / sw, maxCaptureSide / sh)
        func even(_ v: Double) -> Double { Swift.max(16, (v / 2).rounded() * 2) }
        return PIPSize(width: Swift.min(even(sw * k), maxCaptureSide), height: Swift.min(even(sh * k), maxCaptureSide))
    }

    /// Maps a point in the content (normalized, top-left origin) back to the full
    /// source (normalized, top-left origin), undoing rotation, flips and crop.
    package static func sourcePoint(view p: PIPPoint, crop: PIPRect?, rotation: Int, flipHorizontal: Bool,
                                    flipVertical: Bool) -> PIPPoint {
        var x = Swift.min(Swift.max(Double(p.x), 0), 1)
        var y = Swift.min(Swift.max(Double(p.y), 0), 1)
        // Displayed = rotate(flip(source)); undo the rotation first.
        switch PIPConfiguration.normalizedRotation(rotation) {
        case 90: (x, y) = (y, 1 - x)
        case 180: (x, y) = (1 - x, 1 - y)
        case 270: (x, y) = (1 - y, x)
        default: break
        }
        if flipHorizontal { x = 1 - x }
        if flipVertical { y = 1 - y }
        if let c = crop?.normalizedCrop() {
            x = c.x + x * c.width
            y = c.y + y * c.height
        }
        return PIPPoint(x: x, y: y)
    }

    /// The inverse of `sourcePoint`, for drawing source-space rectangles on the view.
    package static func viewPoint(source p: PIPPoint, crop: PIPRect?, rotation: Int, flipHorizontal: Bool,
                                  flipVertical: Bool) -> PIPPoint {
        var x = Double(p.x)
        var y = Double(p.y)
        if let c = crop?.normalizedCrop() {
            x = (x - c.x) / c.width
            y = (y - c.y) / c.height
        }
        if flipHorizontal { x = 1 - x }
        if flipVertical { y = 1 - y }
        switch PIPConfiguration.normalizedRotation(rotation) {
        case 90: (x, y) = (1 - y, x)
        case 180: (x, y) = (1 - x, 1 - y)
        case 270: (x, y) = (y, 1 - x)
        default: break
        }
        return PIPPoint(x: x, y: y)
    }

    /// Seconds between frames: `fps` 0 follows the display (60 if unknown, at most 120).
    package static func frameInterval(fps: Int, displayRefresh: Double) -> Double {
        if fps <= 0 {
            let r = displayRefresh.isFinite && displayRefresh >= 1 ? Swift.min(displayRefresh, 120) : 60
            return 1 / r
        }
        return 1 / Double(Swift.min(Swift.max(fps, PIPConfiguration.fpsRange.lowerBound), PIPConfiguration.fpsRange.upperBound))
    }

    /// A crop rectangle (normalized source space) from two corners dragged on the
    /// view, composed with the crop already in effect.
    package static func cropFromDrag(start: PIPPoint, end: PIPPoint, current: PIPRect?, rotation: Int,
                                     flipHorizontal: Bool, flipVertical: Bool) -> PIPRect? {
        let a = sourcePoint(view: start, crop: current, rotation: rotation, flipHorizontal: flipHorizontal,
                            flipVertical: flipVertical)
        let b = sourcePoint(view: end, crop: current, rotation: rotation, flipHorizontal: flipHorizontal,
                            flipVertical: flipVertical)
        let r = PIPRect(x: Double(Swift.min(a.x, b.x)), y: Double(Swift.min(a.y, b.y)),
                        width: Double(abs(a.x - b.x)), height: Double(abs(a.y - b.y)))
        guard r.width >= PIPConfiguration.minCropFraction, r.height >= PIPConfiguration.minCropFraction else { return nil }
        return r.normalizedCrop()
    }
}

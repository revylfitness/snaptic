import Foundation

/// How a feature is enabled by default.
package enum FeatureDefault: String, Codable, Sendable {
    /// Always on while the module runs; not user-switchable.
    case always
    /// On by default.
    case standard
    /// Off by default.
    case optIn
    /// Off by default and labeled Experimental.
    case experimental
}

/// Static description of one Displays feature (PLAN §2.1, R5.4).
package struct FeatureSpec: Sendable {
    package let defaultState: FeatureDefault
    package let beta: Bool
    /// Turned on together with this feature.
    package let requiresAll: [DisplayFeature]
    /// At least one must be on; when none is, the first available one is turned on.
    package let requiresAny: [DisplayFeature]
    package let uses: Set<DisplayServiceID>
    package let controller: DisplayControllerID
    /// Settings page id (see DisplaysModule pages).
    package let page: String
    package let permissions: Set<Permission>

    package init(_ defaultState: FeatureDefault, beta: Bool = false, all: [DisplayFeature] = [], any: [DisplayFeature] = [],
                 uses: Set<DisplayServiceID> = [], controller: DisplayControllerID, page: String,
                 permissions: Set<Permission> = []) {
        self.defaultState = defaultState
        self.beta = beta
        self.requiresAll = all
        self.requiresAny = any
        self.uses = uses
        self.controller = controller
        self.page = page
        self.permissions = permissions
    }
}

/// The Displays feature graph: data plus pure resolution logic. Unit-tested on Linux.
package enum FeatureGraph {
    private static let methods: [DisplayFeature] = [.brightnessApple, .brightnessDDC, .brightnessGamma, .brightnessOverlay]

    package static let specs: [DisplayFeature: FeatureSpec] = [
        .overview: FeatureSpec(.always, uses: [.registry], controller: .overview, page: "overview"),
        .diagnostics: FeatureSpec(.always, uses: [.registry], controller: .diagnostics, page: "diagnostics"),

        .resolution: FeatureSpec(.standard, uses: [.registry, .transactions], controller: .resolution, page: "resolution"),
        .hiddenModes: FeatureSpec(.experimental, all: [.resolution], uses: [.transactions], controller: .resolution, page: "resolution"),
        .scaleMatch: FeatureSpec(.optIn, all: [.resolution], uses: [.transactions], controller: .resolution, page: "resolution"),

        .brightness: FeatureSpec(.standard, any: methods, uses: [.brightness], controller: .brightness, page: "brightness"),
        .brightnessApple: FeatureSpec(.standard, uses: [.appleBrightness], controller: .brightness, page: "brightness"),
        .brightnessDDC: FeatureSpec(.standard, uses: [.ddc], controller: .brightness, page: "brightness"),
        .brightnessGamma: FeatureSpec(.standard, uses: [.gamma], controller: .brightness, page: "brightness"),
        .brightnessOverlay: FeatureSpec(.standard, uses: [.overlays], controller: .brightness, page: "brightness"),
        .brightnessRestore: FeatureSpec(.standard, all: [.brightness], controller: .brightness, page: "brightness"),
        .dimToBlack: FeatureSpec(.optIn, all: [.brightness], any: [.brightnessGamma, .brightnessOverlay],
                                 uses: [.guardProcess], controller: .brightness, page: "brightness"),
        .dimOnLock: FeatureSpec(.optIn, all: [.brightness, .brightnessGamma], controller: .brightness, page: "brightness"),
        .nits: FeatureSpec(.optIn, all: [.brightness], controller: .brightness, page: "brightness"),
        .xdr: FeatureSpec(.optIn, beta: true, all: [.brightness], any: [.brightnessGamma, .brightnessOverlay],
                          uses: [.edr], controller: .xdr, page: "brightness"),
        .sync: FeatureSpec(.optIn, all: [.brightness], controller: .sync, page: "brightness"),
        .autoBrightness: FeatureSpec(.experimental, uses: [.appleBrightness], controller: .systemColors, page: "color"),

        .color: FeatureSpec(.optIn, uses: [.gamma], controller: .color, page: "color"),
        .colorProfiles: FeatureSpec(.optIn, uses: [.colorSync], controller: .systemColors, page: "color"),
        .nightShift: FeatureSpec(.experimental, controller: .systemColors, page: "color"),
        .applePresets: FeatureSpec(.experimental, uses: [.monitorPanel], controller: .systemColors, page: "color"),

        .ddcControls: FeatureSpec(.standard, uses: [.ddc], controller: .ddc, page: "ddc"),
        .ddcInput: FeatureSpec(.optIn, uses: [.ddc], controller: .ddc, page: "ddc"),
        .ddcPower: FeatureSpec(.optIn, uses: [.ddc], controller: .ddc, page: "ddc"),
        .ddcCustom: FeatureSpec(.optIn, uses: [.ddc], controller: .ddc, page: "ddc"),

        .brightnessKeys: FeatureSpec(.optIn, all: [.brightness], uses: [.mediaKeys], controller: .keys, page: "keys",
                                     permissions: [.accessibility]),
        .volumeKeys: FeatureSpec(.optIn, all: [.ddcControls], uses: [.mediaKeys], controller: .keys, page: "keys",
                                 permissions: [.accessibility]),
        .shortcuts: FeatureSpec(.standard, controller: .keys, page: "keys"),
        .osd: FeatureSpec(.standard, uses: [.osd], controller: .osd, page: "osd"),
        .osdBroadcast: FeatureSpec(.optIn, controller: .osd, page: "osd"),

        .mainDisplay: FeatureSpec(.standard, uses: [.transactions], controller: .arrangement, page: "arrangement"),
        .arrangement: FeatureSpec(.standard, uses: [.transactions], controller: .arrangement, page: "arrangement"),
        .mirroring: FeatureSpec(.standard, uses: [.transactions], controller: .arrangement, page: "arrangement"),
        .rotation: FeatureSpec(.optIn, beta: true, uses: [.monitorPanel, .transactions], controller: .panelProps, page: "arrangement"),
        .underscan: FeatureSpec(.experimental, uses: [.monitorPanel, .transactions], controller: .panelProps, page: "arrangement"),
        .hdrToggle: FeatureSpec(.experimental, uses: [.monitorPanel, .transactions], controller: .panelProps, page: "arrangement"),
        .disconnect: FeatureSpec(.optIn, beta: true, uses: [.transactions, .guardProcess], controller: .power, page: "arrangement"),
        .autoDisconnectBuiltin: FeatureSpec(.optIn, all: [.disconnect], uses: [.guardProcess], controller: .power, page: "arrangement"),
        .sleepPrevention: FeatureSpec(.optIn, controller: .power, page: "arrangement"),

        .protection: FeatureSpec(.optIn, uses: [.transactions], controller: .protection, page: "protection"),
        .layouts: FeatureSpec(.optIn, uses: [.transactions, .brightness], controller: .layouts, page: "protection"),

        .virtualScreens: FeatureSpec(.optIn, beta: true, uses: [.virtualHosts, .transactions], controller: .virtual, page: "virtual"),
        .smartHiDPI: FeatureSpec(.optIn, beta: true, uses: [.virtualHosts, .transactions, .guardProcess],
                                 controller: .smartHiDPI, page: "virtual"),
        .hdrVirtual: FeatureSpec(.experimental, any: [.virtualScreens, .smartHiDPI], uses: [.virtualHosts],
                                 controller: .virtual, page: "virtual"),

        .pip: FeatureSpec(.optIn, uses: [.capture], controller: .pip, page: "pip", permissions: [.screenRecording]),
        .pipFilters: FeatureSpec(.optIn, all: [.pip], uses: [.capture], controller: .pip, page: "pip",
                                 permissions: [.screenRecording]),

        .menuBarOverlays: FeatureSpec(.optIn, uses: [.overlays], controller: .menuBarOverlays, page: "color"),

        .hooks: FeatureSpec(.optIn, uses: [.spawner], controller: .automation, page: "automation"),
        .customActions: FeatureSpec(.optIn, uses: [.spawner], controller: .automation, page: "automation"),
    ]

    package static func spec(_ feature: DisplayFeature) -> FeatureSpec {
        // Every case has a spec (tested), so this never falls back in practice.
        specs[feature] ?? FeatureSpec(.optIn, controller: .overview, page: "overview")
    }

    package static func controller(of feature: DisplayFeature) -> DisplayControllerID { spec(feature).controller }

    package static func features(of controller: DisplayControllerID) -> Set<DisplayFeature> {
        Set(DisplayFeature.allCases.filter { spec($0).controller == controller })
    }

    package static func permissions(_ feature: DisplayFeature) -> Set<Permission> { spec(feature).permissions }

    /// Features removed from the effective set in Safe Mode (R5.4). Everything else is gated internally.
    package static let safeModeRemoves: Set<DisplayFeature> = [
        .xdr, .sync, .dimOnLock, .sleepPrevention, .protection, .autoDisconnectBuiltin, .hooks, .customActions,
    ]

    /// Features removed while panic is latched (R5.4).
    package static let panicLatchRemoves: Set<DisplayFeature> = [.protection, .autoDisconnectBuiltin, .hooks]

    /// Whether a feature is on before the user touches it.
    package static func isOnByDefault(_ feature: DisplayFeature) -> Bool {
        switch spec(feature).defaultState {
        case .always, .standard: return true
        case .optIn, .experimental: return false
        }
    }

    /// The raw (user-chosen) state of a feature: the stored value, or its default.
    package static func rawState(_ feature: DisplayFeature, in raw: [DisplayFeature: Bool]) -> Bool {
        if spec(feature).defaultState == .always { return true }
        return raw[feature] ?? isOnByDefault(feature)
    }

    /// The effective feature set: raw choices, minus kill switches, unavailable features,
    /// Safe Mode and panic removals, then repeatedly minus anything whose requirements
    /// are no longer met.
    package static func resolve(raw: [DisplayFeature: Bool], killSwitches: Set<DisplayFeature>, safeMode: Bool,
                                unavailable: Set<DisplayFeature>, panicLatch: Bool) -> Set<DisplayFeature> {
        var set = Set(DisplayFeature.allCases.filter { rawState($0, in: raw) })
        set.subtract(killSwitches)
        set.subtract(unavailable)
        if safeMode { set.subtract(safeModeRemoves) }
        if panicLatch { set.subtract(panicLatchRemoves) }
        var changed = true
        while changed {
            changed = false
            for feature in set {
                let s = spec(feature)
                let allMet = s.requiresAll.allSatisfy { set.contains($0) }
                let anyMet = s.requiresAny.isEmpty || s.requiresAny.contains { set.contains($0) }
                if !allMet || !anyMet {
                    set.remove(feature)
                    changed = true
                }
            }
        }
        return set
    }

    /// The raw changes needed to turn a feature on: the feature, everything it requires
    /// (recursively), and for each "any" requirement with nothing on, the first available.
    package static func enabling(_ feature: DisplayFeature, raw: [DisplayFeature: Bool],
                                 available: Set<DisplayFeature>) -> [DisplayFeature: Bool] {
        var result = raw
        var stack: [DisplayFeature] = [feature]
        var visited: Set<DisplayFeature> = []
        while let f = stack.popLast() {
            guard visited.insert(f).inserted else { continue }
            result[f] = true
            let s = spec(f)
            stack.append(contentsOf: s.requiresAll)
            if !s.requiresAny.isEmpty, !s.requiresAny.contains(where: { rawState($0, in: result) }) {
                let pick = s.requiresAny.first { available.contains($0) } ?? s.requiresAny[0]
                stack.append(pick)
            }
        }
        return result
    }

    /// Features that stop being effective if `feature` is turned off (for the
    /// "Also turns off: …" notice).
    package static func dependents(of feature: DisplayFeature, effective: Set<DisplayFeature>) -> Set<DisplayFeature> {
        var raw: [DisplayFeature: Bool] = [:]
        for f in DisplayFeature.allCases { raw[f] = effective.contains(f) }
        raw[feature] = false
        let after = resolve(raw: raw, killSwitches: [], safeMode: false, unavailable: [], panicLatch: false)
        return effective.subtracting(after).subtracting([feature])
    }

    // MARK: Services

    /// Direct dependencies between services.
    package static func dependencies(_ service: DisplayServiceID) -> Set<DisplayServiceID> {
        switch service {
        case .registry, .sessionGate, .spawner: return []
        case .guardProcess: return [.registry, .spawner]
        case .transactions: return [.registry, .sessionGate, .guardProcess]
        case .appleBrightness, .overlays, .osd, .colorSync, .monitorPanel, .mediaKeys: return [.registry]
        case .ddc, .gamma, .capture: return [.registry, .sessionGate]
        case .edr: return [.registry, .overlays, .gamma]
        case .brightness: return [.registry, .sessionGate]
        case .virtualHosts: return [.registry, .guardProcess, .spawner]
        }
    }

    /// Activation order: every service comes after its dependencies (tested).
    package static let activationOrder: [DisplayServiceID] = [
        .registry, .sessionGate, .spawner, .guardProcess, .transactions,
        .appleBrightness, .ddc, .gamma, .overlays, .edr, .brightness,
        .osd, .colorSync, .monitorPanel, .mediaKeys, .virtualHosts, .capture,
    ]

    /// Services needed by an effective feature set, closed over dependencies.
    package static func requiredServices(effective: Set<DisplayFeature>) -> Set<DisplayServiceID> {
        var result: Set<DisplayServiceID> = []
        var stack = effective.flatMap { spec($0).uses }
        while let s = stack.popLast() {
            guard result.insert(s).inserted else { continue }
            stack.append(contentsOf: dependencies(s))
        }
        return result
    }
}

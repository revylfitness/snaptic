import Foundation
import SnapticKit
import SnapticShims

// Every private display symbol goes through this file (owner: B; lint rule 11). PLAN §1,
// R5.4: resolved at runtime (dlopen/dlsym with the SLS↔CGS alias, NSClassFromString),
// encoding-checked, behind kill switches `Displays.disable.symbol.<name>`, fail-closed.

/// An open id for a private symbol. Teams declare their own in their own files:
/// `extension PrivateSymbol { static let dsGetBrightness = PrivateSymbol(function: "DisplayServicesGetBrightness",
///  framework: "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", features: [.brightnessApple]) }`
struct PrivateSymbol: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case function(name: String, framework: String)
        case objcClass(String)
    }
    let kind: Kind
    /// Features that can't work without this symbol.
    let features: Set<DisplayFeature>
    /// For classes: the framework to load first (nil = already loaded, e.g. CoreGraphics).
    let framework: String?

    init(function name: String, framework: String, features: Set<DisplayFeature>) {
        kind = .function(name: name, framework: framework)
        self.features = features
        self.framework = framework
    }

    init(objcClass name: String, features: Set<DisplayFeature>) {
        kind = .objcClass(name)
        self.features = features
        framework = nil
    }

    init(objcClass name: String, framework: String, features: Set<DisplayFeature>) {
        kind = .objcClass(name)
        self.features = features
        self.framework = framework
    }

    /// The symbol's own name (function or class).
    var name: String {
        switch kind {
        case .function(let name, _): return name
        case .objcClass(let name): return name
        }
    }

    /// Persistent-domain Bool key that turns this symbol off.
    var killSwitchKey: String { "Displays.disable.symbol.\(name)" }
}

// Symbols team B's services use.
extension PrivateSymbol {
    static let coreGraphicsPath = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    static let coreDisplayPath = "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
    static let monitorPanelPath = "/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel"

    static let cgsConfigureDisplayEnabled = PrivateSymbol(function: "CGSConfigureDisplayEnabled",
                                                          framework: coreGraphicsPath, features: [.disconnect])
    static let cgsIsHDRSupported = PrivateSymbol(function: "CGSIsHDRSupported", framework: coreGraphicsPath, features: [])
    static let cgsIsHDREnabled = PrivateSymbol(function: "CGSIsHDREnabled", framework: coreGraphicsPath, features: [])
    static let cgsGetNumberOfDisplayModes = PrivateSymbol(function: "CGSGetNumberOfDisplayModes",
                                                          framework: coreGraphicsPath, features: [.hiddenModes])
    static let cgsGetDisplayModeDescription = PrivateSymbol(function: "CGSGetDisplayModeDescriptionOfLength",
                                                            framework: coreGraphicsPath, features: [.hiddenModes])
    static let cgsGetCurrentDisplayMode = PrivateSymbol(function: "CGSGetCurrentDisplayMode",
                                                        framework: coreGraphicsPath, features: [.hiddenModes])
    static let cgsConfigureDisplayMode = PrivateSymbol(function: "CGSConfigureDisplayMode",
                                                       framework: coreGraphicsPath, features: [.hiddenModes])
    static let coreDisplayInfo = PrivateSymbol(function: "CoreDisplay_DisplayCreateInfoDictionary",
                                               framework: coreDisplayPath, features: [])
    static let mpDisplay = PrivateSymbol(objcClass: "MPDisplay", framework: monitorPanelPath,
                                         features: [.rotation, .underscan, .hdrToggle, .applePresets])
}

/// Nonisolated resolution, for the guard helper (which has no kill switches or defaults)
/// and for PrivateDisplayAPI itself.
enum PrivateSymbolResolver {
    private static let lock = NSLock()
    private static var handles: [String: UnsafeMutableRawPointer] = [:]

    /// The function pointer, trying the framework, then the global namespace, then the
    /// SLS↔CGS alias. Nil when missing.
    static func resolve(function name: String, framework: String) -> UnsafeMutableRawPointer? {
        let handle = open(framework)
        let aliases = [name] + alias(of: name)
        for candidate in aliases {
            if let handle, let p = dlsym(handle, candidate) { return p }
            if let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), candidate) { return p }   // RTLD_DEFAULT
        }
        return nil
    }

    /// Loads `framework` (if given) and looks the class up.
    static func resolveClass(_ name: String, framework: String?) -> AnyClass? {
        if let framework { _ = open(framework) }
        return NSClassFromString(name)
    }

    private static func open(_ path: String) -> UnsafeMutableRawPointer? {
        lock.lock()
        defer { lock.unlock() }
        if let h = handles[path] { return h }
        guard let h = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        handles[path] = h
        return h
    }

    private static func alias(of name: String) -> [String] {
        if name.hasPrefix("CGS") { return ["SLS" + name.dropFirst(3)] }
        if name.hasPrefix("SLS") { return ["CGS" + name.dropFirst(3)] }
        return []
    }

    // MARK: MonitorPanel verification (shared by app and guard)

    /// Expected MPDisplay encodings (arm64 class-dumps; BOOL `B`≡`c` handled by KitEncoding).
    static let monitorPanelRequirements: [String: [KitEncoding.Requirement]] = [
        "core": [KitEncoding.Requirement("initWithCGSDisplayID:", "@20@0:8i16")],
        "rotation": [KitEncoding.Requirement("canChangeOrientation", "B16@0:8"),
                     KitEncoding.Requirement("orientation", "i16@0:8"),
                     KitEncoding.Requirement("setOrientation:", "v20@0:8i16")],
        "hdr": [KitEncoding.Requirement("hasHDRModes", "B16@0:8"), KitEncoding.Requirement("preferHDRModes", "B16@0:8"),
                KitEncoding.Requirement("setPreferHDRModes:", "v20@0:8B16")],
        "underscan": [KitEncoding.Requirement("underscan", "f16@0:8"), KitEncoding.Requirement("setUnderscan:", "v20@0:8f16")],
        "presets": [KitEncoding.Requirement("presets", "@16@0:8"), KitEncoding.Requirement("activePreset", "@16@0:8"),
                    KitEncoding.Requirement("setActivePreset:", "v24@0:8@16")],
    ]

    /// Loads MonitorPanel, checks every group's encodings and marks the good ones in the shim.
    /// Returns the groups that verified ("core" must, or nothing works).
    @discardableResult
    static func verifyMonitorPanel() -> Set<String> {
        guard resolveClass("MPDisplay", framework: PrivateSymbol.monitorPanelPath) != nil else { return [] }
        var good: Set<String> = []
        for (group, reqs) in monitorPanelRequirements {
            if KitEncoding.failures(reqs, actual: { SNMonitorPanel.rawEncoding(selector: $0) }).isEmpty {
                SNMonitorPanel.markVerified(reqs.map(\.selector))
                good.insert(group)
            }
        }
        return good.contains("core") ? good : []
    }
}

@MainActor final class PrivateDisplayAPI: DiagnosticsContributor {
    enum State: Equatable {
        case available
        case missing
        case killed
        case encodingMismatch(String)
    }

    private struct Entry {
        let symbol: PrivateSymbol
        var state: State
        var pointer: UnsafeMutableRawPointer?
        var objcClass: AnyClass?
    }

    private var entries: [PrivateSymbol: Entry] = [:]
    private var order: [PrivateSymbol] = []
    /// MonitorPanel groups that verified (rotation, hdr, underscan, presets).
    private(set) var monitorPanelGroups: Set<String> = []

    init() {}

    /// Called once by DisplaysModule.init with every controller's and service's symbols.
    /// Kill switches are read once here (persistent domain only).
    func register(_ symbols: [PrivateSymbol]) {
        let defaults = UserDefaults.standard.persistentDomain(forName: ConfigStore<DisplaysConfig>.persistentDomainName) ?? [:]
        for symbol in symbols where entries[symbol] == nil {
            order.append(symbol)
            if (defaults[symbol.killSwitchKey] as? Bool) == true {
                entries[symbol] = Entry(symbol: symbol, state: .killed, pointer: nil, objcClass: nil)
                EventLog.shared.record(.privateAPI, "\(symbol.name): turned off by a defaults setting")
                continue
            }
            switch symbol.kind {
            case .function(let name, let framework):
                let p = PrivateSymbolResolver.resolve(function: name, framework: framework)
                entries[symbol] = Entry(symbol: symbol, state: p == nil ? .missing : .available, pointer: p, objcClass: nil)
            case .objcClass(let name):
                let cls = PrivateSymbolResolver.resolveClass(name, framework: symbol.framework)
                var state: State = cls == nil ? .missing : .available
                if cls != nil && name == "MPDisplay" {
                    monitorPanelGroups = PrivateSymbolResolver.verifyMonitorPanel()
                    if monitorPanelGroups.isEmpty { state = .encodingMismatch("initWithCGSDisplayID:") }
                }
                entries[symbol] = Entry(symbol: symbol, state: state, pointer: nil, objcClass: cls)
            }
            if entries[symbol]?.state != .available {
                EventLog.shared.record(.privateAPI, "\(symbol.name): unavailable")
            }
        }
    }

    func state(of symbol: PrivateSymbol) -> State { entries[symbol]?.state ?? .missing }

    func isUsable(_ symbol: PrivateSymbol) -> Bool { state(of: symbol) == .available }

    func availability(of symbol: PrivateSymbol) -> FeatureAvailability {
        switch state(of: symbol) {
        case .available: return .available
        case .missing: return .unavailable(L("Not supported on this Mac or macOS version"))
        case .killed: return .unavailable(L("Turned off by a defaults setting"))
        case .encodingMismatch: return .unavailable(L("This macOS version changed a system interface Snaptic needs"))
        }
    }

    /// Resolves a C function as a `@convention(c)` type; nil if missing or kill-switched.
    func function<T>(_ symbol: PrivateSymbol, as type: T.Type) -> T? {
        guard let entry = entries[symbol], entry.state == .available, let p = entry.pointer else { return nil }
        guard MemoryLayout<T>.size == MemoryLayout<UnsafeMutableRawPointer>.size else { return nil }
        return unsafeBitCast(p, to: type)
    }

    /// The raw pointer (for shims that take function pointers).
    func pointer(_ symbol: PrivateSymbol) -> UnsafeRawPointer? {
        guard let entry = entries[symbol], entry.state == .available, let p = entry.pointer else { return nil }
        return UnsafeRawPointer(p)
    }

    func objcClass(_ symbol: PrivateSymbol) -> AnyClass? {
        guard let entry = entries[symbol], entry.state == .available else { return nil }
        return entry.objcClass
    }

    /// Whether a MonitorPanel capability verified ("rotation", "hdr", "underscan", "presets").
    func monitorPanelSupports(_ group: String) -> Bool { isUsable(.mpDisplay) && monitorPanelGroups.contains(group) }

    /// Features whose probed private symbols are missing, with a user-facing reason.
    func unavailableFeatures() -> [DisplayFeature: String] {
        var result: [DisplayFeature: String] = [:]
        for symbol in order {
            guard case .unavailable(let reason) = availability(of: symbol) else { continue }
            for f in symbol.features where result[f] == nil { result[f] = reason }
        }
        // MonitorPanel groups that failed their own encoding check.
        if isUsable(.mpDisplay) {
            let groups: [(String, DisplayFeature)] = [("rotation", .rotation), ("hdr", .hdrToggle),
                                                      ("underscan", .underscan), ("presets", .applePresets)]
            for (group, feature) in groups where !monitorPanelGroups.contains(group) && result[feature] == nil {
                result[feature] = L("This macOS version changed a system interface Snaptic needs")
            }
        }
        return result
    }

    func diagnostics() -> [(String, String)] { diagnosticsRows() }

    /// Diagnostics rows: symbol name and state (no addresses).
    func diagnosticsRows() -> [(String, String)] {
        order.map { s in
            let text: String
            switch state(of: s) {
            case .available: text = "available"
            case .missing: text = "missing"
            case .killed: text = "kill switch"
            case .encodingMismatch(let sel): text = "encoding mismatch (\(sel))"
            }
            return (s.name, text)
        } + [("MonitorPanel groups", monitorPanelGroups.sorted().joined(separator: ", "))]
    }
}

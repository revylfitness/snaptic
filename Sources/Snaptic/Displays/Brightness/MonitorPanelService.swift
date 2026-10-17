import AppKit
import Combine
import SnapticKit
import SnapticShims

/// An Apple display preset (Pro Display XDR, Studio Display, XDR built-ins).
struct AppleDisplayPreset: Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let isActive: Bool
    /// The preset fixes brightness (Apple native brightness stops working while it's active).
    let fixesBrightness: Bool
}

/// Wraps B's SNMonitorPanel shim for Apple presets and panel properties (PLAN §13 note).
/// The shim's class methods are called by selector so this file builds before (and
/// lights up after) B lands them. Agreed selectors (all class methods, NSNumber in/out):
///   presetsForDisplayNumber:(NSNumber *)  → NSArray<NSDictionary *> {name, id, active, fixedBrightness}
///   activatePresetWithRequest:(NSDictionary *){display, id} → NSNumber(BOOL)
///   rotationForDisplayNumber:(NSNumber *) → NSNumber(int degrees)
///   underscanForDisplayNumber:(NSNumber *) → NSNumber(double 0…1)
///   hdrEnabledForDisplayNumber:(NSNumber *) → NSNumber(BOOL)
@MainActor final class MonitorPanelService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .monitorPanel }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) { self.context = context }
    func deactivate() { context = nil }

    private static let presetsSelector = Selector(("presetsForDisplayNumber:"))
    private static let activateSelector = Selector(("activatePresetWithRequest:"))
    private static let rotationSelector = Selector(("rotationForDisplayNumber:"))
    private static let underscanSelector = Selector(("underscanForDisplayNumber:"))
    private static let hdrSelector = Selector(("hdrEnabledForDisplayNumber:"))

    private static var shim: AnyObject { SNMonitorPanel.self as AnyObject }

    private static func call(_ selector: Selector, _ argument: Any) -> Any? {
        guard SNMonitorPanel.isAvailable(), shim.responds(to: selector) else { return nil }
        return shim.perform(selector, with: argument)?.takeUnretainedValue()
    }

    var isAvailable: Bool { SNMonitorPanel.isAvailable() && Self.shim.responds(to: Self.presetsSelector) }

    private func hardwareID(_ key: DisplayKey) -> UInt32? { context?.registry.info(for: key)?.hardwareID }

    func presetList(for key: DisplayKey) -> [AppleDisplayPreset] {
        guard let id = hardwareID(key),
              let list = Self.call(Self.presetsSelector, NSNumber(value: id)) as? [[String: Any]] else { return [] }
        return list.prefix(64).compactMap { entry in
            guard let name = entry["name"] as? String, let pid = (entry["id"] as? NSNumber)?.intValue else { return nil }
            return AppleDisplayPreset(id: pid, name: TextSanitizer.clean(name, maxScalars: 64),
                                      isActive: (entry["active"] as? NSNumber)?.boolValue ?? false,
                                      fixesBrightness: (entry["fixedBrightness"] as? NSNumber)?.boolValue ?? false)
        }
    }

    func presets(for key: DisplayKey) -> [String] { presetList(for: key).map(\.name) }

    func activePreset(for key: DisplayKey) -> String? { presetList(for: key).first { $0.isActive }?.name }

    func applyPreset(_ name: String, for key: DisplayKey) -> Bool {
        guard let preset = presetList(for: key).first(where: { $0.name == name }) else { return false }
        return applyPreset(id: preset.id, for: key)
    }

    func applyPreset(id: Int, for key: DisplayKey) -> Bool {
        guard let display = hardwareID(key) else { return false }
        let request: NSDictionary = ["display": NSNumber(value: display), "id": NSNumber(value: id)]
        let ok = (Self.call(Self.activateSelector, request) as? NSNumber)?.boolValue ?? false
        if ok { EventLog.shared.record(.brightness, "Apple display preset changed") }
        return ok
    }

    func rotation(of key: DisplayKey) -> Int? {
        guard let id = hardwareID(key) else { return nil }
        return (Self.call(Self.rotationSelector, NSNumber(value: id)) as? NSNumber)?.intValue
    }

    func underscan(of key: DisplayKey) -> Double? {
        guard let id = hardwareID(key) else { return nil }
        return (Self.call(Self.underscanSelector, NSNumber(value: id)) as? NSNumber)?.doubleValue
    }

    func hdrEnabled(of key: DisplayKey) -> Bool? {
        guard let id = hardwareID(key) else { return nil }
        return (Self.call(Self.hdrSelector, NSNumber(value: id)) as? NSNumber)?.boolValue
    }
}

import AppKit
import Combine
import SnapticKit
import SnapticShims

/// An Apple display preset (Pro Display XDR, Studio Display, XDR built-ins).
struct AppleDisplayPreset: Hashable, Identifiable, Sendable {
    /// Index in the display's preset list (stable while the list is unchanged).
    let id: Int
    let name: String
    let isActive: Bool
}

/// Wraps B's `SNMonitorPanel` shim for Apple presets and panel properties (PLAN §13 note).
/// Every call goes through the shim, which refuses selectors whose encodings
/// `PrivateDisplayAPI.verifyMonitorPanel()` didn't verify; the group check here keeps
/// the UI from offering what can't work. D's `PanelPropsController` reads rotation,
/// underscan and HDR here; changes go through transactions (B's `CGConfig`).
@MainActor final class MonitorPanelService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .monitorPanel }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) { self.context = context }
    func deactivate() { context = nil }

    private func supports(_ group: String) -> Bool {
        SNMonitorPanel.isAvailable() && (context?.privateAPI.monitorPanelSupports(group) ?? false)
    }

    /// Presets can be listed and selected on this Mac.
    var isAvailable: Bool { supports("presets") }

    private func hardwareID(_ key: DisplayKey) -> UInt32? { context?.registry.info(for: key)?.hardwareID }

    func presetList(for key: DisplayKey) -> [AppleDisplayPreset] {
        guard supports("presets"), let id = hardwareID(key), let names = SNMonitorPanel.presetNames(display: id) else { return [] }
        let active = SNMonitorPanel.activePresetName(display: id)
        return names.prefix(64).enumerated().map { index, name in
            AppleDisplayPreset(id: index, name: TextSanitizer.clean(name, maxScalars: 64), isActive: name == active)
        }
    }

    func presets(for key: DisplayKey) -> [String] { presetList(for: key).map(\.name) }

    func activePreset(for key: DisplayKey) -> String? {
        guard supports("presets"), let id = hardwareID(key), let name = SNMonitorPanel.activePresetName(display: id) else {
            return nil
        }
        return TextSanitizer.clean(name, maxScalars: 64)
    }

    /// Selects a preset by its (raw) name as the shim lists it.
    func applyPreset(_ name: String, for key: DisplayKey) -> Bool {
        guard supports("presets"), let id = hardwareID(key) else { return false }
        // Match against the raw names; the list we show is sanitized.
        guard let raw = SNMonitorPanel.presetNames(display: id)?.first(where: { TextSanitizer.clean($0, maxScalars: 64) == name }) else {
            return false
        }
        let ok = SNMonitorPanel.setActivePreset(named: raw, display: id)
        if ok { EventLog.shared.record(.brightness, "Apple display preset changed") }
        return ok
    }

    func applyPreset(id index: Int, for key: DisplayKey) -> Bool {
        guard supports("presets"), let id = hardwareID(key), let names = SNMonitorPanel.presetNames(display: id),
              names.indices.contains(index) else { return false }
        let ok = SNMonitorPanel.setActivePreset(named: names[index], display: id)
        if ok { EventLog.shared.record(.brightness, "Apple display preset changed") }
        return ok
    }

    func rotation(of key: DisplayKey) -> Int? {
        guard supports("rotation"), let id = hardwareID(key) else { return nil }
        return SNMonitorPanel.orientation(display: id)?.intValue
    }

    func underscan(of key: DisplayKey) -> Double? {
        guard supports("underscan"), let id = hardwareID(key) else { return nil }
        return SNMonitorPanel.underscan(display: id)?.doubleValue
    }

    func hasHDRModes(_ key: DisplayKey) -> Bool {
        guard supports("hdr"), let id = hardwareID(key) else { return false }
        return SNMonitorPanel.hasHDRModes(display: id)?.boolValue ?? false
    }

    func hdrEnabled(of key: DisplayKey) -> Bool? {
        guard supports("hdr"), let id = hardwareID(key) else { return nil }
        return SNMonitorPanel.prefersHDR(display: id)?.boolValue
    }
}

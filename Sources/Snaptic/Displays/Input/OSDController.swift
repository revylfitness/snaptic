import AppKit
import SnapticKit
import SnapticShims

/// The OSD (PLAN §8.3) and its broadcast (§4.10(2)). Turns the presenter's HUD and
/// broadcast on and off; the presenter reads style, position and target from settings.
@MainActor final class OSDController: DisplayFeatureController, DiagnosticsContributor, SessionParticipant {
    static var id: DisplayControllerID { .osd }
    static var privateSymbols: [PrivateSymbol] { [] }

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .available }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        context.diagnostics.register(self, section: L("On-screen display"), lifetime: lifetime)
        context.registerSession(self, lifetime: lifetime)
        context.osd.controller = self
        apply(effective)
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) { apply(effective) }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.keys.osdStyle != new.keys.osdStyle || old.keys.osdPosition != new.keys.osdPosition { context?.osd.hideAll() }
    }

    func stop() {
        if let context {
            if context.osd.controller === self { context.osd.controller = nil }
            context.osd.isEnabled = true
            context.osd.broadcastEnabled = false
            context.osd.hideAll()
        }
        lifetime = nil
        context = nil
    }

    private func apply(_ effective: Set<DisplayFeature>) {
        guard let context else { return }
        context.osd.isEnabled = effective.contains(.osd)
        // Both features use the OSD service (FeatureGraph), so the presenter is active and
        // has its context whenever either is on.
        context.osd.broadcastEnabled = effective.contains(.osdBroadcast)
        if !effective.contains(.osd) { context.osd.hideAll() }
    }

    func sessionDidPause() { context?.osd.hideAll() }
    func sessionDidResume() {}

    /// Shows a sample HUD with the current settings (OSD page "Preview").
    func preview() {
        guard let context, let display = context.registry.displays.first(where: \.isMain) else { return }
        context.osd.show(.brightness, value: context.brightness.value(for: display.key) ?? 0.6, max: 1, on: display.desktopID,
                         detail: L("Preview"))
    }

    var nativeAvailable: Bool { SNOSD.isAvailable() }

    func diagnostics() -> [(String, String)] {
        guard let context else { return [] }
        let keys = context.config.value.keys
        let os = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return [
            ("HUD", context.osd.isEnabled ? (keys.osdNative && SNOSD.isAvailable() ? "system OSD" : "Snaptic HUD") : "off"),
            ("Style", keys.effectiveOSDStyle(osMajor: os).rawValue),
            ("Position", keys.effectiveOSDPosition(osMajor: os).rawValue),
            ("Target", keys.osdTarget.rawValue),
            ("Broadcast", context.osd.broadcastEnabled ? "on" : "off"),
        ]
    }
}

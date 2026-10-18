import AppKit
import Combine
import SnapticKit

/// Menu-bar strip (a black band behind the menu bar, hiding the notch) and rounded corner
/// overlays, per display (PLAN §2.1 `menuBarOverlays`, parity §5.7). Panic removes them.
@MainActor final class MenuBarOverlaysController: DisplayFeatureController, PanicParticipant, DiagnosticsContributor {
    static var id: DisplayControllerID { .menuBarOverlays }
    static var privateSymbols: [PrivateSymbol] { [] }

    static let stripAction = DisplayActionID(rawValue: "c.menuBarStrip")
    static var observedSections: Set<DisplaysConfigSection> { [.perDisplayColor] }

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private var sinks: [AnyCancellable] = []
    private var strips: [DisplayKey: OverlayToken] = [:]
    private var corners: [DisplayKey: OverlayToken] = [:]
    /// After a panic, overlays stay off until the user changes a setting.
    private var heldByPanic = false
    private var menuItems: ColorMenuItems?

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .available }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        heldByPanic = false
        context.registerPanic(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Menu-bar overlays"), lifetime: lifetime)
        let items = ColorMenuItems(context: context, part: .menuBarOverlays, owner: self)
        menuItems = items
        context.menus.register(items, lifetime: lifetime)
        context.actions.register(Action(id: Self.stripAction, title: L("Toggle Menu-Bar Strip"), feature: .menuBarOverlays,
                                        cliAllowed: false) { [weak self] target in self?.toggleStrip(target) }, lifetime: lifetime)
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.sync(rebuild: true) } }
            .store(in: &sinks)
        sync(rebuild: false)
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {}

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.perDisplay.values.mapValues(\.color) != new.perDisplay.values.mapValues(\.color) {
            heldByPanic = false
            sync(rebuild: true)
            context?.runtime.revision(.menuBarOverlays).bump()
            context?.requestMenuRebuild()
        }
    }

    func stop() {
        sinks.removeAll()
        removeAll()
        menuItems = nil
        lifetime = nil
        context = nil
    }

    func panicRestore() {
        heldByPanic = true
        removeAll()
        context?.runtime.revision(.menuBarOverlays).bump()
    }

    private func removeAll() {
        guard let context else { return }
        for token in strips.values { context.overlays.remove(token) }
        for token in corners.values { context.overlays.remove(token) }
        strips.removeAll()
        corners.removeAll()
    }

    /// Adds, updates and removes overlays to match settings. `rebuild` re-creates them
    /// (display ids or geometry may have changed).
    private func sync(rebuild: Bool) {
        guard let context else { return }
        if rebuild { removeAll() }
        guard !heldByPanic else { return }
        let config = context.config.value
        let online = context.registry.displays.filter { $0.isOnline && $0.isActive && $0.mirrorOf == nil }
        let keys = Set(online.map(\.key))
        for (key, token) in strips where !keys.contains(key) {
            context.overlays.remove(token)
            strips[key] = nil
        }
        for (key, token) in corners where !keys.contains(key) {
            context.overlays.remove(token)
            corners[key] = nil
        }
        for display in online {
            let per = config.perDisplay[display.key]?.color ?? PerDisplayColor()
            if per.menuBarStrip {
                if strips[display.key] == nil, let token = context.overlays.add(.menuBarStrip, on: display.desktopID) {
                    strips[display.key] = token
                }
            } else if let token = strips.removeValue(forKey: display.key) {
                context.overlays.remove(token)
            }
            if per.hasRoundedCorners {
                let token = corners[display.key] ?? context.overlays.add(.roundedCorners, on: display.desktopID)
                if let token {
                    corners[display.key] = token
                    let view = (context.overlays.contentView(for: token) as? RoundedCornersView) ?? RoundedCornersView()
                    view.top = per.cornerRadiusTop
                    view.bottom = per.cornerRadiusBottom
                    if context.overlays.contentView(for: token) !== view { context.overlays.setContentView(view, for: token) }
                    view.needsDisplay = true
                }
            } else if let token = corners.removeValue(forKey: display.key) {
                context.overlays.remove(token)
            }
        }
    }

    func toggleStrip(_ target: DisplayTarget) {
        guard let context else { return }
        for display in DisplayTargets.resolve(target, context) {
            PerDisplayEdit.update(context, display.key) { $0.color.menuBarStrip.toggle() }
        }
    }

    // MARK: Menu


    func diagnostics() -> [(String, String)] {
        [("Strips", String(strips.count)), ("Rounded corners", String(corners.count)), ("Held by panic", heldByPanic ? "yes" : "no")]
    }
}

/// Black corner masks; radii are fractions of the shorter side (0…3%).
final class RoundedCornersView: NSView {
    var top: Double = 0
    var bottom: Double = 0

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        NSColor.black.setFill()
        let corners: [(Double, NSPoint, Bool)] = [
            (top, NSPoint(x: bounds.minX, y: bounds.maxY), true),
            (top, NSPoint(x: bounds.maxX, y: bounds.maxY), true),
            (bottom, NSPoint(x: bounds.minX, y: bounds.minY), false),
            (bottom, NSPoint(x: bounds.maxX, y: bounds.minY), false),
        ]
        for (fraction, corner, isTop) in corners where fraction > 0 {
            let r = CGFloat(min(0.03, fraction)) * side
            guard r >= 1 else { continue }
            let left = corner.x == bounds.minX
            let square = NSRect(x: left ? bounds.minX : bounds.maxX - r, y: isTop ? bounds.maxY - r : bounds.minY,
                                width: r, height: r)
            let center = NSPoint(x: left ? square.maxX : square.minX, y: isTop ? square.minY : square.maxY)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: square).addClip()
            let path = NSBezierPath(rect: square)
            path.appendOval(in: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            path.windingRule = .evenOdd
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

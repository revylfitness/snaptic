import AppKit
import CoreGraphics
import CryptoKit
import SnapticKit

// Shared helpers for the management controllers (owner: D): public-API mode reading,
// display lookup, transaction submission, menu items with closures, identity digests.

/// Seconds of uptime (pauses during sleep, like the guard's clock).
func managementUptime() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

/// Wall-clock seconds for UI-only timestamps.
func managementWallClock() -> Double { Date().timeIntervalSince1970 }

/// Safe Mode or panic latch: automatic management work is gated (R5.4).
@MainActor func managementAutomationPaused(_ ctx: DisplaysContext) -> Bool {
    ctx.safeMode.isActive || ctx.panic.isLatched
}

// MARK: Modes (public CoreGraphics only)

/// Desktop-usable public modes, through B's `DisplayModes` (the same lists the queue resolves
/// against). The CGS "Show all" list stays with B (`DisplayModes.hiddenList`).
enum ManagedModes {
    /// Desktop-usable modes including the HiDPI duplicates, largest first.
    static func modes(for displayID: UInt32) -> [DisplayModeDescriptor] {
        guard displayID != 0 else { return [] }
        return DisplayModes.list(displayID).filter(\.isUsableForDesktop)
            .sorted { ($0.ref.pointWidth, $0.ref.pointHeight, $0.ref.isHiDPI ? 1 : 0, $0.ref.refreshMilliHz)
                > ($1.ref.pointWidth, $1.ref.pointHeight, $1.ref.isHiDPI ? 1 : 0, $1.ref.refreshMilliHz) }
    }

    static func current(for displayID: UInt32) -> DisplayModeDescriptor? {
        displayID == 0 ? nil : DisplayModes.current(displayID)
    }

    /// The display's native mode (by the IOKit flag, else the largest pixel size).
    static func native(in modes: [DisplayModeDescriptor]) -> DisplayModeDescriptor? {
        modes.first(where: \.isNative) ?? modes.max { $0.ref.pixelWidth * $0.ref.pixelHeight < $1.ref.pixelWidth * $1.ref.pixelHeight }
    }

    /// Modes with the given display's native aspect ratio (±1%).
    static func nativeAspect(_ modes: [DisplayModeDescriptor]) -> [DisplayModeDescriptor] {
        guard let n = native(in: modes), n.ref.pixelHeight > 0 else { return modes }
        let aspect = Double(n.ref.pixelWidth) / Double(n.ref.pixelHeight)
        return modes.filter {
            $0.ref.pointHeight > 0 && abs(Double($0.ref.pointWidth) / Double($0.ref.pointHeight) - aspect) / aspect < 0.01
        }
    }
}

// MARK: Display lookup

@MainActor enum ManagedDisplays {
    /// Active presented displays first (main first), then the rest.
    static func all(_ ctx: DisplaysContext) -> [DisplayInfo] {
        ctx.registry.displays.sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            if a.isActive != b.isActive { return a.isActive }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    static func info(_ ctx: DisplaysContext, key: DisplayKey) -> DisplayInfo? {
        ctx.registry.displays.first { $0.key == key }
    }

    static func info(_ ctx: DisplaysContext, desktopID: UInt32) -> DisplayInfo? {
        ctx.registry.displays.first { $0.desktopID == desktopID } ?? ctx.registry.displays.first { $0.hardwareID == desktopID }
    }

    static func resolve(_ ctx: DisplaysContext, _ target: DisplayTarget) -> [DisplayInfo] {
        let displays = ctx.registry.displays
        switch target {
        case .display(let key): return displays.filter { $0.key == key }
        case .main: return displays.filter(\.isMain)
        case .all: return displays.filter(\.isActive)
        case .pointer:
            let p = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }), let id = screen.displayID,
               let info = info(ctx, desktopID: id) {
                return [info]
            }
            return displays.filter(\.isMain)
        }
    }

    /// CLI selectors through the lead's `DisplaySelectorResolver` (§11: Identify numbers,
    /// `id:N`, keys, `main`/`mouse`/`focus`/`all`, names). Either the displays, or the
    /// response to return (not found → `ControlExit.notFound`, ambiguous → `.usage`).
    static func cliSelect(_ ctx: DisplaysContext, _ selector: String) -> (displays: [DisplayInfo], error: ControlResponse?) {
        let r = DisplaySelectorResolver.resolveForCLI(selector, ctx)
        if let error = r.error { return ([], error) }
        guard let target = r.target else { return ([], notFound(selector)) }
        let list = resolve(ctx, target)
        return list.isEmpty ? ([], notFound(selector)) : (list, nil)
    }

    /// One display for verbs that take exactly one (`all` is refused as ambiguous).
    static func cliSelectOne(_ ctx: DisplaysContext, _ selector: String) -> (display: DisplayInfo?, error: ControlResponse?) {
        let r = cliSelect(ctx, selector)
        if let error = r.error { return (nil, error) }
        guard r.displays.count == 1 else {
            return (nil, .failure(ControlExit.usage, L("“\(selector)” matches several displays. Use its number or id:N.")))
        }
        return (r.displays[0], nil)
    }

    /// Keys for a selector, including displays that are online but not presented (for
    /// `connect`): `.display(key)` targets aren't filtered by the registry.
    static func cliKeys(_ ctx: DisplaysContext, _ selector: String) -> (keys: [DisplayKey], error: ControlResponse?) {
        let r = DisplaySelectorResolver.resolveForCLI(selector, ctx)
        if let error = r.error { return ([], error) }
        guard let target = r.target else { return ([], notFound(selector)) }
        if case .display(let key) = target { return ([key], nil) }
        let list = resolve(ctx, target).map(\.key)
        return list.isEmpty ? ([], notFound(selector)) : (list, nil)
    }

    private static func notFound(_ selector: String) -> ControlResponse {
        .failure(ControlExit.notFound, L("No display matches “\(selector)”. Try `snaptic list`."))
    }

    static func rect(_ d: DisplayInfo) -> ArrangeRect {
        ArrangeRect(x: Int32(d.bounds.origin.x.rounded()), y: Int32(d.bounds.origin.y.rounded()),
                    width: Int(d.bounds.width.rounded()), height: Int(d.bounds.height.rounded()))
    }

    static func onlyStronglyVisible(_ ctx: DisplaysContext) -> DisplayKey? {
        let strong = ctx.registry.displays.filter(\.isStronglyVisible)
        return strong.count == 1 ? strong[0].key : nil
    }
}

// MARK: Transactions

@MainActor enum ManagedTransactions {
    /// User-facing text for an outcome that didn't apply, or nil.
    static func message(_ outcome: TransactionOutcome) -> String? {
        switch outcome {
        case .applied, .kept: return nil
        case .reverted(let why): return why.isEmpty ? L("Change reverted") : why
        case .busy: return L("Another display change is in progress")
        case .failed(let why): return why.isEmpty ? L("The display change failed") : why
        case .refused(let violations):
            guard let first = violations.first else { return L("The display change was refused") }
            switch first {
            case .noVisibleDisplay: return L("Refused: no display would stay visible")
            case .noPanelHost: return L("Refused: the confirmation panel would have nowhere to show")
            case .dimToBlackWithoutOtherVisible: return L("Refused: dimming to black needs another visible display")
            case .mainNotVisible: return L("Refused: the main display must stay visible")
            case .guardNotArmed: return L("Safety helper unavailable")
            case .onlyDisplayUnsupported: return L("Refused on the only visible display")
            }
        }
    }

    /// Submits within `lifetime`; failures become a toast unless `quiet`.
    static func submit(_ ctx: DisplaysContext, _ request: TransactionRequest, lifetime: Lifetime, quiet: Bool = false,
                       completion: (@MainActor (TransactionOutcome) -> Void)? = nil) {
        lifetime.spawn { [weak ctx] in
            guard let ctx else { return }
            let outcome = await ctx.transactions.submit(request)
            if lifetime.isEnded { return }
            if !quiet, let text = message(outcome) { ctx.toasts.show(text, lifetime: lifetime) }
            EventLog.shared.record(.transaction, "\(request.label): \(outcomeName(outcome))")
            completion?(outcome)
        }
    }

    /// Awaits the outcome directly (CLI handlers).
    /// Automatic requests carry the running plan's id (the rate limiter counts plans). A
    /// restore refused because it would modeset the only strongly visible display becomes a
    /// prompt: "Restore '<name>'? Keep / Not now", re-submitted as a trial on Keep (R5.2).
    static func run(_ ctx: DisplaysContext, _ request: TransactionRequest) async -> TransactionOutcome {
        var request = request
        if request.automatic && request.planID == nil { request.planID = ctx.connectPlanner.currentPlanID }
        let outcome = await ctx.transactions.submit(request)
        EventLog.shared.record(.transaction, "\(request.label): \(outcomeName(outcome))")
        if request.risk == .restore, case .refused(let violations) = outcome,
           violations.contains(where: { if case .onlyDisplayUnsupported = $0 { return true }; return false }) {
            promptTrial(ctx, request)
        }
        return outcome
    }

    static func promptTrial(_ ctx: DisplaysContext, _ request: TransactionRequest) {
        let label = request.label
        let changes = request.changes
        let scope = request.finalScope
        weak var weakCtx = ctx
        ctx.toasts.show(L("Restore '\(label)'?"), action: ToastAction(title: L("Keep")) {
            guard let ctx = weakCtx else { return }
            submit(ctx, TransactionRequest(label: label, risk: .trial, changes: changes, finalScope: scope), lifetime: ctx.lifetime)
        }, lifetime: ctx.lifetime)
    }

    static func outcomeName(_ o: TransactionOutcome) -> String {
        switch o {
        case .applied: return "applied"
        case .kept: return "kept"
        case .reverted: return "reverted"
        case .refused: return "refused"
        case .busy: return "busy"
        case .failed: return "failed"
        }
    }

    static func response(_ outcome: TransactionOutcome, ok: String = "") -> ControlResponse {
        switch outcome {
        case .applied, .kept: return .ok(ok)
        case .refused: return .failure(ControlExit.refused, message(outcome) ?? "")
        // Declined in the confirmation panel or timed out: cancelled (§11).
        case .reverted: return .failure(ControlExit.cancelled, message(outcome) ?? "")
        case .busy, .failed: return .failure(ControlExit.unavailable, message(outcome) ?? "")
        }
    }
}

// MARK: Menu items

/// A menu item that runs a closure. Captures `DisplayKey`s, never display ids (R3C §5.6).
@MainActor final class ManagedMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, on: Bool = false, enabled: Bool = true, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        target = self
        state = on ? .on : .off
        isEnabled = enabled
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
    }

    @objc private func fire(_ sender: Any?) { handler() }

    /// A submenu holder item.
    static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach { menu.addItem($0) }
        item.submenu = menu
        return item
    }

    static func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

// MARK: Identity and digests

enum ManagedIdentity {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Layout identities for a display (R5.7). Tier 1 needs a serial number; tier 2 is the
    /// display UUID. Digests only: no serial ever leaves this function.
    static func identity(hardwareID: UInt32) -> LayoutDisplayIdentity {
        let serial = CGDisplaySerialNumber(hardwareID)
        var tier1: String?
        if serial != 0 {
            let seed = "t1:\(CGDisplayVendorNumber(hardwareID)):\(CGDisplayModelNumber(hardwareID)):\(serial)"
            tier1 = sha256Hex(Data(seed.utf8))
        }
        var tier2: String?
        if let uuid = CGDisplayCreateUUIDFromDisplayID(hardwareID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            tier2 = sha256Hex(Data(("t2:" + string).utf8))
        }
        return LayoutDisplayIdentity(tier1: tier1, tier2: tier2)
    }

    static var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }
}

// MARK: Hardware facts (static; safe in helpers too)

enum ManagedHardware {
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 4096 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    static var isAppleSilicon: Bool { sysctlInt("hw.optional.arm64") == 1 }
    static var modelIdentifier: String { sysctlString("hw.model") ?? "" }
    static var cpuBrand: String { sysctlString("machdep.cpu.brand_string") ?? "" }
    static var soc: SoCClass { SoCCaps.classify(cpuBrand: cpuBrand, isAppleSilicon: isAppleSilicon) }
    static var ram: UInt64 { ProcessInfo.processInfo.physicalMemory }
}

import AppKit
import SnapticKit

// Displays protocols and value types (lead-owned contract; R5.1: no classes here).

enum FeatureAvailability: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }
}

/// One controller per DisplayControllerID (PLAN §2.1). Constructed once by
/// DisplaysModule with init(); started when any of its features becomes effective.
@MainActor protocol DisplayFeatureController: AnyObject {
    init()
    static var id: DisplayControllerID { get }
    /// Private symbols this controller needs; registered once when the module is built.
    static var privateSymbols: [PrivateSymbol] { get }
    /// Static facts only: services may not be active yet.
    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability
    /// `lifetime` ends right after stop().
    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>)
    /// The effective subset changed but is still non-empty. Never a restart.
    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>)
    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig)
    /// Synchronous, idempotent, never shows UI.
    func stop()
}

/// Internal services, activated by reference count. Nonisolated services conform in
/// an extension with @MainActor witnesses (rule 14).
@MainActor protocol DisplayServiceLifecycle: AnyObject {
    static var serviceID: DisplayServiceID { get }
    static var privateSymbols: [PrivateSymbol] { get }
    /// `lifetime` ends right after deactivate(); register hooks on it, not on context.lifetime.
    func activate(_ context: DisplaysContext, lifetime: Lifetime)
    /// Synchronous, idempotent; reverts this service's system state.
    func deactivate()
}

@MainActor protocol PanicParticipant: AnyObject {
    func panicRestore()
}

@MainActor protocol SessionParticipant: AnyObject {
    func sessionDidPause()
    func sessionDidResume()
}

@MainActor protocol DiagnosticsContributor: AnyObject {
    func diagnostics() -> [(String, String)]
}

/// Where a menu item lives (PLAN §3.5).
enum MenuSlot: String, CaseIterable, Sendable {
    /// Inside each display's block.
    case display
    /// Switches in a display block's header row (DDC standby, disconnect).
    case header
    /// The Tools section (layouts, virtual screens, Match UI size, Connect All, Restore All…).
    case tools
    /// The right-click quick menu.
    case quick
}

struct DisplayMenuItemDescriptor {
    let id: DisplayMenuItemID
    let title: String
    let slot: MenuSlot
    let defaultVisibility: MenuItemVisibility
}

@MainActor protocol DisplayMenuContributor: AnyObject {
    var descriptors: [DisplayMenuItemDescriptor] { get }
    /// Items for the `.display` and `.header` slots of one display.
    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)]
    /// Items for the global `.tools` and `.quick` slots.
    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)]
}

/// A display as the rest of the app sees it. A Smart HiDPI pair is one entry:
/// `desktopID` is the virtual (desktop, overlays, OSD, PIP), `hardwareID` the
/// physical. Services that act on the panel (DDC, gamma, DisplayServices) take the
/// `DisplayKey` and resolve the hardware display themselves (PLAN A.2).
struct DisplayInfo: Identifiable, Equatable {
    var id: DisplayKey { key }
    let key: DisplayKey
    var desktopID: UInt32
    var hardwareID: UInt32
    var transport: Transport
    var name: String
    var isBuiltin: Bool
    var isOnline: Bool
    var isActive: Bool
    var isMain: Bool
    var mirrorOf: UInt32?
    var bounds: CGRect
    var rotation: Int
    var currentMode: DisplayModeDescriptor?
    var hdrSupported: Bool?
    var hdrEnabled: Bool?
    var notchInset: Double
    var physicalSizeMM: CGSize
    var edrPotential: Double
    var isSmartHiDPIPair: Bool
    var isStronglyVisible: Bool
    var isWeaklyVisible: Bool
}

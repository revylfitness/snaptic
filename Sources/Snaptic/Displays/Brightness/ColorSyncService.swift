import AppKit
import Combine
import SnapticKit
import SnapticShims

/// An installed ColorSync display profile.
struct ColorProfileInfo: Hashable, Identifiable, Sendable {
    let name: String
    let url: URL
    var id: URL { url }
}

/// ColorSync profiles per display (PLAN §6.5): list, current, set (nil → factory via
/// kCFNull), custom-profile detection for the safeguard, and the global ColorSync restore.
@MainActor final class ColorSyncService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .colorSync }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?
    /// The running system-colors controller, for the Color page.
    weak var systemColors: SystemColorsController?

    private var installed: [ColorProfileInfo] = []
    private var observer: NSObjectProtocol?
    private var refreshWork: DispatchWorkItem?
    /// Profiles Snaptic replaced this session, by display, so "Restore previous" works.
    private var previous: [DisplayKey: URL?] = [:]

    /// Called after display profiles changed (ours or anyone's).
    var onProfilesChanged: (@MainActor () -> Void)?

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        reloadInstalled()
        let name = Notification.Name(SNColorSync.displayProfilesNotificationName())
        observer = DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
    }

    func deactivate() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        refreshWork?.cancel()
        refreshWork = nil
        installed = []
        previous = [:]
        context = nil
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadInstalled()
                self?.onProfilesChanged?()
            }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func reloadInstalled() {
        installed = SNColorSync.installedDisplayProfiles().map { ColorProfileInfo(name: $0.name, url: $0.url) }
    }

    private func hardwareID(_ key: DisplayKey) -> UInt32? {
        context?.registry.info(for: key)?.hardwareID
    }

    // MARK: API

    func profiles(for key: DisplayKey) -> [String] { installed.map(\.name) }

    func installedProfiles() -> [ColorProfileInfo] { installed }

    func currentProfile(for key: DisplayKey) -> ColorProfileInfo? {
        guard let id = hardwareID(key), let p = SNColorSync.currentProfile(forDisplay: id) else { return nil }
        return ColorProfileInfo(name: p.name, url: p.url)
    }

    func hasCustomProfile(for key: DisplayKey) -> Bool {
        guard let id = hardwareID(key) else { return false }
        return SNColorSync.hasCustomProfile(forDisplay: id)
    }

    /// True when any online display uses a custom profile (the safeguard's trigger).
    var anyCustomProfile: Bool {
        guard let context else { return false }
        return context.registry.displays.contains { $0.isOnline && SNColorSync.hasCustomProfile(forDisplay: $0.hardwareID) }
    }

    /// Sets a display's profile; nil restores the factory profile.
    @discardableResult
    func setProfile(_ url: URL?, for key: DisplayKey) -> Bool {
        guard let id = hardwareID(key) else { return false }
        if previous[key] == nil {
            let current: URL? = hasCustomProfile(for: key) ? currentProfile(for: key)?.url : nil
            previous[key] = .some(current)
        }
        do {
            try SNColorSync.setProfile(url, forDisplay: id)
            EventLog.shared.record(.gamma, url == nil ? "Display profile reset to factory" : "Display profile changed")
            scheduleRefresh()
            return true
        } catch {
            EventLog.shared.record(.gamma, "Display profile change failed")
            return false
        }
    }

    var canRestorePrevious: Bool { !previous.isEmpty }

    /// Puts back the profiles Snaptic replaced this session.
    func restorePrevious(for key: DisplayKey) {
        guard let entry = previous.removeValue(forKey: key), let id = hardwareID(key) else { return }
        try? SNColorSync.setProfile(entry, forDisplay: id)
        scheduleRefresh()
    }

    func showInFinder(_ profile: ColorProfileInfo) {
        NSWorkspace.shared.activateFileViewerSelecting([profile.url])
    }

    func openInColorSyncUtility(_ profile: ColorProfileInfo) {
        let utility = URL(fileURLWithPath: "/System/Applications/Utilities/ColorSync Utility.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([profile.url], withApplicationAt: utility, configuration: config) { _, _ in }
    }

    /// ColorSync restore for every display (panic for gamma, color and XDR B).
    func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
    }
}

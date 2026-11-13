import SnapticKit
import AppKit
import ApplicationServices

struct WindowItem: Identifiable {
    static let firstSyntheticID: CGWindowID = CatalogWindow.firstSyntheticID

    /// What the shared rules read: inclusion, filters, the badge and the capture gate (`WindowCatalogRules`).
    var catalog: CatalogWindow
    let axElement: AXUIElement?
    let appName: String
    let bundleID: String?
    var title: String
    let icon: NSImage
    var frame: CGRect          // global coordinates, origin top-left of the main screen
    /// The (full, untruncated) title marks a private-browsing window.
    var hasPrivateMarker: Bool = false
    /// With "one window per app": how many windows the app has.
    var groupedCount: Int = 1

    var id: CGWindowID { catalog.id }
    var pid: pid_t { catalog.pid }
    var isMinimized: Bool {
        get { catalog.minimized }
        set { catalog.minimized = newValue }
    }
    var isHidden: Bool {
        get { catalog.hidden }
        set { catalog.hidden = newValue }
    }
    var isOnOtherSpace: Bool { catalog.onOtherSpace }
    var isFullscreen: Bool { catalog.fullscreen }
    var isWindowless: Bool { catalog.windowless }
    /// Never captured, and the title is hidden (password managers, private browsing).
    var isPrivate: Bool {
        get { catalog.isPrivate }
        set { catalog.isPrivate = newValue }
    }

    var hasRealWindowID: Bool { catalog.hasRealID }
    var displayTitle: String { title.isEmpty ? appName : title }
    var searchText: String { "\(appName) \(title)" }
    var aspectRatio: CGFloat { frame.height > 1 ? frame.width / frame.height : 1.6 }

    var badge: String? {
        switch WindowCatalogRules.switcherBadge(catalog, groupedCount: groupedCount) {
        case nil: return nil
        case .noWindows?: return L("No windows")
        case .windows(let count)?: return L("\(count) windows")
        case .minimized?: return L("Minimized")
        case .hidden?: return L("Hidden")
        case .otherSpace?: return L("Other Space")
        case .fullScreen?: return L("Full Screen")
        case .display(let name)?: return name
        }
    }
}

enum Screens {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Converts a top-left-origin (CG/AX) rect to Cocoa's bottom-left-origin space.
    static func cocoaRect(fromGlobal rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static var mouseScreen: NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// The frontmost app's top on-screen window, from window-server data so it
    /// never blocks on a slow app.
    static func frontWindowBounds(pid: pid_t?) -> CGRect? {
        guard let pid else { return nil }
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  // Hidden or zero-alpha windows don't count (macOS 27 keeps such
                  // windows around off screen).
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width > 1, bounds.height > 1 else { continue }
            return bounds
        }
        return nil
    }

    static func activeWindowScreen(frontPID: pid_t?) -> NSScreen {
        guard let bounds = frontWindowBounds(pid: frontPID) else { return mouseScreen }
        let rect = cocoaRect(fromGlobal: bounds)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? mouseScreen
    }

    /// Whether the app's front window fills a whole screen (full screen mode).
    /// On notched displays full-screen windows stop below the camera housing.
    static func isFullscreen(pid: pid_t?) -> Bool {
        guard let bounds = frontWindowBounds(pid: pid) else { return false }
        let rect = cocoaRect(fromGlobal: bounds)
        func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 2 }
        return NSScreen.screens.contains { screen in
            let f = screen.frame
            return close(rect.minX, f.minX) && close(rect.width, f.width) && close(rect.minY, f.minY)
                && (close(rect.height, f.height) || close(rect.height, f.height - screen.safeAreaInsets.top))
        }
    }
}

/// Window data read off the main thread through Accessibility.
struct RawWindow: @unchecked Sendable {
    let pid: pid_t
    let element: AXUIElement
    let windowID: CGWindowID?
    let kind: CatalogWindowKind
    let title: String
    let hasPrivateMarker: Bool
    let frame: CGRect
    let isMinimized: Bool
    let isFullscreen: Bool
}

struct AppSnapshot: Sendable {
    let pid: pid_t
}

/// Lets an AX element cross to a background task. AX calls are thread-safe.
struct AXRef: @unchecked Sendable {
    let element: AXUIElement
}

private struct EnumerationResult: @unchecked Sendable {
    let windows: [RawWindow]
    let focusedID: CGWindowID?
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buckets: [[RawWindow]]

    init(count: Int) { buckets = Array(repeating: [], count: count) }

    func set(_ index: Int, _ windows: [RawWindow]) {
        lock.lock()
        buckets[index] = windows
        lock.unlock()
    }

    var all: [RawWindow] {
        lock.lock()
        defer { lock.unlock() }
        return buckets.flatMap { $0 }
    }
}

struct WindowList {
    var items: [WindowItem]
    var focusedID: CGWindowID?
    /// The app the user is actually in (accounts for a switch Snaptic just made
    /// that macOS hasn't reported yet).
    var frontPID: pid_t?
}

/// Window-server facts gathered in one pass.
private struct ServerSnapshot {
    var zOrder: [CGWindowID: Int] = [:]          // layer-0 on-screen windows, front to back
    var onScreen = Set<CGWindowID>()             // on-screen windows of any layer
    var owner: [CGWindowID: pid_t] = [:]         // every window's owning process
    var layer: [CGWindowID: Int] = [:]           // every window's layer
}

fileprivate extension DockRect {
    /// A Cocoa-space rect (`Screens.cocoaRect(fromGlobal:)`).
    init(cocoa rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), w: Double(rect.width), h: Double(rect.height))
    }
}

/// Finds windows, keeps a most-recently-used order, and focuses / closes / minimizes them.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// Seconds Snaptic waits for any app to answer an Accessibility request.
    nonisolated static let axTimeout: Float = 0.15
    /// Limits that keep one misbehaving app from slowing the switcher.
    nonisolated static let maxWindowsPerApp = 100
    nonisolated static let maxTitleLength = 512
    nonisolated static let perAppBudget: Double = 0.5
    /// Listing as a whole gives up on slow apps after this long.
    nonisolated static let totalBudget: Double = 1.2

    private var mru: [CGWindowID] = []
    private var nextSyntheticID = WindowItem.firstSyntheticID
    fileprivate var lastFocused: (id: CGWindowID, pid: pid_t, at: Date)?
    private let focusTracker = FocusTracker()

    // MARK: Most-recently-used tracking

    private(set) var isStarted = false

    /// Idempotent. Seeds the most-recently-used order and starts focus tracking.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        // Seed with the current stacking order, front first.
        mru = serverSnapshot().zOrder.sorted { $0.value < $1.value }.map { $0.key }
        focusTracker.onFocus = { pid, id in
            let manager = WindowManager.shared
            // Only the app you're actually using counts; background apps
            // shuffling their own windows must not reorder the switcher.
            guard pid == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
            if let recent = manager.recentFocus {
                // Right after Snaptic switched, the app may still report its old
                // window for a moment; don't let that jump ahead of the target.
                if recent.pid == pid, recent.id != id { return }
                if recent.pid != pid { manager.lastFocused = nil }   // user moved on
            }
            manager.touch(id)
        }
        focusTracker.start()
    }

    /// Idempotent. Stops focus tracking (every AX observer is removed) and forgets the
    /// window order.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        focusTracker.stop()
        mru = []
        lastFocused = nil
    }

    /// Re-registers focus tracking for every app (after Accessibility is granted).
    func refreshFocusTracking() {
        guard isStarted else { return }
        focusTracker.observeAll()
    }

    func touch(_ id: CGWindowID) {
        guard id < WindowItem.firstSyntheticID else { return }
        mru.removeAll { $0 == id }
        mru.insert(id, at: 0)
        if mru.count > 500 { mru.removeLast(mru.count - 500) }
    }

    /// The window Snaptic focused in the last second, which macOS may not have
    /// reported as frontmost yet.
    fileprivate var recentFocus: (id: CGWindowID, pid: pid_t)? {
        guard let lastFocused, Date().timeIntervalSince(lastFocused.at) < 1 else { return nil }
        return (lastFocused.id, lastFocused.pid)
    }

    var effectiveFrontPID: pid_t? {
        recentFocus?.pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    // MARK: Listing

    func loadWindows(includeOtherSpaces: Bool, includeWindowless: Bool, excluded: [String]) async -> WindowList {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            WindowCatalogRules.listsApp(regular: $0.activationPolicy == .regular,
                                        isOwnProcess: $0.processIdentifier == ownPID,
                                        bundleID: $0.bundleIdentifier, excluded: excluded)
        }
        let snapshots = apps.map { AppSnapshot(pid: $0.processIdentifier) }
        let recent = recentFocus
        let frontPID = effectiveFrontPID
        let server = serverSnapshot()
        let owners = server.owner

        // Accessibility calls can block on a busy app, so they never run on the
        // main thread (which also services the keyboard event tap).
        let result = await Task.detached(priority: .userInitiated) { () -> EnumerationResult in
            EnumerationResult(
                windows: WindowManager.enumerate(snapshots, owners: owners),
                focusedID: recent?.id ?? frontPID.flatMap { WindowManager.focusedWindowID(pid: $0) }
            )
        }.value

        var byPID: [pid_t: NSRunningApplication] = [:]
        for app in apps { byPID[app.processIdentifier] = app }

        var items: [WindowItem] = []
        var seen = Set<CGWindowID>()
        var pidsWithWindows = Set<pid_t>()

        for raw in result.windows {
            guard let app = byPID[raw.pid] else { continue }
            let id = raw.windowID ?? makeSyntheticID()
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            var window = CatalogWindow(
                id: id,
                pid: raw.pid,
                hasTitle: !raw.title.isEmpty,
                minimized: raw.isMinimized,
                hidden: app.isHidden,
                onScreen: raw.windowID.map { server.onScreen.contains($0) } ?? true,
                fullscreen: raw.isFullscreen,
                layer: raw.windowID.flatMap { server.layer[$0] } ?? 0,
                bounds: DockRect(cocoa: Screens.cocoaRect(fromGlobal: raw.frame)),
                kind: raw.kind
            )
            let verdict = Self.include(&window)
            if verdict.appHasWindow { pidsWithWindows.insert(raw.pid) }
            guard verdict.included else { continue }
            items.append(WindowItem(
                catalog: window,
                axElement: raw.element,
                appName: Self.appName(app),
                bundleID: app.bundleIdentifier,
                title: raw.title,
                icon: app.icon ?? NSImage(),
                frame: raw.frame,
                hasPrivateMarker: raw.hasPrivateMarker
            ))
        }

        let elsewhere = windowsOnOtherSpaces(apps: apps, alreadySeen: seen)
        pidsWithWindows.formUnion(elsewhere.pids)
        if includeOtherSpaces {
            items += elsewhere.items
        }

        if includeWindowless {
            for app in apps where !pidsWithWindows.contains(app.processIdentifier) {
                items.append(WindowItem(
                    catalog: .windowless(id: makeSyntheticID(), pid: app.processIdentifier, hidden: app.isHidden),
                    axElement: nil,
                    appName: Self.appName(app),
                    bundleID: app.bundleIdentifier,
                    title: "",
                    icon: app.icon ?? NSImage(),
                    frame: .zero
                ))
            }
        }

        // The window you're in comes first, then most recently used; windows never focused while Snaptic was
        // running follow in stacking order; apps without windows go last.
        let order = WindowCatalogRules.switcherOrder(
            items.map(\.catalog),
            names: items.map { (app: $0.appName, title: $0.title) },
            focusedID: result.focusedID,
            mru: mru,
            zOrder: server.zOrder
        )
        return WindowList(items: order.map { items[$0] }, focusedID: result.focusedID, frontPID: frontPID)
    }

    /// The shared inclusion rule. The Spaces check is a window-server call, so it runs only for a window whose
    /// verdict turns on it (`WindowCatalogRules.needsSpaceCheck`), as the switcher always has.
    private static func include(_ window: inout CatalogWindow) -> CatalogVerdict {
        if WindowCatalogRules.needsSpaceCheck(window, appListed: true, options: .switcher) {
            window.spaceKnown = PrivateWindowAPI.isOnAnySpace(window.id)
        }
        return WindowCatalogRules.inclusion(window, appListed: true, options: .switcher)
    }

    nonisolated private static func enumerate(_ apps: [AppSnapshot], owners: [CGWindowID: pid_t]) -> [RawWindow] {
        let box = ResultBox(count: apps.count)
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(totalBudget * 1_000_000_000)
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            box.set(index, windows(of: apps[index], owners: owners, deadline: deadline))
        }
        return box.all
    }

    nonisolated private static func windows(of app: AppSnapshot, owners: [CGWindowID: pid_t], deadline: UInt64) -> [RawWindow] {
        let appDeadline = min(deadline, DispatchTime.now().uptimeNanoseconds + UInt64(perAppBudget * 1_000_000_000))
        // Checked before every request, so one slow app costs at most its budget.
        func outOfTime() -> Bool { DispatchTime.now().uptimeNanoseconds > appDeadline }

        let appElement = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(appElement, axTimeout)
        var result: [RawWindow] = []
        for window in AX.elements(appElement, kAXWindowsAttribute).prefix(maxWindowsPerApp) {
            if outOfTime() { break }
            AXUIElementSetMessagingTimeout(window, axTimeout)
            // The subrole and size parts of the shared inclusion rule, checked before the title is read.
            let kind = CatalogWindowKind(subrole: AX.string(window, kAXSubroleAttribute))
            guard WindowCatalogRules.kindLeftOut(kind, hasTitle: nil, options: .switcher) == nil,
                  !outOfTime() else { continue }
            let size = AX.size(window) ?? .zero
            guard WindowCatalogRules.sizeLeftOut(width: Double(size.width), height: Double(size.height),
                                                 minimum: CatalogInclusion.switcher.minAXSide) == nil,
                  !outOfTime() else { continue }

            let windowID = WindowCatalogRules.trustedWindowID(claimed: PrivateWindowAPI.windowID(of: window),
                                                              pid: app.pid, owners: owners)
            let fullTitle = outOfTime() ? "" : (AX.string(window, kAXTitleAttribute) ?? "")

            result.append(RawWindow(
                pid: app.pid,
                element: window,
                windowID: windowID,
                kind: kind,
                title: TextSanitizer.clean(fullTitle, maxScalars: maxTitleLength),
                hasPrivateMarker: TextSanitizer.hasPrivateMarker(fullTitle),
                frame: CGRect(origin: AX.position(window) ?? .zero, size: size),
                isMinimized: AX.bool(window, kAXMinimizedAttribute) ?? false,
                isFullscreen: AX.bool(window, "AXFullScreen") ?? false
            ))
        }
        return result
    }

    nonisolated private static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        guard let window = AX.element(app, kAXFocusedWindowAttribute) else { return nil }
        return PrivateWindowAPI.windowID(of: window)
    }

    private func serverSnapshot() -> ServerSnapshot {
        var snapshot = ServerSnapshot()
        let onScreenList = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        var position = 0
        for info in onScreenList {
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            snapshot.onScreen.insert(id)
            if (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 {
                snapshot.zOrder[id] = position
                position += 1
            }
        }
        let allList = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        for info in allList {
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }
            snapshot.owner[id] = pid
            if let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue { snapshot.layer[id] = layer }
        }
        return snapshot
    }

    /// Accessibility only reports windows on the current Space, so windows elsewhere
    /// are found through the window server list instead. Titles need Screen Recording.
    /// Also returns every app that has a real window somewhere, titled or not.
    private func windowsOnOtherSpaces(
        apps: [NSRunningApplication],
        alreadySeen: Set<CGWindowID>
    ) -> (items: [WindowItem], pids: Set<pid_t>) {
        var byPID: [pid_t: NSRunningApplication] = [:]
        for app in apps { byPID[app.processIdentifier] = app }

        let list = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        var items: [WindowItem] = []
        var pids = Set<pid_t>()
        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  !alreadySeen.contains(id),
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = byPID[pid],
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { continue }
            let rawTitle = info[kCGWindowName as String] as? String ?? ""
            // Layer, on-screen, size, alpha and the Spaces check (inactive native tabs and hidden helper windows
            // belong to no Space) are the shared inclusion rule's.
            var window = CatalogWindow(
                id: id,
                pid: pid,
                hasTitle: !rawTitle.isEmpty,
                hidden: app.isHidden,
                onScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                layer: layer,
                bounds: DockRect(cocoa: Screens.cocoaRect(fromGlobal: bounds)),
                hasAXElement: false,
                kind: .unknown,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            )
            let verdict = Self.include(&window)
            if verdict.appHasWindow { pids.insert(pid) }
            guard verdict.included else { continue }

            items.append(WindowItem(
                catalog: window,
                axElement: nil,
                appName: Self.appName(app),
                bundleID: app.bundleIdentifier,
                title: TextSanitizer.clean(rawTitle, maxScalars: Self.maxTitleLength),
                icon: app.icon ?? NSImage(),
                frame: bounds,
                hasPrivateMarker: TextSanitizer.hasPrivateMarker(rawTitle)
            ))
        }
        return (items, pids)
    }

    private static func appName(_ app: NSRunningApplication) -> String {
        let name = TextSanitizer.clean(app.localizedName ?? "", maxScalars: 64)
        return name.isEmpty ? L("App") : name
    }

    private func makeSyntheticID() -> CGWindowID {
        nextSyntheticID &+= 1
        if nextSyntheticID < WindowItem.firstSyntheticID { nextSyntheticID = WindowItem.firstSyntheticID }
        return nextSyntheticID
    }

    // MARK: Actions

    func focus(_ item: WindowItem) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        if app.isHidden { app.unhide() }
        lastFocused = (item.id, item.pid, Date())

        if item.isWindowless {
            reopen(app)
            return
        }

        let windowID = item.hasRealWindowID ? item.id : 0
        if !PrivateWindowAPI.bringToFront(pid: item.pid, windowID: windowID) { app.activate() }

        if let element = item.axElement {
            // Accessibility calls go to the target app and can be slow; keep
            // them off the main thread, which also services the keyboard.
            let ref = AXRef(element: element)
            let wasMinimized = item.isMinimized
            Task.detached(priority: .userInitiated) {
                if wasMinimized { AX.setBool(ref.element, kAXMinimizedAttribute, false) }
                AX.setBool(ref.element, kAXMainAttribute, true)
                AX.perform(ref.element, kAXRaiseAction)
            }
        } else {
            // A window on another Space: macOS switches Spaces for the app,
            // then raise the exact window once it's reachable via AX.
            let id = item.id, pid = item.pid
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(for: .milliseconds(400))
                WindowManager.raise(windowID: id, pid: pid)
            }
        }
        if item.hasRealWindowID { touch(item.id) }
    }

    /// Like clicking the app in the Dock: it opens a window if it has none.
    private func reopen(_ app: NSRunningApplication) {
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        } else if !PrivateWindowAPI.bringToFront(pid: app.processIdentifier, windowID: 0) {
            app.activate()
        }
    }

    nonisolated private static func raise(windowID: CGWindowID, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        for window in AX.elements(app, kAXWindowsAttribute).prefix(maxWindowsPerApp)
        where PrivateWindowAPI.windowID(of: window) == windowID {
            AXUIElementSetMessagingTimeout(window, axTimeout)
            AX.setBool(window, kAXMainAttribute, true)
            AX.perform(window, kAXRaiseAction)
            return
        }
    }

    func close(_ item: WindowItem) {
        guard let element = item.axElement else { return }
        let ref = AXRef(element: element)
        Task.detached(priority: .userInitiated) {
            guard let button = AX.element(ref.element, kAXCloseButtonAttribute) else { return }
            AXUIElementSetMessagingTimeout(button, WindowManager.axTimeout)
            AX.perform(button, kAXPressAction)
        }
    }

    func toggleMinimized(_ item: WindowItem) {
        guard let element = item.axElement else { return }
        let ref = AXRef(element: element)
        let minimize = !item.isMinimized
        Task.detached(priority: .userInitiated) {
            AX.setBool(ref.element, kAXMinimizedAttribute, minimize)
        }
    }

    func toggleFullscreen(_ item: WindowItem) {
        guard let element = item.axElement else { return }
        let ref = AXRef(element: element)
        let fullscreen = !item.isFullscreen
        Task.detached(priority: .userInitiated) {
            AX.setBool(ref.element, "AXFullScreen", fullscreen)
        }
    }

    func quitApp(_ item: WindowItem) {
        NSRunningApplication(processIdentifier: item.pid)?.terminate()
    }

    func toggleHidden(_ item: WindowItem) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        if app.isHidden { app.unhide() } else { app.hide() }
    }
}

// MARK: - Window-level focus tracking

private let focusChangedCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon, let id = PrivateWindowAPI.windowID(of: element) else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    // Runs on the observer thread. The box is retained until the session has removed
    // every observer, and its target is weak (a weak load is atomic).
    Unmanaged<CallbackTarget<FocusSession>>.fromOpaque(refcon).takeUnretainedValue().target?
        .deliver(pid: pid, windowID: id)
}

/// Watches every app for "focused window changed", so the switcher's order
/// reflects the windows you actually used, not just which app was in front.
/// Restartable: each start() builds a new session (thread, observers, refcon box);
/// stop() removes every observer and ends the thread.
@MainActor final class FocusTracker {
    /// Delivered on the main thread. Set before `start()`.
    var onFocus: (@MainActor (pid_t, CGWindowID) -> Void)?

    private var session: FocusSession?

    var isRunning: Bool { session != nil }

    func start() {
        guard session == nil else { return }
        let session = FocusSession(onFocus: onFocus)
        session.start()
        self.session = session
    }

    func stop() {
        session?.stop()
        session = nil
    }

    /// (Re)registers every running app. Harmless for apps already observed.
    func observeAll() {
        session?.observeAll()
    }
}

private final class FocusSession: @unchecked Sendable {
    private let onFocus: (@MainActor (pid_t, CGWindowID) -> Void)?
    private let thread = ObserverThread()
    private var observers: [pid_t: (observer: AXObserver, app: AXUIElement)] = [:]   // only touched on `thread`
    private var notificationTokens: [NSObjectProtocol] = []                         // main only
    private var box: Unmanaged<CallbackTarget<FocusSession>>?                        // set on main, released on `thread`
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private let stateLock = NSLock()
    private var stopped = false
    private var pending: (pid: pid_t, windowID: CGWindowID)?

    init(onFocus: (@MainActor (pid_t, CGWindowID) -> Void)?) {
        self.onFocus = onFocus
    }

    private var isStopped: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return stopped
    }

    @MainActor func start() {
        box = Unmanaged.passRetained(CallbackTarget(self))
        thread.name = "Snaptic focus tracking"
        thread.qualityOfService = .userInitiated
        thread.start()
        thread.waitUntilReady()

        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let pid = Self.pid(from: note) else { return }
            self.onThread {
                self.observe(pid, attempt: 0)
                self.reportFocusedWindow(of: pid)
            }
        })
        notificationTokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let pid = Self.pid(from: note) else { return }
            self.onThread { self.observe(pid, attempt: 0) }
        })
        notificationTokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let pid = Self.pid(from: note) else { return }
            self.onThread { self.stopObserving(pid) }
        })

        observeAll()
    }

    /// Removes every observer, releases the refcon box and ends the thread.
    @MainActor func stop() {
        stateLock.lock()
        let already = stopped
        stopped = true
        pending = nil
        stateLock.unlock()
        guard !already else { return }

        let center = NSWorkspace.shared.notificationCenter
        for token in notificationTokens { center.removeObserver(token) }
        notificationTokens = []

        // The box stays set: blocks still queued check `stopped` before using it, and the
        // block below (queued last) releases it.
        let box = self.box
        thread.cancel()
        thread.perform {
            for pid in Array(self.observers.keys) { self.stopObserving(pid) }
            self.observers = [:]
            box?.release()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    @MainActor func observeAll() {
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { $0.processIdentifier }
        onThread {
            // Drop observers of processes that are gone (NSRunningApplication.isTerminated
            // can lag by seconds on macOS 27, leaking observers under churn).
            for pid in Array(self.observers.keys) where kill(pid, 0) != 0 && errno == ESRCH {
                self.stopObserving(pid)
            }
            for pid in pids { self.observe(pid, attempt: 0) }
        }
    }

    private func onThread(_ block: @escaping () -> Void) {
        guard !isStopped else { return }
        thread.perform { [weak self] in
            guard let self, !self.isStopped else { return }
            block()
        }
    }

    private static func pid(from note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    /// Coalesced: a flood of focus notifications (e.g. from a hostile app)
    /// costs the main thread at most one hop at a time, with the latest value.
    fileprivate func deliver(pid: pid_t, windowID: CGWindowID) {
        stateLock.lock()
        guard !stopped else { stateLock.unlock(); return }
        let alreadyScheduled = pending != nil
        pending = (pid, windowID)
        stateLock.unlock()
        guard !alreadyScheduled else { return }

        let handler = onFocus
        Task { @MainActor in
            let latest = self.takePending()
            if let latest { handler?(latest.pid, latest.windowID) }
        }
    }

    /// Synchronous on purpose: locks are never held across an `await`.
    private func takePending() -> (pid: pid_t, windowID: CGWindowID)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !stopped else { return nil }
        let latest = pending
        pending = nil
        return latest
    }

    // Runs on `thread`.
    private func observe(_ pid: pid_t, attempt: Int) {
        guard observers[pid] == nil, pid != ownPID, let box else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, focusChangedCallback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, WindowManager.axTimeout)
        guard AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString,
                                        box.toOpaque()) == .success else {
            // Apps that just launched often aren't ready yet; try again shortly.
            let delays: [Double] = [0.3, 1.0, 3.0]
            guard attempt < delays.count else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
                self?.onThread { self?.observe(pid, attempt: attempt + 1) }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = (observer, app)
    }

    // Runs on `thread`.
    private func stopObserving(_ pid: pid_t) {
        guard let entry = observers.removeValue(forKey: pid) else { return }
        AXObserverRemoveNotification(entry.observer, entry.app, kAXFocusedWindowChangedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(entry.observer), .defaultMode)
    }

    // Runs on `thread`.
    private func reportFocusedWindow(of pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, WindowManager.axTimeout)
        guard let window = AX.element(app, kAXFocusedWindowAttribute),
              let id = PrivateWindowAPI.windowID(of: window) else { return }
        deliver(pid: pid, windowID: id)
    }
}

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
    var windowID: CGWindowID?
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

/// One app's windows for Dock Previews (PLAN 0.5 §4.8): `WindowManager.windows(for:budget:allowUntitled:)`.
struct DockWindowRead {
    var items: [WindowItem] = []
    /// The budget ran out after at least one window was read, so the app may have more ("More windows…").
    var unreadRemain = false
    /// AX couldn't read even the first window in time, or the app is in its 30 s skip after that: `items` are
    /// `CGWindowList` windows only, with titles only.
    var timedOut = false
    /// Served from the 2 s cache.
    var fromCache = false
    /// The app's on-screen layer-0 windows, front to back, as the read found them (the recency merge's stacking
    /// order, §4.8; A4a).
    var zOrder: [CGWindowID: Int] = [:]

    /// The windows a caller lists (`allowUntitled`, §2.6). The read itself keeps untitled ones for every caller.
    fileprivate func listing(allowUntitled: Bool, fromCache: Bool) -> DockWindowRead {
        var read = self
        read.items = items.filter { DockReaderRules.listed($0.catalog, allowUntitled: allowUntitled) }
        read.fromCache = fromCache
        return read
    }
}

/// One app's AX read. `ranOut`: the budget ran out before the read was done. `listTimedOut`: the window list itself
/// still timed out (`kAXErrorCannotComplete`) when the read ended.
private struct AppRead: Sendable {
    var windows: [RawWindow]
    var ranOut: Bool
    var listTimedOut: Bool
}

/// A window read only from `CGWindowList`, before it becomes a `WindowItem`.
private struct ListOnlyWindow: Sendable {
    var catalog: CatalogWindow
    /// Sanitized.
    var title: String
    var hasPrivateMarker: Bool
    var frame: CGRect
}

/// What the window-read thread gives back for one app (§4.8). The ids of AX windows without a real one are filled in
/// on main.
private struct DockAppScan: @unchecked Sendable {
    var ax: [(raw: RawWindow, catalog: CatalogWindow)] = []
    var listOnly: [ListOnlyWindow] = []
    var ranOut = false
    var timedOut = false
    var zOrder: [CGWindowID: Int] = [:]
}

/// Dock Previews' window reads (§4.8): one `ObserverThread`, so an app that stalls never holds main or a pool thread.
/// Created on the first read and ended with the module (`WindowManager.endWindowReads()`).
private final class WindowReadQueue: @unchecked Sendable {
    private let thread = ObserverThread()
    private let lock = NSLock()
    private var stopped = false
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<DockAppScan?, Never>] = [:]

    @MainActor init() {
        thread.name = "Snaptic window reads"
        thread.qualityOfService = .userInitiated
        thread.start()
        thread.waitUntilReady()
    }

    /// Runs `work` on the thread. Nil once the queue has stopped.
    func submit(_ work: @escaping @Sendable () -> DockAppScan) async -> DockAppScan? {
        await withCheckedContinuation { continuation in
            lock.lock()
            guard !stopped else {
                lock.unlock()
                continuation.resume(returning: nil)
                return
            }
            let id = nextID
            nextID += 1
            pending[id] = continuation
            lock.unlock()
            thread.perform {
                let result = self.isStopped ? nil : work()
                self.finish(id, result)
            }
        }
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func finish(_ id: Int, _ result: DockAppScan?) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(returning: result)
    }

    /// Every waiting read gets nil; a read in progress finishes on the thread first.
    func stop() {
        lock.lock()
        let waiting = stopped ? [] : Array(pending.values)
        stopped = true
        pending = [:]
        lock.unlock()
        for continuation in waiting { continuation.resume(returning: nil) }
        thread.cancel()
        thread.perform { CFRunLoopStop(CFRunLoopGetCurrent()) }
    }
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
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }
}

/// Finds windows, keeps a most-recently-used order, and focuses / closes / minimizes them.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// Limits that keep one misbehaving app from slowing the switcher.
    nonisolated static let maxWindowsPerApp = 100
    nonisolated static let maxTitleLength = 512
    nonisolated static let perAppBudget: Double = 0.5
    /// Listing as a whole gives up on slow apps after this long.
    nonisolated static let totalBudget: Double = 1.2

    private var mru: [CGWindowID] = []
    private var nextSyntheticID = WindowItem.firstSyntheticID
    fileprivate var lastFocused: (id: CGWindowID, pid: pid_t, at: Date)?

    // MARK: Most-recently-used tracking

    private(set) var isStarted = false

    /// Idempotent. Seeds the most-recently-used order. `WindowServices` calls it on the first `.recency` lease, then
    /// starts `FocusTracker`, which reports through `focusChanged(pid:windowID:)`.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        // Seed with the current stacking order, front first.
        mru = Self.serverSnapshot().zOrder.sorted { $0.value < $1.value }.map { $0.key }
    }

    /// Idempotent. Forgets the window order. `WindowServices` calls it on the last `.recency` release, after
    /// `FocusTracker` has stopped (every AX observer is removed).
    func stop() {
        guard isStarted else { return }
        isStarted = false
        mru = []
        lastFocused = nil
    }

    /// `FocusTracker` saw an app's focused window change (on the main thread).
    func focusChanged(pid: pid_t, windowID id: CGWindowID) {
        // Only the app you're actually using counts; background apps
        // shuffling their own windows must not reorder the switcher.
        guard pid == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        if let recent = recentFocus {
            // Right after Snaptic switched, the app may still report its old
            // window for a moment; don't let that jump ahead of the target.
            if recent.pid == pid, recent.id != id { return }
            if recent.pid != pid { lastFocused = nil }   // user moved on
        }
        touch(id)
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
        PrivateWindowAPI.readKillSwitches()   // once per enumeration (H6)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            WindowCatalogRules.listsApp(regular: $0.activationPolicy == .regular,
                                        isOwnProcess: $0.processIdentifier == ownPID,
                                        bundleID: $0.bundleIdentifier, excluded: excluded)
        }
        let snapshots = apps.map { AppSnapshot(pid: $0.processIdentifier) }
        let recent = recentFocus
        let frontPID = effectiveFrontPID
        let server = Self.serverSnapshot()
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
    nonisolated private static func include(_ window: inout CatalogWindow,
                                            options: CatalogInclusion = .switcher) -> CatalogVerdict {
        if WindowCatalogRules.needsSpaceCheck(window, appListed: true, options: options) {
            window.spaceKnown = PrivateWindowAPI.isOnAnySpace(window.id)
        }
        return WindowCatalogRules.inclusion(window, appListed: true, options: options)
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
        read(app.pid, owners: owners, deadline: deadline, budget: perAppBudget, options: .switcher,
             retryList: false).windows
    }

    /// One app's AX windows, within `budget` seconds and `deadline`. `retryList`: a window list that timed out is
    /// asked for again while time is left (Dock Previews, §4.8), so a timeout means the whole budget went by.
    nonisolated private static func read(_ pid: pid_t, owners: [CGWindowID: pid_t], deadline: UInt64, budget: Double,
                                         options: CatalogInclusion, retryList: Bool) -> AppRead {
        let appDeadline = min(deadline, DispatchTime.now().uptimeNanoseconds + UInt64(budget * 1_000_000_000))
        var ranOut = false
        // Checked before every request, so one slow app costs at most its budget.
        func outOfTime() -> Bool {
            guard DispatchTime.now().uptimeNanoseconds > appDeadline else { return false }
            ranOut = true
            return true
        }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, WindowServices.axTimeout)
        var list = AX.read(appElement, kAXWindowsAttribute)
        while retryList, list.error == .cannotComplete, !outOfTime() {
            list = AX.read(appElement, kAXWindowsAttribute)
        }
        var result: [RawWindow] = []
        var refused: [Int] = []
        for window in AX.elements(in: list.value).prefix(maxWindowsPerApp) {
            if outOfTime() { break }
            AXUIElementSetMessagingTimeout(window, WindowServices.axTimeout)
            // The subrole and size parts of the shared inclusion rule, checked before the title is read.
            let kind = CatalogWindowKind(subrole: AX.string(window, kAXSubroleAttribute))
            guard WindowCatalogRules.kindLeftOut(kind, hasTitle: nil, options: options) == nil,
                  !outOfTime() else { continue }
            let size = AX.size(window) ?? .zero
            guard WindowCatalogRules.sizeLeftOut(width: Double(size.width), height: Double(size.height),
                                                 minimum: options.minAXSide) == nil,
                  !outOfTime() else { continue }

            let lookup = PrivateWindowAPI.lookUpWindowID(of: window)
            var claimed: CGWindowID?
            if case .id(let id) = lookup { claimed = id }
            if case .refused = lookup { refused.append(result.count) }
            let windowID = WindowCatalogRules.trustedWindowID(claimed: claimed, pid: pid, owners: owners)
            let fullTitle = outOfTime() ? "" : (AX.string(window, kAXTitleAttribute) ?? "")

            result.append(RawWindow(
                pid: pid,
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
        if !refused.isEmpty { matchByTitleAndFrame(&result, refused, pid: pid) }
        return AppRead(windows: result, ranOut: ranOut, listTimedOut: list.error == .cannotComplete)
    }

    /// `axWindowID` was refused for the windows at `indices`: each takes the id of the one window-server window of
    /// its app with the same frame and title (§4.12), so it gets its thumbnail and isn't listed twice.
    nonisolated private static func matchByTitleAndFrame(_ windows: inout [RawWindow], _ indices: [Int], pid: pid_t) {
        let list = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        let candidates = list.compactMap { info -> WindowFrameCandidate? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { return nil }
            let title = (info[kCGWindowName as String] as? String).map {
                TextSanitizer.clean($0, maxScalars: maxTitleLength)
            }
            return WindowFrameCandidate(id: id, title: title, frame: DockRect(x: bounds.minX, y: bounds.minY,
                                        width: bounds.width, height: bounds.height), layer: layer)
        }
        var taken = Set(windows.compactMap(\.windowID))
        for index in indices {
            let frame = windows[index].frame
            guard let id = WindowCatalogRules.matchByTitleAndFrame(
                title: windows[index].title,
                frame: DockRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
                candidates: candidates, taken: taken) else { continue }
            windows[index].windowID = id
            taken.insert(id)
        }
    }

    nonisolated private static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, WindowServices.axTimeout)
        guard let window = AX.element(app, kAXFocusedWindowAttribute) else { return nil }
        return PrivateWindowAPI.windowID(of: window)
    }

    nonisolated private static func serverSnapshot() -> ServerSnapshot {
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
        var hidden: [pid_t: Bool] = [:]
        for app in apps {
            byPID[app.processIdentifier] = app
            hidden[app.processIdentifier] = app.isHidden
        }
        let found = Self.listOnlyWindows(hidden: hidden, primaryHeight: Screens.primaryHeight,
                                         alreadySeen: alreadySeen, options: .switcher, onScreenToo: false)
        let items = found.windows.compactMap { window in
            byPID[window.catalog.pid].map { Self.item(window, app: $0) }
        }
        return (items, found.pids)
    }

    /// The windows `CGWindowList` reports for the apps in `hidden` (pid → hidden), past the shared inclusion rule.
    /// `onScreenToo`: on-screen windows are listed as well (an app AX timed out on, §4.8). Also returns every app that
    /// has a real window somewhere, titled or not.
    nonisolated private static func listOnlyWindows(
        hidden: [pid_t: Bool],
        primaryHeight: CGFloat,
        alreadySeen: Set<CGWindowID>,
        options: CatalogInclusion,
        onScreenToo: Bool
    ) -> (windows: [ListOnlyWindow], pids: Set<pid_t>) {
        let list = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        var windows: [ListOnlyWindow] = []
        var pids = Set<pid_t>()
        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  !alreadySeen.contains(id),
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let isHidden = hidden[pid],
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { continue }
            let rawTitle = info[kCGWindowName as String] as? String ?? ""
            // Layer, on-screen, size, alpha and the Spaces check (inactive native tabs and hidden helper windows
            // belong to no Space) are the shared inclusion rule's.
            let cocoa = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width,
                               height: bounds.height)
            var window = CatalogWindow(
                id: id,
                pid: pid,
                hasTitle: !rawTitle.isEmpty,
                hidden: isHidden,
                onScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                layer: layer,
                bounds: DockRect(cocoa: cocoa),
                hasAXElement: false,
                kind: .unknown,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            )
            let verdict = include(&window, options: options)
            if verdict.appHasWindow { pids.insert(pid) }
            guard verdict.included || (onScreenToo && DockReaderRules.listedOnTimeout(window, options: options))
            else { continue }
            windows.append(ListOnlyWindow(
                catalog: window,
                title: TextSanitizer.clean(rawTitle, maxScalars: maxTitleLength),
                hasPrivateMarker: TextSanitizer.hasPrivateMarker(rawTitle),
                frame: bounds
            ))
        }
        return (windows, pids)
    }

    private static func item(_ window: ListOnlyWindow, app: NSRunningApplication) -> WindowItem {
        WindowItem(
            catalog: window.catalog,
            axElement: nil,
            appName: appName(app),
            bundleID: app.bundleIdentifier,
            title: window.title,
            icon: app.icon ?? NSImage(),
            frame: window.frame,
            hasPrivateMarker: window.hasPrivateMarker
        )
    }

    // MARK: Dock Previews

    /// The last read of each app, 2 s, marked dirty by the freshness lease (§4.8).
    private var dockCache = DockWindowCache<DockWindowRead>()
    private var windowReadQueue: WindowReadQueue?
    /// Bumped by `endWindowReads()`, so a read that finishes after it is dropped.
    private var windowReadEpoch = 0
    private var reading: [pid_t: Int] = [:]
    /// Apps the lease marked dirty while a read was in progress: that read isn't cached.
    private var dirtiedWhileReading = Set<pid_t>()

    nonisolated private static var uptime: Double { ProcessInfo.processInfo.systemUptime }

    /// One app's windows for Dock Previews (§4.8): AX, within `budget` seconds, on the window-read thread; windows on
    /// other Spaces from `CGWindowList`. Cached 2 s unless the lease marks the app dirty. When the budget runs out
    /// after at least one window, the list is partial (`unreadRemain`). When AX can't read even the first window in
    /// time, the app isn't read through AX for 30 s and its `CGWindowList` windows are listed, titles only
    /// (`timedOut`). `allowUntitled` (§2.6): untitled windows read only from `CGWindowList` are listed.
    func windows(for pid: pid_t, budget: Double = WindowManager.perAppBudget,
                 allowUntitled: Bool = true) async -> DockWindowRead {
        let now = Self.uptime
        dockCache.prune(now: now)
        if let cached = dockCache.value(for: pid, now: now) {
            return cached.listing(allowUntitled: allowUntitled, fromCache: true)
        }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return DockWindowRead() }
        PrivateWindowAPI.readKillSwitches()   // once per read, as `loadWindows` does (H6)
        let budget = budget.isFinite ? min(max(budget, 0), Self.totalBudget) : Self.perAppBudget
        let skip = dockCache.isSkipped(pid, now: now)
        let hidden = app.isHidden
        let primaryHeight = Screens.primaryHeight
        let epoch = windowReadEpoch
        let queue = windowReadQueue ?? WindowReadQueue()
        windowReadQueue = queue
        reading[pid, default: 0] += 1
        let scan = await queue.submit {
            Self.scan(pid: pid, hidden: hidden, primaryHeight: primaryHeight, budget: budget, skip: skip)
        }
        guard epoch == windowReadEpoch else { return DockWindowRead() }
        let dirtied = finishReading(pid)
        guard let scan else { return DockWindowRead() }

        let done = Self.uptime
        if scan.timedOut, !skip { dockCache.timedOut(pid, now: done) }
        let name = Self.appName(app)
        let icon = app.icon ?? NSImage()
        var items: [WindowItem] = []
        for (raw, catalog) in scan.ax {
            var window = catalog
            if raw.windowID == nil { window.id = makeSyntheticID() }
            items.append(WindowItem(catalog: window, axElement: raw.element, appName: name,
                                    bundleID: app.bundleIdentifier, title: raw.title, icon: icon, frame: raw.frame,
                                    hasPrivateMarker: raw.hasPrivateMarker))
        }
        items += scan.listOnly.map { Self.item($0, app: app) }
        var read = DockWindowRead(items: items, unreadRemain: scan.ranOut && !scan.timedOut, timedOut: scan.timedOut)
        read.zOrder = scan.zOrder
        if !dirtied { dockCache.store(read, for: pid, now: done) }
        return read.listing(allowUntitled: allowUntitled, fromCache: false)
    }

    /// One read of `pid` ended. True when the lease marked the app dirty while it ran.
    private func finishReading(_ pid: pid_t) -> Bool {
        let left = (reading[pid] ?? 1) - 1
        reading[pid] = left > 0 ? left : nil
        return left > 0 ? dirtiedWhileReading.contains(pid) : dirtiedWhileReading.remove(pid) != nil
    }

    /// The freshness lease saw the app's windows change (`WindowServices` `onWindowsChanged`).
    func markWindowsDirty(_ pid: pid_t) {
        dockCache.markDirty(pid)
        if reading[pid] != nil { dirtiedWhileReading.insert(pid) }
    }

    /// The module stopped: the window-read thread ends, waiting reads get an empty answer and the cache is dropped.
    func endWindowReads() {
        windowReadEpoch += 1
        windowReadQueue?.stop()
        windowReadQueue = nil
        dockCache.removeAll()
        reading = [:]
        dirtiedWhileReading = []
    }

    /// The read itself, on the window-read thread.
    nonisolated private static func scan(pid: pid_t, hidden: Bool, primaryHeight: CGFloat, budget: Double,
                                         skip: Bool) -> DockAppScan {
        var scan = DockAppScan()
        var seen = Set<CGWindowID>()
        if skip {
            scan.timedOut = true
        } else {
            let server = serverSnapshot()
            scan.zOrder = server.zOrder.filter { server.owner[$0.key] == pid }
            let read = read(pid, owners: server.owner, deadline: .max, budget: budget, options: .dock,
                            retryList: true)
            for raw in read.windows {
                if let id = raw.windowID, !seen.insert(id).inserted { continue }
                let frame = raw.frame
                var window = CatalogWindow(
                    id: raw.windowID ?? WindowItem.firstSyntheticID,
                    pid: pid,
                    hasTitle: !raw.title.isEmpty,
                    minimized: raw.isMinimized,
                    hidden: hidden,
                    onScreen: raw.windowID.map { server.onScreen.contains($0) } ?? true,
                    fullscreen: raw.isFullscreen,
                    layer: raw.windowID.flatMap { server.layer[$0] } ?? 0,
                    bounds: DockRect(cocoa: CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width,
                                                   height: frame.height)),
                    kind: raw.kind
                )
                guard include(&window, options: .dock).included else { continue }
                scan.ax.append((raw, window))
            }
            scan.ranOut = read.ranOut
            scan.timedOut = read.windows.isEmpty && (read.ranOut || read.listTimedOut)
        }
        scan.listOnly = listOnlyWindows(hidden: [pid: hidden], primaryHeight: primaryHeight, alreadySeen: seen,
                                        options: .dock, onScreenToo: scan.timedOut).windows
        return scan
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

    /// Like clicking the app in the Dock: it opens a window if it has none. Dock Previews' small card and app-wide
    /// actions call it too (§4.4).
    func reopen(_ app: NSRunningApplication) {
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
        AXUIElementSetMessagingTimeout(app, WindowServices.axTimeout)
        for window in AX.elements(app, kAXWindowsAttribute).prefix(maxWindowsPerApp)
        where PrivateWindowAPI.windowID(of: window) == windowID {
            AXUIElementSetMessagingTimeout(window, WindowServices.axTimeout)
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
            AXUIElementSetMessagingTimeout(button, WindowServices.axTimeout)
            AX.perform(button, kAXPressAction)
        }
    }

    /// Dock Previews' Close All (§4.4): presses each listed window's close button, in order, in one background task.
    /// A window without an AX element is left alone.
    func close(_ items: [WindowItem]) {
        let refs = items.compactMap { $0.axElement.map(AXRef.init) }
        guard !refs.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            for ref in refs {
                guard let button = AX.element(ref.element, kAXCloseButtonAttribute) else { continue }
                AXUIElementSetMessagingTimeout(button, WindowServices.axTimeout)
                AX.perform(button, kAXPressAction)
            }
        }
    }

    /// Dock Previews' Minimize All (§4.4): minimizes each listed window that isn't already, in one background task.
    func minimize(_ items: [WindowItem]) {
        let refs = items.filter { !$0.isMinimized }.compactMap { $0.axElement.map(AXRef.init) }
        guard !refs.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            for ref in refs { AX.setBool(ref.element, kAXMinimizedAttribute, true) }
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

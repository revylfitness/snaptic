import AppKit
import SwiftUI
import SnapticKit

/// Dock Previews' controller (PLAN 0.5 §2.4, §4.1–§4.3, §4.7–§4.9; A4a): it feeds K3's `DockPreviewPolicy` and runs
/// its commands.
/// - Events go through one queue, so a command that sends an event (a placement) never re-enters the policy.
/// - The pointer is watched only while the policy asks (`watchPointer`): a global and a local mouse monitor, the
///   panel's tracking area, and the workspace notifications the policy reacts to. Moves reach the policy at most once
///   a display frame (`DockMoveThrottle`); the first goes the moment watching starts (§R4 K3).
/// - The policy's geometry is K2's, from what the Dock observer last read (`DockPreviewRules.liveGeometry`).
/// - A show reads the app's windows (`WindowManager.windows(for:)`, off main) and settles the item's frame (the
///   observer's reads); the panel is placed once both are in. A swap reuses the panel.
/// - While shown, a 0.1 s tick reconciles the pointer with the panel, drives the policy's deadlines and re-reads the
///   windows every second (S0-26); the lease's freshness for the shown app (§2.3, M32) marks the read dirty.
/// - Thumbnails come from the shared store and `WindowCapture` at the Dock's 720 px bucket, for the cards in view
///   plus one each side (§4.3, §4.9), never for a private window, a protected app or an app hidden from Dock
///   previews (§4.10).
/// - A4b: the actions (§4.4) are internal methods A5's keys call too. Each one checks the card's window again first
///   (§4.8), and its AX calls run off main (`WindowManager`). With VoiceOver and “Show previews while VoiceOver is
///   on”, the selection alone drives the panel and each show is announced (§4.16).
/// - No window titles, app names or bundle ids are logged.
@MainActor
final class DockPreviewController {
    /// §4.9: the Dock's thumbnail bucket, on the long side.
    static let maxPixels: CGFloat = 720
    /// The panel is placed at the selection's frame if the settle reads haven't answered by then (§4.7).
    static let settleFallback = 0.25
    /// The tick while a panel is shown.
    static let tickInterval = 0.1
    /// A window action's AX change lands a moment later; the panel reads once more after this.
    static let followUpDelay = 0.3
    /// Finder has no Quit (§4.4).
    static let finderBundleID = "com.apple.finder"
    /// SwiftUI's VoiceOver focus can pass through nil between two of the panel's elements, so focus leaving the
    /// panel counts only once it has lasted this long (§4.16).
    static let focusLeaveDelay = 0.15

    /// The policy's clock.
    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// One show: the app, where its panel goes, and what its window read found.
    private struct Showing {
        let pid: Int32
        var anchor: DockRect
        var edge: DockEdge
        var settled = false
        var read: DockWindowRead?
        /// `totalBudget` once “More windows…” was clicked.
        var budget = WindowManager.perAppBudget
        /// The windows in card order, as the view lists them.
        var cards: [WindowItem] = []
        var built = false
        /// VoiceOver heard this show's announcement (§4.16).
        var announced = false
        let startedAt: Double
    }

    private let observer: DockObserver
    private var config: DockConfig
    private let onFreshness: @MainActor (Int32?) -> Void
    private let onCapture: @MainActor (Int) -> Void
    private var policy: DockPreviewPolicy
    private let timers = DockTimers()
    private let model = DockPreviewModel()
    private var panel: DockPreviewPanel?
    private var stopped = false

    // The event queue.
    private var queue: [DockEvent] = []
    private var draining = false

    // The pointer, while watched.
    private var watching = false
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var throttle = DockMoveThrottle()
    private var flushTimer: Int?
    private var dragging = false
    private var inPanel = false
    /// The selection as the policy last saw it, without the button-down rule, for mouse-downs on the item.
    private var lastSelection: DockSelection?

    private var tickTimer: Int?
    private var ticks = 0
    private var freshPID: Int32?

    // The show.
    private var showing: Showing?
    /// Bumped by each show, swap, hide and stop; reads, settles and images from before are dropped.
    private var generation = 0
    private var settleTimer: Int?
    private var readInFlight: Int?
    private var readAgain = false
    /// The panel's frame as the policy last heard it; nil while nothing is placed.
    private var placed: DockRect?
    private var scrollOffset = 0.0
    /// When the panel last appeared, in `ThumbnailStore.now` seconds (captures wait 150 ms after it, §4.9).
    private var visibleSince = 0.0
    private var requestedTargets: [CaptureTarget] = []
    private var lastVisible: [Int] = []
    /// The app whose icon and name the model shows.
    private var modelPID: Int32?

    // Our own actions, for `appActivated(byUs:)`.
    private var lastAction: DockAction?
    private var lastActionAt: Double?

    // A4b: keys, menus, the pointer's card and VoiceOver.
    /// `Dock.disable.keys` as read at the module's start (H6).
    private let keysKilled: Bool
    /// The panel's own right-click menus report opening and closing here (`ownMenuOpened`, `ownMenuClosed`).
    private var menuDelegate: DockMenuDelegate?
    /// The card under the pointer, as the view's tracking reports it; nil over the header, a gap or outside.
    private(set) var hoveredCardID: CGWindowID?
    /// VoiceOver's focus is on an element in the panel (§4.16).
    private var voiceOverFocused = false
    /// Runs `voiceOverFocusInPanel(false)` once focus has stayed out for `focusLeaveDelay`.
    private var focusTimer: Int?
    /// A5 sets this: its key tap runs, its breaker hasn't tripped and secure input is off (§4.5). Until A5 runs, no
    /// tooltip or menu offers a key.
    var keysAvailable = false {
        didSet { syncKeysWork() }
    }

    /// §4.5: keys work, so tooltips and menus show them. The setting is on, `Dock.disable.keys` isn't set and A5
    /// says its tap can take them (`keysAvailable`).
    var keysWork: Bool { config.keys && !keysKilled && keysAvailable }

    /// §4.22: counts and enums only.
    private var counts = DockPreviewCounts()

    init(observer: DockObserver, config: DockConfig, keysKilled: Bool,
         onFreshness: @escaping @MainActor (Int32?) -> Void, onCapture: @escaping @MainActor (Int) -> Void) {
        self.observer = observer
        self.config = config
        self.keysKilled = keysKilled
        self.onFreshness = onFreshness
        self.onCapture = onCapture
        let store = observer.geometry
        policy = DockPreviewPolicy(delay: config.delay, dockAutoHides: Self.dockAutoHides(),
                                   geometry: DockPreviewRules.liveGeometry { store.snapshot })
    }

    // MARK: Inputs

    /// The Dock observer's selection (coalesced, §2.4).
    func selectionChanged(_ raw: DockSelection?) {
        guard !stopped else { return }
        let hidden = isHiddenFromDock(raw?.pid), voiceOver = voiceOverPreviews
        lastSelection = DockPreviewRules.mapped(raw, hiddenFromDock: hidden, buttonDown: false, voiceOver: voiceOver)
        send(.selectionChanged(DockPreviewRules.mapped(raw, hiddenFromDock: hidden,
                                                       buttonDown: NSEvent.pressedMouseButtons != 0,
                                                       voiceOver: voiceOver)))
    }

    /// The lease's freshness notification for `pid` (§2.3).
    func windowsChanged(_ pid: Int32) {
        send(.windowsChanged(pid: pid))
    }

    /// The Dock's own menu opened or closed (M36).
    func dockMenu(_ open: Bool) {
        send(open ? .dockMenuOpened : .dockMenuClosed)
    }

    /// A §2.5 purge: the store is about to drop every thumbnail. The cards fall back to the icon.
    func purged() {
        dropThumbnails()
    }

    func configChanged(_ value: DockConfig) {
        guard !stopped else { return }
        let old = config
        config = value
        policy.delay = value.delay
        if !value.thumbnails { dropThumbnails() }
        syncKeysWork()
        if old != value, showing?.built == true { build() }
    }

    /// The module stopped: everything goes at once, with no fade.
    func stop() {
        guard !stopped else { return }
        send(.moduleStopped)
        stopped = true
        stopWatching()
        timers.cancelAll()
        tickTimer = nil
        flushTimer = nil
        settleTimer = nil
        focusTimer = nil
        if let panel {
            panel.close()
            self.panel = nil
            DockPreviewsModule.liveCount(.panel, up: false)
        }
        WindowCapture.shared.stop(client: .dockPreviews)
        model.reset()
        showing = nil
        modelPID = nil
        generation += 1
        freshPID = nil
    }

    /// §4.22's lines for this run.
    var diagnosticsLines: [String] { counts.lines }

    // MARK: The policy

    private func send(_ event: DockEvent) {
        guard !stopped else { return }
        queue.append(event)
        guard !draining else { return }
        draining = true
        while !queue.isEmpty {
            let next = queue.removeFirst()
            for command in policy.handle(next, now: Self.now) { run(command) }
        }
        draining = false
        syncTick()
        syncFreshness()
    }

    private func run(_ command: DockCommand) {
        switch command {
        case let .watchPointer(on):
            if on { startWatching() } else { stopWatching() }
        case let .show(pid, anchor, edge), let .swap(pid, anchor, edge):
            present(pid: pid, anchor: anchor, edge: edge)
        case let .hide(reason):
            dismiss(reason)
        case let .refresh(pid):
            guard showing?.pid == pid else { return }
            WindowManager.shared.markWindowsDirty(pid)
            read()
        case .engageKeys:
            break   // A5's DockKeys.
        case let .schedule(after, token):
            timers.after(after) { [weak self] in self?.send(.fired(token: token)) }
        }
    }

    /// The tick runs while a panel is shown.
    private func syncTick() {
        if policy.shownPID != nil {
            guard tickTimer == nil else { return }
            ticks = 0
            tickTimer = timers.every(Self.tickInterval) { [weak self] in self?.tick() }
        } else if let tickTimer {
            timers.cancel(tickTimer)
            self.tickTimer = nil
        }
    }

    private func tick() {
        if watching { syncInPanel(DockPoint(NSEvent.mouseLocation)) }
        send(.tick)
        ticks += 1
        guard ticks % DockPreviewRules.refreshTicks == 0, let sh = showing, sh.built else { return }
        // S0-26: a real re-read each second, since minimize and restore notifications arrive late. An app whose last
        // read ran out of budget is left to the 2 s cache, so a stalled app isn't asked every second (M10).
        if sh.read?.timedOut == false { WindowManager.shared.markWindowsDirty(sh.pid) }
        read()
    }

    /// The lease holds `.freshness(pid)` for the shown app only (M32).
    private func syncFreshness() {
        let pid = policy.shownPID
        guard pid != freshPID else { return }
        freshPID = pid
        onFreshness(pid)
    }

    // MARK: The pointer (§2.4, §4.1, §4.2)

    private func startWatching() {
        guard !watching else { return }
        watching = true
        policy.dockAutoHides = Self.dockAutoHides()
        observer.geometry.setScreens(Self.screens())
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                           .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.globalEvent(type) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type, windowNumber = event.windowNumber
            MainActor.assumeIsolated { self?.localEvent(type, windowNumber: windowNumber) }
            return event
        }) {
            monitors.append(local)
        }
        observeSystem()
        // §R4 K3: one move as watching starts, so the policy knows where the pointer is before it moves.
        pointer(at: NSEvent.mouseLocation)
    }

    private func stopWatching() {
        guard watching else { return }
        watching = false
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        throttle.reset()
        timers.cancel(flushTimer)
        flushTimer = nil
        dragging = false
        inPanel = false
    }

    /// Clicks and moves that go to other apps, the Dock included.
    private func globalEvent(_ type: NSEvent.EventType) {
        guard watching else { return }
        let location = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            dragging = false
            mouseDown(at: location)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if !dragging {
                dragging = true
                send(.dragStarted)
            }
            pointer(at: location)
        default:
            pointer(at: location)
        }
    }

    /// Clicks and moves that go to Snaptic's own windows, the panel included.
    private func localEvent(_ type: NSEvent.EventType, windowNumber: Int) {
        guard watching else { return }
        let location = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            dragging = false
            if let panel, windowNumber == panel.windowNumber {
                send(.panelClicked)
            } else {
                mouseDown(at: location)
            }
        default:
            pointer(at: location)
        }
    }

    /// A mouse-down outside the panel (X-12): on the selected item or anywhere else.
    private func mouseDown(at location: NSPoint) {
        let p = DockPoint(location)
        if panel?.isShown == true, placed?.contains(p) == true {
            send(.panelClicked)
            return
        }
        let band = lastSelection.map { policy.geometry.hitBand($0) }
        send(DockPreviewRules.mouseDown(at: p, selection: lastSelection, hitBand: band))
    }

    private func pointer(at location: NSPoint) {
        guard watching else { return }
        let p = DockPoint(location)
        syncInPanel(p)
        if let move = throttle.moved(to: p, now: Self.now) {
            sendMove(move)
        } else {
            armFlush()
        }
    }

    private func sendMove(_ p: DockPoint) {
        send(inPanel ? .pointerMovedInPanel(p) : .pointerMoved(p))
    }

    /// The last move of a burst goes once the frame is up.
    private func armFlush() {
        guard flushTimer == nil, let at = throttle.flushAt else { return }
        flushTimer = timers.after(max(at - Self.now, 0)) { [weak self] in
            guard let self else { return }
            self.flushTimer = nil
            if let move = self.throttle.flush(now: Self.now) {
                self.sendMove(move)
            } else if self.throttle.isHolding {
                self.armFlush()
            }
        }
    }

    /// The panel's tracking area, the monitors and the tick all land here, so entering and leaving is reported once.
    private func syncInPanel(_ p: DockPoint) {
        let inside = panel?.isShown == true && placed?.contains(p) == true
        guard inside != inPanel else { return }
        inPanel = inside
        send(inside ? .panelEntered : .panelExited)
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { controller, pid in
            guard let pid else { return }
            let byUs = DockPreviewRules.isByUs(action: controller.lastAction, at: controller.lastActionAt,
                                               now: Self.now)
            controller.send(.appActivated(pid: pid, byUs: byUs))
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { controller, pid in
            guard let pid else { return }
            controller.send(.appTerminated(pid: pid))
        }
        // §4.4 (G2-1): the header's Hide button reads Show while the app is hidden, and the cards' states follow.
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            observe(workspace, name) { controller, pid in
                guard let pid, pid == controller.showing?.pid else { return }
                controller.send(.windowsChanged(pid: pid))
            }
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { controller, _ in
            controller.send(.spaceChanged)
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { controller, _ in
            controller.send(.screensSlept)
        }
        observe(workspace, NSWorkspace.willSleepNotification) { controller, _ in
            controller.send(.willSleep)
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { controller, _ in
            controller.send(.sessionResigned)
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { controller, _ in
            controller.observer.geometry.setScreens(Self.screens())
            controller.send(.displaysChanged)
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) {
            controller, _ in
            controller.send(.locked)
        }
    }

    /// `handle` gets the notification's app pid, if it names one.
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handle: @escaping @MainActor (DockPreviewController, Int32?) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, self.watching else { return }
                handle(self, pid)
            }
        }
        observers.append((center, token))
    }

    // MARK: Showing (§4.3, §4.7, §4.8)

    private func present(pid: Int32, anchor: DockRect, edge: DockEdge) {
        generation += 1
        let gen = generation
        timers.cancel(settleTimer)
        settleTimer = nil
        showing = Showing(pid: pid, anchor: anchor, edge: edge, startedAt: Self.now)
        readInFlight = nil
        readAgain = false
        scrollOffset = 0
        requestedTargets = []
        lastVisible = []
        WindowCapture.shared.stop(client: .dockPreviews)
        counts.shows += 1
        read()
        observer.settle { [weak self] settled in self?.settled(settled, generation: gen) }
        settleTimer = timers.after(Self.settleFallback) { [weak self] in self?.settled(nil, generation: gen) }
    }

    /// The settled item frame is the anchor (§4.7); without one, the selection's frame stands.
    private func settled(_ selection: DockSelection?, generation gen: Int) {
        guard gen == generation, var sh = showing, !sh.settled else { return }
        timers.cancel(settleTimer)
        settleTimer = nil
        sh.settled = true
        if let selection, selection.pid == sh.pid, !selection.itemFrame.isDegenerate {
            sh.anchor = selection.itemFrame
        }
        showing = sh
        buildIfReady()
    }

    /// Reads the shown app's windows off main. One read at a time; a request while one runs reads again after it.
    private func read() {
        guard let sh = showing else { return }
        if readInFlight == generation {
            readAgain = true
            return
        }
        readInFlight = generation
        readAgain = false
        let gen = generation, pid = sh.pid, budget = sh.budget, started = Self.now
        Task { @MainActor [weak self] in
            let result = await WindowManager.shared.windows(for: pid, budget: budget)
            self?.landed(result, generation: gen, budget: budget, startedAt: started)
        }
    }

    private func landed(_ result: DockWindowRead, generation gen: Int, budget: Double, startedAt: Double) {
        guard gen == generation, var sh = showing else { return }
        readInFlight = nil
        if !result.fromCache { counts.reads.add((Self.now - startedAt) * 1000) }
        counts.lastWindowCount = result.items.count
        sh.read = result
        showing = sh
        if budget >= WindowManager.totalBudget, model.readingMore { model.readingMore = false }
        if readAgain { read() }
        buildIfReady()
    }

    private func buildIfReady() {
        guard let sh = showing, sh.settled, sh.read != nil else { return }
        build()
    }

    /// The cards, the layout and the panel's frame from the last read; then the thumbnails.
    private func build() {
        guard var sh = showing, let read = sh.read else { return }
        let services = WindowServices.shared
        let protect = services.protectPrivateWindows, protectedApps = services.protectedApps
        let ownWindow = panel.map { CGWindowID(truncatingIfNeeded: $0.windowNumber) }
        var items: [WindowItem] = []
        var privacies: [CatalogPrivacy] = []
        var privateIDs: Set<CGWindowID> = []
        for var item in read.items where item.id != ownWindow {
            let privacy = WindowCatalogRules.privacy(bundleID: item.bundleID, hasTitle: !item.title.isEmpty,
                                                     hasPrivateMarker: item.hasPrivateMarker,
                                                     windowless: item.isWindowless, protect: protect,
                                                     protectedApps: protectedApps)
            if privacy != .none {
                // §4.10: never captured, and the title never reaches the view.
                item.isPrivate = true
                item.title = ""
                if item.hasRealWindowID { privateIDs.insert(item.id) }
            }
            items.append(item)
            privacies.append(privacy)
        }
        if !privateIDs.isEmpty { ThumbnailStore.shared.forget(windowIDs: privateIDs) }

        let plan = DockPreviewRules.plan(windows: items.map(\.catalog), titles: items.map(\.title), config: config,
                                         pid: sh.pid, unreadRemain: read.unreadRemain, timedOut: read.timedOut,
                                         zOrder: read.zOrder)
        sh.cards = plan.order.map { items[$0] }
        sh.built = true
        showing = sh
        guard !plan.isEmpty,
              let site = DockPreviewRules.site(anchor: sh.anchor, edge: sh.edge, snapshot: observer.geometry.snapshot)
        else {
            conceal()
            return
        }
        var layout: DockPanelLayout?
        var size = DockPreviewRules.smallPanel()
        if plan.small == nil {
            layout = DockGeometry.layout(windows: plan.order.count, moreWindows: plan.moreWindows,
                                         preferred: config.cardSize, edge: site.edge,
                                         area: DockSize(width: site.area.width, height: site.area.height),
                                         rightToLeft: NSApp.userInterfaceLayoutDirection == .rightToLeft)
            guard let layout else {
                conceal()
                return
            }
            size = layout.panel
        }
        guard let frame = DockPreviewRules.frame(panel: size, anchor: sh.anchor, site: site) else {
            conceal()
            return
        }

        let displays = NSScreen.screens
        let cards = plan.order.map { index in
            let item = items[index]
            return DockPreviewCard(id: item.id, text: Self.text(item, privacy: privacies[index]),
                                   badge: Self.badge(item, displays: displays), hasAXElement: item.axElement != nil,
                                   minimized: item.isMinimized, fullScreen: item.isFullscreen,
                                   label: DockPreviewRules.cardLabel(item.catalog, privacy: privacies[index],
                                                                     title: item.title, app: item.appName))
        }
        updateModel(pid: sh.pid, items: items, small: plan.small, layout: layout, cards: cards)

        let panel = ensurePanel()
        panel.place(frame.cgRect)
        if !panel.isShown {
            panel.show()
            visibleSince = ThumbnailStore.now
            counts.lastShowLatency = (Self.now - sh.startedAt) * 1000
        }
        if placed != frame {
            placed = frame
            send(.panelPlaced(frame))
        }
        // §4.16: once per show or swap, “Safari, 3 windows”. A private window counts, but no title is ever said.
        if !sh.announced, showing?.pid == sh.pid, voiceOverPreviews {
            showing?.announced = true
            VoiceOverAnnouncer.announce(DockPreviewRules.announcement(app: model.appName, windows: plan.order.count,
                                                                      small: plan.small))
        }
        captureThumbnails()
    }

    /// Assigns only what changed, so a refresh that finds the same windows redraws nothing.
    private func updateModel(pid: Int32, items: [WindowItem], small: DockSmallCard?, layout: DockPanelLayout?,
                             cards: [DockPreviewCard]) {
        let app = NSRunningApplication(processIdentifier: pid)
        if modelPID != pid {
            modelPID = pid
            model.icon = items.first?.icon ?? app?.icon
            model.appName = items.first?.appName ?? TextSanitizer.clean(app?.localizedName ?? "", maxScalars: 64)
        }
        let hidden = app?.isHidden ?? false, finder = app?.bundleIdentifier == Self.finderBundleID
        if model.appHidden != hidden { model.appHidden = hidden }
        if model.isFinder != finder { model.isFinder = finder }
        if model.keysWork != keysWork { model.keysWork = keysWork }
        if model.small != small { model.small = small }
        if model.layout != layout { model.layout = layout }
        if model.cards != cards { model.cards = cards }
        if let id = hoveredCardID, !cards.contains(where: { $0.id == id }) { hoveredCardID = nil }
        let keep = Set(cards.indices.filter { !(showing?.cards[$0].isPrivate ?? true) }.map { cards[$0].id })
        if model.thumbnails.keys.contains(where: { !keep.contains($0) }) {
            model.thumbnails = model.thumbnails.filter { keep.contains($0.key) }
        }
    }

    /// The policy still has the app shown, but there's nothing to place (no screen, no room, or no card with the
    /// small cards off): the panel stays hidden until the next build or the hide (§R4).
    private func conceal() {
        placed = nil
        if inPanel {
            inPanel = false
            send(.panelExited)
        }
        WindowCapture.shared.stop(client: .dockPreviews)
        requestedTargets = []
        lastVisible = []
        panel?.hide { [weak self] in self?.releasePanel() }
    }

    private func dismiss(_ reason: DockDismissReason) {
        generation += 1
        timers.cancel(settleTimer)
        settleTimer = nil
        showing = nil
        readInFlight = nil
        readAgain = false
        requestedTargets = []
        lastVisible = []
        placed = nil
        inPanel = false
        hoveredCardID = nil
        timers.cancel(focusTimer)
        focusTimer = nil
        voiceOverFocused = false
        WindowCapture.shared.stop(client: .dockPreviews)
        counts.dismissals[reason, default: 0] += 1
        if let panel {
            panel.hide { [weak self] in self?.releasePanel() }
        } else {
            model.reset()
            modelPID = nil
        }
    }

    private func ensurePanel() -> DockPreviewPanel {
        if let panel { return panel }
        let actions = DockPreviewActions(
            card: { [weak self] id, button in self?.cardClicked(id, button) },
            smallCard: { [weak self] in self?.smallCardClicked() },
            moreWindows: { [weak self] in self?.moreWindows() },
            scrolled: { [weak self] offset in self?.scrolled(offset) },
            hoverButton: { [weak self] id, button in self?.hoverButtonClicked(id, button) },
            header: { [weak self] button in self?.headerClicked(button) },
            cardMenu: { [weak self] id in self?.cardMenu(id) },
            headerMenu: { [weak self] in self?.headerMenu() },
            hovered: { [weak self] id, inside in self?.cardHovered(id, inside) },
            voiceOverFocus: { [weak self] focused in self?.voiceOverFocusChanged(focused) })
        let panel = DockPreviewPanel(rootView: AnyView(DockPreviewView(model: model, actions: actions)),
                                     onPointer: { [weak self] in self?.pointer(at: NSEvent.mouseLocation) })
        self.panel = panel
        DockPreviewsModule.liveCount(.panel, up: true)
        return panel
    }

    /// After the fade-out (ground rule: the panel exists only while a preview is shown).
    private func releasePanel() {
        guard let panel, !panel.isShown else { return }
        panel.close()
        self.panel = nil
        DockPreviewsModule.liveCount(.panel, up: false)
        if showing == nil {
            model.reset()
            modelPID = nil
        }
    }

    // MARK: Thumbnails (§4.9)

    /// Cached thumbnails for the cards in view (plus one each side), and captures for the ones not asked for yet.
    private func captureThumbnails() {
        guard let sh = showing, sh.built, placed != nil else { return }
        guard config.thumbnails, WindowCapture.shared.screenRecordingAllowed() else {
            dropThumbnails()
            return
        }
        guard let layout = model.layout else { return }
        let visible = layout.thumbnailWindows(at: scrollOffset).filter { sh.cards.indices.contains($0) }
        lastVisible = visible
        let services = WindowServices.shared
        let store = ThumbnailStore.shared
        let lease = store.holdsThumbnails(.dockPreviews)
        let cached = store.cached(visible.map { sh.cards[$0].id }, maxPixels: Self.maxPixels, client: .dockPreviews)
        var thumbnails = model.thumbnails
        var fresh: [CaptureTarget] = []
        for index in visible {
            let item = sh.cards[index]
            let gate = CaptureGate(
                client: .dockPreviews, screenRecording: true, thumbnailsLease: lease, ownerMatches: true,
                protectedApp: WindowCatalogRules.isProtected(bundleID: item.bundleID,
                                                             protect: services.protectPrivateWindows,
                                                             protectedApps: services.protectedApps),
                hiddenFromDock: WindowCatalogRules.isHiddenFromDock(bundleID: item.bundleID,
                                                                    hiddenBundleIDs: config.hiddenBundleIDs),
                privatePath: false, hasLastSeen: cached[item.id] != nil)
            guard WindowCatalogRules.captureRefusal(item.catalog, gate: gate) == nil else { continue }
            if let image = cached[item.id], thumbnails[item.id] !== image { thumbnails[item.id] = image }
            if WindowCatalogRules.capturePath(item.catalog, gate: gate) == .screenCaptureKit,
               !requestedTargets.contains(where: { $0.id == item.id }) {
                fresh.append(CaptureTarget(window: item.catalog))
            }
        }
        if thumbnails.count != model.thumbnails.count
            || thumbnails.contains(where: { model.thumbnails[$0.key] !== $0.value }) {
            model.thumbnails = thumbnails
        }
        guard !fresh.isEmpty else { return }
        requestedTargets += fresh
        onCapture(fresh.count)
        let gen = generation
        WindowCapture.shared.refresh(requestedTargets, client: .dockPreviews, maxPixels: Self.maxPixels,
                                     priority: nil, visibleSince: visibleSince,
                                     protectedBundleIDs: services.captureBlockedBundleIDs,
                                     hiddenBundleIDs: config.hiddenBundleIDs) { [weak self] id, image in
            self?.imageArrived(id, image, generation: gen)
        }
    }

    private func imageArrived(_ id: CGWindowID, _ image: NSImage, generation gen: Int) {
        guard gen == generation, config.thumbnails, let sh = showing,
              let item = sh.cards.first(where: { $0.id == id }), !item.isPrivate else { return }
        model.thumbnails[id] = image
    }

    /// Thumbnails off, Screen Recording gone or a purge: the cards show the icon (M39).
    private func dropThumbnails() {
        WindowCapture.shared.stop(client: .dockPreviews)
        requestedTargets = []
        if !model.thumbnails.isEmpty { model.thumbnails = [:] }
    }

    private func scrolled(_ offset: Double) {
        scrollOffset = offset
        guard let layout = model.layout, layout.thumbnailWindows(at: offset) != lastVisible else { return }
        captureThumbnails()
    }

    // MARK: Actions (§4.4). A5's keys call these too.

    /// Bring Forward: raises the card's window (`WindowManager.focus`), and the panel hides (`raised`).
    func raiseWindow(_ id: CGWindowID) {
        guard let item = resolve(id) else { return }
        WindowManager.shared.focus(item)
        acted(.raise)
    }

    /// Close Window: presses the window's close button, so an app with unsaved work asks first. Needs the window's
    /// AX element (D2-25).
    func closeWindow(_ id: CGWindowID) {
        guard let item = resolve(id), item.axElement != nil else { return }
        WindowManager.shared.close(item)
        acted(.close)
        followUp()
    }

    /// Minimize Window. Needs the AX element; a minimized window is left as it is.
    func minimizeWindow(_ id: CGWindowID) {
        guard let item = resolve(id), item.axElement != nil, !item.isMinimized else { return }
        WindowManager.shared.toggleMinimized(item)
        acted(.minimize)
        followUp()
    }

    /// Restore Window: un-minimizes it in place, without raising it. Needs the AX element.
    func restoreWindow(_ id: CGWindowID) {
        guard let item = resolve(id), item.axElement != nil, item.isMinimized else { return }
        WindowManager.shared.toggleMinimized(item)
        acted(.restore)
        followUp()
    }

    /// Enter or Exit Full Screen, as the switcher does it: the window comes forward first, then it's toggled 250 ms
    /// later. Needs the AX element.
    func toggleFullScreen(_ id: CGWindowID) {
        guard let item = resolve(id), item.axElement != nil else { return }
        WindowManager.shared.focus(item)
        acted(.fullScreen)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            WindowManager.shared.toggleFullscreen(item)
        }
    }

    /// Minimize All (header): every listed window that's still there and isn't minimized.
    func minimizeAll() {
        let items = liveCards()
        guard !items.isEmpty else { return }
        WindowManager.shared.minimize(items)
        acted(.minimizeAll)
        followUp()
    }

    /// Close All (the header's menu, Y-10): every listed window that's still there and has an AX element.
    func closeAll() {
        let items = liveCards()
        guard !items.isEmpty else { return }
        WindowManager.shared.close(items)
        acted(.closeAll)
        followUp()
    }

    /// Hide Safari. The panel hides (`hidApp`).
    func hideApp() {
        guard let app = shownApp, !app.isHidden else { return }
        app.hide()
        acted(.hideApp)
    }

    /// Show Safari, while it's hidden (G2-1). The panel stays and its cards follow.
    func showApp() {
        guard let app = shownApp, app.isHidden else { return }
        app.unhide()
        acted(.showApp)
        followUp()
    }

    /// Quit Safari: `terminate()`, never `forceTerminate()`, so unsaved work asks first (M41). Finder has no Quit.
    /// Snaptic's own header quits the normal way (`LaunchStability.markCleanQuit`), so the next launch isn't counted
    /// as a crash (X-29).
    func quitApp() {
        guard let app = shownApp, app.bundleIdentifier != Self.finderBundleID else { return }
        acted(.quitApp)
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // After this event, so the policy's hide and the menu (if any) finish first.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        } else {
            app.terminate()
        }
    }

    /// The small card's click: like clicking the app in the Dock. It's unhidden, and opens a window if it has none
    /// (`WindowManager.reopen`, G-18).
    func activateApp() {
        guard let app = shownApp else { return }
        if app.isHidden { app.unhide() }
        WindowManager.shared.reopen(app)
        acted(.activateApp)
    }

    /// One action on the shown app; `windowID` names the card for the window actions, and is ignored by the others.
    func perform(_ action: DockAction, on windowID: CGWindowID?) {
        switch action {
        case .raise: if let windowID { raiseWindow(windowID) }
        case .close: if let windowID { closeWindow(windowID) }
        case .minimize: if let windowID { minimizeWindow(windowID) }
        case .restore: if let windowID { restoreWindow(windowID) }
        case .fullScreen: if let windowID { toggleFullScreen(windowID) }
        case .minimizeAll: minimizeAll()
        case .closeAll: closeAll()
        case .hideApp: hideApp()
        case .showApp: showApp()
        case .quitApp: quitApp()
        case .activateApp: activateApp()
        }
    }

    /// A5: a key `DockKeyRules` resolved. The policy hears it (Esc hides the panel), then its action runs on
    /// `windowID`, the card under the pointer, if it names one.
    func perform(_ key: DockKeyAction, on windowID: CGWindowID?) {
        send(.keyHandled(key))
        guard let action = DockPreviewRules.action(for: key) else { return }
        perform(action, on: windowID)
    }

    /// The shown app's pid, while a panel is up or on its way.
    var shownPID: Int32? { showing?.pid }

    /// The shown app is Finder (no Quit) or hidden (Show instead of Hide), as the last build saw it.
    var shownAppIsFinder: Bool { model.isFinder }
    var shownAppIsHidden: Bool { model.appHidden }

    /// What A5's key table needs of a card (`DockKeyTarget.card`); nil if it isn't listed.
    func cardState(_ id: CGWindowID) -> (hasAXElement: Bool, minimized: Bool)? {
        guard let item = showing?.cards.first(where: { $0.id == id }) else { return nil }
        return (item.axElement != nil, item.isMinimized)
    }

    // MARK: Clicks and menus (§4.4)

    private func cardClicked(_ id: CGWindowID, _ button: DockMouseButton) {
        guard let item = showing?.cards.first(where: { $0.id == id }),
              let action = policy.resolveClick(button, on: .card(hasAXElement: item.axElement != nil),
                                               appIsFinder: model.isFinder, now: Self.now)
        else { return }
        perform(action, on: id)
    }

    private func smallCardClicked() {
        guard showing != nil, policy.resolveClick(.left, on: .smallCard, now: Self.now) == .activateApp else { return }
        activateApp()
    }

    /// The header's buttons ignore clicks for 300 ms after a show or a swap (K3's resolver).
    private func headerClicked(_ button: DockHeaderButton) {
        guard showing?.built == true,
              let action = policy.resolveClick(.left, on: .header(button), appIsFinder: model.isFinder, now: Self.now)
        else { return }
        perform(action, on: nil)
    }

    private func hoverButtonClicked(_ id: CGWindowID, _ button: DockHoverButton) {
        guard policy.shownPID != nil, let item = showing?.cards.first(where: { $0.id == id }) else { return }
        perform(DockPreviewRules.action(for: button, minimized: item.isMinimized), on: id)
    }

    /// The card's right-click menu (G-16); Bring Forward only without an AX element (D2-25).
    private func cardMenu(_ id: CGWindowID) -> NSMenu? {
        guard policy.shownPID != nil, let item = showing?.cards.first(where: { $0.id == id }) else { return nil }
        return menu(DockPreviewRules.cardMenu(hasAXElement: item.axElement != nil, minimized: item.isMinimized,
                                              fullScreen: item.isFullscreen, appHidden: model.appHidden,
                                              appIsFinder: model.isFinder), card: id)
    }

    /// The header's right-click menu: its buttons plus Close All (Y-10).
    private func headerMenu() -> NSMenu? {
        guard policy.shownPID != nil, showing?.built == true else { return nil }
        return menu(DockPreviewRules.headerMenu(appHidden: model.appHidden, appIsFinder: model.isFinder), card: nil)
    }

    /// While a menu is open the policy holds the panel and its timers (`ownMenuOpened`); they restart from zero
    /// when it closes. Keys show only while keys work (G2-1).
    private func menu(_ entries: [DockPanelMenuItem], card id: CGWindowID?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let app = model.appName, keys = keysWork
        for entry in entries {
            guard let action = DockPreviewRules.action(for: entry) else {
                menu.addItem(MenuKit.separator())
                continue
            }
            menu.addItem(MenuKit.action(DockPreviewRules.menuTitle(entry, app: app),
                                        key: DockPreviewRules.menuKey(entry, keysWork: keys)) { [weak self] in
                self?.perform(action, on: id)
            })
        }
        let delegate = menuDelegate ?? DockMenuDelegate { [weak self] open in
            self?.send(open ? .ownMenuOpened : .ownMenuClosed)
        }
        menuDelegate = delegate
        menu.delegate = delegate
        return menu
    }

    private func cardHovered(_ id: CGWindowID, _ inside: Bool) {
        if inside {
            hoveredCardID = id
        } else if hoveredCardID == id {
            hoveredCardID = nil
        }
    }

    /// §4.16: into the panel counts at once; out of it only after `focusLeaveDelay`, so moving between two cards
    /// never reads as leaving.
    private func voiceOverFocusChanged(_ focused: Bool) {
        timers.cancel(focusTimer)
        focusTimer = nil
        if focused {
            guard !voiceOverFocused, showing != nil else { return }
            voiceOverFocused = true
            send(.voiceOverFocusInPanel(true))
            return
        }
        guard voiceOverFocused else { return }
        focusTimer = timers.after(Self.focusLeaveDelay) { [weak self] in
            guard let self else { return }
            self.focusTimer = nil
            guard self.voiceOverFocused else { return }
            self.voiceOverFocused = false
            self.send(.voiceOverFocusInPanel(false))
        }
    }

    /// “More windows…”: the same app read again with the whole budget (§4.8, X3-12).
    private func moreWindows() {
        guard var sh = showing, sh.built, !model.readingMore else { return }
        sh.budget = WindowManager.totalBudget
        showing = sh
        model.readingMore = true
        WindowManager.shared.markWindowsDirty(sh.pid)
        read()
    }

    private func acted(_ action: DockAction) {
        lastAction = action
        lastActionAt = Self.now
        send(.actionDone(action))
    }

    /// §4.8: the card's window, checked again just before an action, so a closed or reused id never gets one. A
    /// window that's gone, or now belongs to another app, refreshes the panel instead.
    private func resolve(_ id: CGWindowID) -> WindowItem? {
        guard policy.shownPID != nil, let sh = showing, sh.built,
              let item = sh.cards.first(where: { $0.id == id }) else { return nil }
        guard item.hasRealWindowID else { return item }
        if Self.owners(of: [id])[id] == item.pid { return item }
        send(.windowsChanged(pid: sh.pid))
        return nil
    }

    /// The listed windows that are still there and still the app's (§4.8), for Minimize All and Close All.
    private func liveCards() -> [WindowItem] {
        guard policy.shownPID != nil, let sh = showing, sh.built else { return [] }
        let owners = Self.owners(of: sh.cards.filter(\.hasRealWindowID).map(\.id))
        return sh.cards.filter { !$0.hasRealWindowID || owners[$0.id] == $0.pid }
    }

    /// The owning pid of each window that still exists, in one window-server call (no AX).
    private static func owners(of ids: [CGWindowID]) -> [CGWindowID: pid_t] {
        // A CFArray of raw CGWindowIDs (no callbacks), as `CGWindowListCreateDescriptionFromArray` takes them.
        var pointers: [UnsafeRawPointer?] = ids.compactMap { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard !pointers.isEmpty else { return [:] }
        let array = pointers.withUnsafeMutableBufferPointer { buffer in
            CFArrayCreate(kCFAllocatorDefault, buffer.baseAddress, buffer.count, nil)
        }
        guard let array, let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else {
            return [:]
        }
        var owners: [CGWindowID: pid_t] = [:]
        for entry in list {
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let owner = entry[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            owners[number.uint32Value] = owner.int32Value
        }
        return owners
    }

    /// AX changes land a moment after the action; the policy's refresh reads at once, and this reads once more.
    private func followUp() {
        guard let pid = showing?.pid else { return }
        let gen = generation
        timers.after(Self.followUpDelay) { [weak self] in
            guard let self, gen == self.generation else { return }
            WindowManager.shared.markWindowsDirty(pid)
            self.read()
        }
    }

    private var shownApp: NSRunningApplication? {
        guard policy.shownPID != nil, let pid = showing?.pid else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    /// The setting, the kill switch or A5's tap changed: the header's tooltips and the menus follow.
    private func syncKeysWork() {
        let works = keysWork
        if model.keysWork != works { model.keysWork = works }
    }

    /// §4.1 rule 5's exception: VoiceOver runs and “Show previews while VoiceOver is on” is on (G2-5).
    private var voiceOverPreviews: Bool {
        config.showWithVoiceOver && NSWorkspace.shared.isVoiceOverEnabled
    }

    // MARK: Helpers

    private func isHiddenFromDock(_ pid: Int32?) -> Bool {
        guard let pid, !config.hiddenBundleIDs.isEmpty else { return false }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        return WindowCatalogRules.isHiddenFromDock(bundleID: bundleID, hiddenBundleIDs: config.hiddenBundleIDs)
    }

    /// §4.3: the title, the app name, “Private window” or “Window on another Space”.
    private static func text(_ item: WindowItem, privacy: CatalogPrivacy) -> String {
        switch WindowCatalogRules.dockCardText(item.catalog, privacy: privacy) {
        case .title: return item.title
        case .appName: return item.appName
        case .privateWindow: return L("Private window")
        case .windowOnAnotherSpace: return L("Window on another Space")
        }
    }

    /// §4.3: Minimized > Full screen > On another Space > the display's name (with more than one display).
    private static func badge(_ item: WindowItem, displays: [NSScreen]) -> String? {
        let bounds = item.catalog.bounds
        let middle = NSPoint(x: bounds.midX, y: bounds.midY)
        let display = displays.first { $0.frame.contains(middle) }?.localizedName
        switch WindowCatalogRules.dockBadge(item.catalog, displayName: display, displayCount: displays.count) {
        case nil: return nil
        case .minimized?: return L("Minimized")
        case .fullScreen?: return L("Full screen")
        case .otherSpace?: return L("On another Space")
        case .display(let name)?: return name
        case .hidden?: return L("Hidden")
        case .noWindows?, .windows?: return nil
        }
    }

    /// The Dock's auto-hide setting, read (never written) at each watch.
    private static func dockAutoHides() -> Bool {
        CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false
    }

    /// The screens for K2's geometry, in Cocoa coordinates.
    static func screens() -> [DockScreen] {
        NSScreen.screens.map { screen in
            DockScreen(id: screen.displayID ?? 0, frame: DockRect(screen.frame),
                       visibleFrame: DockRect(screen.visibleFrame), scale: Double(screen.backingScaleFactor),
                       isPrimary: screen.frame.origin == .zero)
        }
    }
}

/// §4.22's preview lines: counts, enums and times only.
struct DockPreviewCounts {
    var shows = 0
    /// Milliseconds from the show command to the panel on screen.
    var lastShowLatency: Double?
    var dismissals: [DockDismissReason: Int] = [:]
    /// Window reads that weren't served from the cache.
    var reads = DockReadTimings()
    var lastWindowCount = 0

    var lines: [String] {
        let latency = lastShowLatency.map { String(format: "%.0f ms", $0) } ?? "none"
        let reasons = DockDismissReason.allCases.compactMap { reason in
            dismissals[reason].map { "\(reason.rawValue) \($0)" }
        }
        var lines = ["Shows: \(shows), last hover-to-show \(latency)",
                     "Dismissals: " + (reasons.isEmpty ? "none" : reasons.joined(separator: ", "))]
        #if DEBUG
        let p95 = reads.p95.map { String(format: "%.1f ms", $0) } ?? "none"
        lines.append("Window reads: \(reads.total), p95 \(p95), last \(lastWindowCount) windows")
        #endif
        return lines
    }
}

/// The panel's right-click menus tell the policy when they open and close (§4.2: the panel and its timers wait).
@MainActor
private final class DockMenuDelegate: NSObject, NSMenuDelegate {
    private let changed: @MainActor (_ open: Bool) -> Void

    init(_ changed: @escaping @MainActor (_ open: Bool) -> Void) {
        self.changed = changed
    }

    func menuWillOpen(_ menu: NSMenu) { changed(true) }
    func menuDidClose(_ menu: NSMenu) { changed(false) }
}

/// The controller's timers: one-shot and repeating, on the main run loop in `.common` modes (H8). Each live one
/// counts in §4.22's `timers`.
@MainActor
private final class DockTimers {
    private struct Entry {
        let timer: Timer
        let repeats: Bool
        let body: @MainActor () -> Void
    }

    private var entries: [Int: Entry] = [:]
    private var next = 0

    @discardableResult
    func after(_ delay: Double, _ body: @escaping @MainActor () -> Void) -> Int {
        add(delay, repeats: false, body)
    }

    func every(_ interval: Double, _ body: @escaping @MainActor () -> Void) -> Int {
        add(interval, repeats: true, body)
    }

    func cancel(_ id: Int?) {
        guard let id, let entry = entries.removeValue(forKey: id) else { return }
        entry.timer.invalidate()
        DockPreviewsModule.liveCount(.timers, up: false)
    }

    func cancelAll() {
        for id in Array(entries.keys) { cancel(id) }
    }

    private func add(_ interval: Double, repeats: Bool, _ body: @escaping @MainActor () -> Void) -> Int {
        next += 1
        let id = next
        let timer = Timer(timeInterval: max(interval.isFinite ? interval : 0, 0), repeats: repeats) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire(id) }
        }
        entries[id] = Entry(timer: timer, repeats: repeats, body: body)
        DockPreviewsModule.liveCount(.timers, up: true)
        RunLoop.main.add(timer, forMode: .common)
        return id
    }

    private func fire(_ id: Int) {
        guard let entry = entries[id] else { return }
        if !entry.repeats { cancel(id) }
        entry.body()
    }
}

private extension DockRect {
    init(_ r: CGRect) {
        self.init(x: Double(r.minX), y: Double(r.minY), width: Double(r.width), height: Double(r.height))
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

private extension DockPoint {
    init(_ p: NSPoint) {
        self.init(x: Double(p.x), y: Double(p.y))
    }
}

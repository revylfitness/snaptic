import Foundation

// The Dock Previews hover machine (lead; PLAN 0.5 §2.4, §4.1, §4.2, §4.4, §4.6, §4.7; X-10–X-12, X-25, X2-10, X2-15,
// X2-23, G2-1, G2-5, Y-11, Y-14, Y-18). A value type: events and `now` in, commands out. Every timer is a
// `schedule(after:token:)` the app turns into a one-shot timer; a `fired(token)` whose token isn't live is ignored.
// Geometry comes in through `DockPolicyGeometry` (K2's `DockGeometry` supplies the real rules).

/// Why the panel hid (§2.4, §4.6). Counted, enum only. Mission Control, App Exposé and Launchpad have no reason: the
/// panel is `.transient` (X-16).
package enum DockDismissReason: String, CaseIterable, Sendable {
    case left
    case safetyNet
    case clickOutside
    case itemClicked
    case dockMenu
    case raised
    case hidApp
    case quitApp
    case escape
    case appTerminated
    case activation
    case space
    case display
    case lock
    case sleep
    case session
    case switcherOpened
    case paused
    case stopped
    case noItem
}

/// One of our own actions on the previewed app (§4.4); `actionDone` reports it after it ran.
package enum DockAction: String, CaseIterable, Sendable {
    /// Bring Forward: a card click.
    case raise
    /// The No open windows card's click.
    case activateApp
    case close
    case minimize
    case restore
    case fullScreen
    case minimizeAll
    case closeAll
    case hideApp
    case showApp
    case quitApp
}

/// A mouse button on a card or the header.
package enum DockMouseButton: String, CaseIterable, Sendable {
    case left
    case middle
}

/// A header button (§4.4).
package enum DockHeaderButton: String, CaseIterable, Sendable {
    case minimizeAll
    case hideApp
    case showApp
    case quitApp
}

/// What a click in the panel landed on.
package enum DockClickTarget: Equatable, Sendable {
    case card(hasAXElement: Bool)
    /// “No open windows” or “No windows shown” (§4.3).
    case smallCard
    case header(DockHeaderButton)
}

package enum DockEvent: Equatable, Sendable {
    case selectionChanged(DockSelection?)
    case pointerMoved(DockPoint)
    /// Where the controller placed the panel (§R4: the corridor and swap intent need the panel's frame).
    case panelPlaced(DockRect)
    case panelEntered
    case panelExited
    case pointerMovedInPanel(DockPoint)
    case panelClicked
    case voiceOverFocusInPanel(Bool)
    case tick
    case fired(token: Int)
    case mouseDownOutside
    case mouseDownOnItem(DockSelection)
    case dragStarted
    case ownMenuOpened
    case ownMenuClosed
    case dockMenuOpened
    case dockMenuClosed
    case appActivated(pid: Int32, byUs: Bool)
    case appTerminated(pid: Int32)
    case spaceChanged
    case displaysChanged
    case locked
    case screensSlept
    case willSleep
    case sessionResigned
    case switcherOpened
    case switcherClosed
    case windowsChanged(pid: Int32)
    case actionDone(DockAction)
    case keyHandled(DockKeyAction)
    case keyNotHandled
    case pauseChanged(DockPauseReason?)
    /// The module stopped (§R4: `stopped` needs an event).
    case moduleStopped
}

package enum DockCommand: Equatable, Sendable {
    case watchPointer(Bool)
    case show(pid: Int32, anchor: DockRect, edge: DockEdge)
    case swap(pid: Int32, anchor: DockRect, edge: DockEdge)
    case hide(DockDismissReason)
    case refresh(pid: Int32)
    case engageKeys(Bool)
    case schedule(after: Double, token: Int)
}

/// The geometry the policy asks for. K2's `DockGeometry` supplies the real rules; `plain` is a fallback that needs
/// no screen.
package struct DockPolicyGeometry: Sendable {
    /// The item's hit band (X2-10): its frame grown along the Dock by half the gap to each neighbour, and stretched
    /// across the Dock to the screen edge.
    package var hitBand: @Sendable (DockSelection) -> DockRect
    /// The edge the Dock sits on, from the settled item frame.
    package var edge: @Sendable (DockSelection) -> DockEdge
    /// The rects one selection adds to the Dock zone (§4.1).
    package var zone: @Sendable (DockSelection) -> [DockRect]
    /// The corridor: the convex hull of the item frame and the panel's near edge, as a polygon.
    package var corridor: @Sendable (_ item: DockRect, _ panel: DockRect, _ edge: DockEdge) -> [DockPoint]

    package init(hitBand: @escaping @Sendable (DockSelection) -> DockRect,
                 edge: @escaping @Sendable (DockSelection) -> DockEdge,
                 zone: @escaping @Sendable (DockSelection) -> [DockRect] = DockPolicyGeometry.plainZone,
                 corridor: @escaping @Sendable (DockRect, DockRect, DockEdge) -> [DockPoint]
                     = DockPolicyGeometry.plainCorridor) {
        self.hitBand = hitBand
        self.edge = edge
        self.zone = zone
        self.corridor = corridor
    }

    /// The zone grows by this much around the hovered item (magnification).
    package static let zoneGrow = 24.0

    package static let plain = DockPolicyGeometry(hitBand: plainHitBand, edge: plainEdge)

    /// The item's frame stretched across the Dock (no neighbour gaps without a screen).
    @Sendable
    package static func plainHitBand(_ s: DockSelection) -> DockRect {
        let item = s.itemFrame, list = s.listFrame
        switch plainEdge(s) {
        case .bottom:
            let y0 = min(list.minY, item.minY), y1 = max(list.maxY, item.maxY)
            return DockRect(x: item.minX, y: y0, width: item.width, height: y1 - y0)
        case .left, .right:
            let x0 = min(list.minX, item.minX), x1 = max(list.maxX, item.maxX)
            return DockRect(x: x0, y: item.minY, width: x1 - x0, height: item.height)
        }
    }

    /// Wide Docks are bottom Docks; a tall Dock is a right Dock when the item grows past its left side.
    @Sendable
    package static func plainEdge(_ s: DockSelection) -> DockEdge {
        if s.listFrame.width >= s.listFrame.height { return .bottom }
        return s.itemFrame.minX < s.listFrame.minX ? .right : .left
    }

    @Sendable
    package static func plainZone(_ s: DockSelection) -> [DockRect] {
        [s.listFrame, s.itemFrame.outset(by: zoneGrow)]
    }

    @Sendable
    package static func plainCorridor(_ item: DockRect, _ panel: DockRect, _ edge: DockEdge) -> [DockPoint] {
        let corners = [DockPoint(x: item.minX, y: item.minY), DockPoint(x: item.maxX, y: item.minY),
                       DockPoint(x: item.maxX, y: item.maxY), DockPoint(x: item.minX, y: item.maxY)]
        return hull(corners + nearCorners(panel, edge))
    }

    /// The panel's two corners nearest the Dock.
    package static func nearCorners(_ panel: DockRect, _ edge: DockEdge) -> [DockPoint] {
        switch edge {
        case .bottom: [DockPoint(x: panel.minX, y: panel.minY), DockPoint(x: panel.maxX, y: panel.minY)]
        case .left: [DockPoint(x: panel.minX, y: panel.minY), DockPoint(x: panel.minX, y: panel.maxY)]
        case .right: [DockPoint(x: panel.maxX, y: panel.minY), DockPoint(x: panel.maxX, y: panel.maxY)]
        }
    }

    /// Convex hull, counter-clockwise (monotone chain).
    package static func hull(_ points: [DockPoint]) -> [DockPoint] {
        let p = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard p.count > 2 else { return p }
        var lower: [DockPoint] = []
        for q in p {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        var upper: [DockPoint] = []
        for q in p.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Inside or on a counter-clockwise convex polygon.
    package static func contains(_ polygon: [DockPoint], _ p: DockPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        for i in polygon.indices where cross(polygon[i], polygon[(i + 1) % polygon.count], p) < 0 { return false }
        return true
    }

    private static func cross(_ o: DockPoint, _ a: DockPoint, _ b: DockPoint) -> Double {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }
}

package struct DockPreviewPolicy: Sendable {
    /// A selection change while the panel is up is held this long while the pointer heads into the panel (§4.2).
    package static let swapHold = 0.12
    /// The motion that decides heading in.
    package static let motionWindow = 0.05
    package static let grace = 0.25
    package static let safetyNet = 1.0
    /// After Hide, Quit or the hovered app quitting, nothing shows until the pointer moves this far (S0-22).
    package static let lockoutDistance = 8.0
    /// The header ignores clicks this long after a show or a swap.
    package static let headerIgnore = 0.3
    /// A selection the pointer doesn't agree with stays pending this long (X2-10).
    package static let agreeWindow = 0.5
    /// With auto-hide, show only after the Dock's frame has been unchanged this long (S0-7's fallback).
    package static let autoHideSettle = 0.1
    /// The Dock zone keeps at most this many rects.
    package static let zoneCap = 64

    private struct Shown: Sendable {
        var selection: DockSelection
        var pid: Int32
        var edge: DockEdge
        var at: Double
    }

    private struct Candidate: Sendable {
        var selection: DockSelection
        var at: Double
        var dueAt: Double
        var agreeBy: Double
        var agreed = false
        /// The last time the pointer was heading into the panel while this swap was held.
        var lastHeadingAt: Double?
    }

    private struct Sample: Sendable {
        var at: Double
        var point: DockPoint
    }

    private enum Timer: Hashable, Sendable {
        case candidate
        case grace
        case safety
    }

    /// The show delay (setting; 0…1 s, 0 is “Immediately”).
    package var delay: Double
    /// The Dock auto-hides.
    package var dockAutoHides: Bool
    package let geometry: DockPolicyGeometry

    private var shown: Shown?
    private var candidate: Candidate?
    private var selection: DockSelection?
    private var pointer: DockPoint?
    private var motion: [Sample] = []
    private var zone: [DockRect] = []
    private var lastOutsideZoneAt = -Double.infinity
    private var lastListFrame: DockRect?
    private var listFrameChangedAt = -Double.infinity
    private var panel: DockRect?
    private var inPanel = false
    private var voiceOverFocus = false
    private var blockedItem: DockSelection?
    private var lockedOut = false
    private var lockoutFrom: DockPoint?
    private var dockMenuOpen = false
    private var ownMenuOpen = false
    private var pausedTimers: Set<Timer> = []
    private var switcherOpen = false
    private var pause: DockPauseReason?
    private var stopped = false
    private var engagement = DockEngagement()
    private var deadlines: [Timer: Double] = [:]
    private var tokens: [Timer: Int] = [:]
    private var nextToken = 0
    private var watching = false
    private var keysEngaged = false

    package init(delay: Double = 0.2, dockAutoHides: Bool = false, geometry: DockPolicyGeometry = .plain) {
        self.delay = delay
        self.dockAutoHides = dockAutoHides
        self.geometry = geometry
    }

    // MARK: Read-only state

    /// The previewed app, while the panel is up.
    package var shownPID: Int32? { shown?.pid }
    /// A show or swap is waiting (delay, agreement, settle or swap intent).
    package var pendingPID: Int32? { candidate?.selection.pid }
    /// Nothing shows until the pointer moves 8 pt or the selection empties.
    package var isLockedOut: Bool { lockedOut }
    /// The latch: this item doesn't show again until the selection leaves it or the pointer leaves the zone.
    package var latchedItem: DockSelection? { blockedItem }
    package var keysEngagedNow: Bool { keysEngaged }

    // MARK: Events

    package mutating func handle(_ event: DockEvent, now: Double) -> [DockCommand] {
        var out: [DockCommand] = []
        if stopped { return out }
        switch event {
        case let .selectionChanged(s): selectionChanged(s, now, &out)
        case let .pointerMoved(p): pointerMoved(p, now, &out)
        case let .panelPlaced(rect):
            panel = rect
            reassess(now, &out)
        case .panelEntered: panelEntered(now, &out)
        case .panelExited:
            inPanel = false
            engagement.exited()
            reassess(now, &out)
        case let .pointerMovedInPanel(p):
            record(p, now)
            if shown != nil {
                inPanel = true
                engagement.moved(to: p, at: now)
            }
        case .panelClicked:
            if shown != nil { engagement.clicked(at: now) }
        case let .voiceOverFocusInPanel(focused): voiceOverFocusChanged(focused, now, &out)
        case .tick:
            engagement.expire(at: now)
            due(now, &out)
        case let .fired(token): fired(token, now, &out)
        case .mouseDownOutside: latch(.clickOutside, item: nil, &out)
        case let .mouseDownOnItem(s): latch(.itemClicked, item: s, &out)
        case .dragStarted: latch(.clickOutside, item: nil, &out)
        case .ownMenuOpened: ownMenuOpened()
        case .ownMenuClosed: ownMenuClosed(now, &out)
        case .dockMenuOpened:
            dockMenuOpen = true
            latch(.dockMenu, item: nil, &out)
        case .dockMenuClosed: dockMenuOpen = false
        case let .appActivated(_, byUs):
            if shown != nil && !byUs { hide(.activation, &out) }
        case let .appTerminated(pid): appTerminated(pid, &out)
        case .spaceChanged: endEverything(.space, &out)
        case .displaysChanged: endEverything(.display, &out)
        case .locked: endEverything(.lock, &out)
        case .screensSlept, .willSleep: endEverything(.sleep, &out)
        case .sessionResigned: endEverything(.session, &out)
        case .switcherOpened:
            switcherOpen = true
            endEverything(.switcherOpened, &out)
        case .switcherClosed: switcherOpen = false
        case let .windowsChanged(pid):
            if shown?.pid == pid { out.append(.refresh(pid: pid)) }
        case let .actionDone(action): actionDone(action, &out)
        case let .keyHandled(key):
            if key == .escape, let s = shown {
                hide(.escape, &out)
                blockedItem = s.selection
            }
        case .keyNotHandled: engagement.notInTable()
        case let .pauseChanged(reason):
            pause = reason
            if reason != nil { endEverything(.paused, &out) }
        case .moduleStopped:
            endEverything(.stopped, &out)
            sync(&out)
            stopped = true
            return out
        }
        sync(&out)
        return out
    }

    /// The card and header click resolver (§4.4): a left click raises, a middle click closes; a card without an AX
    /// element offers only raise; the header ignores clicks for 300 ms after a show or a swap.
    package func resolveClick(_ button: DockMouseButton, on target: DockClickTarget, appIsFinder: Bool = false,
                              now: Double) -> DockAction? {
        guard let s = shown else { return nil }
        switch target {
        case let .card(hasAXElement):
            switch button {
            case .left: return .raise
            case .middle: return hasAXElement ? .close : nil
            }
        case .smallCard:
            return button == .left ? .activateApp : nil
        case let .header(b):
            guard button == .left, Self.isDue(s.at + Self.headerIgnore, now) else { return nil }
            switch b {
            case .minimizeAll: return .minimizeAll
            case .hideApp: return .hideApp
            case .showApp: return .showApp
            case .quitApp: return appIsFinder ? nil : .quitApp
            }
        }
    }

    /// What a card offers (§4.4, D2-25): Bring Forward only without an AX element.
    package static func cardActions(hasAXElement: Bool, minimized: Bool) -> [DockAction] {
        hasAXElement ? [.raise, .close, minimized ? .restore : .minimize, .fullScreen] : [.raise]
    }

    // MARK: Selection and pointer

    private mutating func selectionChanged(_ new: DockSelection?, _ now: Double, _ out: inout [DockCommand]) {
        selection = new
        if let new {
            if new.listFrame != lastListFrame {
                lastListFrame = new.listFrame
                listFrameChangedAt = now
            }
            addZone(new)
        }
        guard pause == nil, !switcherOpen else { return }
        if let b = blockedItem, !(new.map { b.sameItem(as: $0) } ?? false) { blockedItem = nil }
        guard let new, new.showsPanel else {
            if new == nil { clearLockout() }
            dropCandidate(now, &out)
            guard let s = shown else { return }
            if s.selection.byPointer {
                reassess(now, &out)
            } else if !(new == nil && voiceOverFocus) {
                hide(.noItem, &out)
            }
            return
        }
        if let s = shown {
            if s.selection.sameItem(as: new) {
                shown?.selection = new
                if candidate != nil { dropCandidate(now, &out) }
                reassess(now, &out)
                return
            }
            if !s.selection.byPointer {
                hide(.noItem, &out)
                consider(new, now, &out)
                return
            }
        }
        consider(new, now, &out)
    }

    /// Starts a show or swap for a running app's item, or updates the one already pending for it.
    private mutating func consider(_ s: DockSelection, _ now: Double, _ out: inout [DockCommand]) {
        if blockedItem.map({ $0.sameItem(as: s) }) == true || lockedOut || dockMenuOpen {
            dropCandidate(now, &out)
            return
        }
        if var c = candidate, c.selection.sameItem(as: s) {
            c.selection = s
            candidate = c
        } else {
            let due = shown == nil ? now + max(0, delay) : now
            candidate = Candidate(selection: s, at: now, dueAt: due, agreeBy: now + Self.agreeWindow)
        }
        attempt(now, &out)
    }

    private mutating func pointerMoved(_ p: DockPoint, _ now: Double, _ out: inout [DockCommand]) {
        record(p, now)
        if !zoneContains(p) {
            lastOutsideZoneAt = now
            blockedItem = nil
            if let c = candidate, c.selection.byPointer {
                dropCandidate(now, &out)
            }
        }
        if lockedOut {
            if let from = lockoutFrom {
                if p.distance(to: from) >= Self.lockoutDistance {
                    clearLockout()
                    // The current selection is fresh again.
                    if shown == nil, let s = selection, s.showsPanel, pause == nil, !switcherOpen {
                        consider(s, now, &out)
                    }
                }
            } else {
                lockoutFrom = p
            }
        }
        attempt(now, &out)
        reassess(now, &out)
    }

    private mutating func panelEntered(_ now: Double, _ out: inout [DockCommand]) {
        guard shown != nil else { return }
        inPanel = true
        engagement.entered(at: now)
        if let c = candidate, c.selection.byPointer { dropCandidate(now, &out) }
        cancel(.grace)
        cancel(.safety)
    }

    private mutating func voiceOverFocusChanged(_ focused: Bool, _ now: Double, _ out: inout [DockCommand]) {
        voiceOverFocus = focused
        guard !focused, let s = shown, !s.selection.byPointer else { return }
        if !(selection.map { $0.showsPanel && $0.sameItem(as: s.selection) } ?? false) { hide(.noItem, &out) }
    }

    // MARK: Show and swap

    /// Runs the pending show or swap when its delay, agreement, settle and swap intent allow.
    private mutating func attempt(_ now: Double, _ out: inout [DockCommand]) {
        guard var c = candidate, !ownMenuOpen else { return }
        let byPointer = c.selection.byPointer
        if byPointer && c.at < lastOutsideZoneAt {
            dropCandidate(now, &out)
            return
        }
        if byPointer && !c.agreed { c.agreed = agrees(c.selection) }
        candidate = c
        if byPointer && !c.agreed {
            if Self.isDue(c.agreeBy, now) {
                dropCandidate(now, &out)
            } else {
                setTimer(.candidate, at: c.agreeBy, now, &out)
            }
            return
        }
        if !Self.isDue(c.dueAt, now) {
            setTimer(.candidate, at: c.dueAt, now, &out)
            return
        }
        if dockAutoHides && !Self.isDue(listFrameChangedAt + Self.autoHideSettle, now) {
            setTimer(.candidate, at: listFrameChangedAt + Self.autoHideSettle, now, &out)
            return
        }
        if let s = shown, s.selection.byPointer, byPointer {
            if inPanel || pointer.map({ panel?.contains($0) == true }) == true {
                dropCandidate(now, &out)
                return
            }
            if headingIn(now) { c.lastHeadingAt = now }
            candidate = c
            if let h = c.lastHeadingAt, !Self.isDue(h + Self.swapHold, now) {
                setTimer(.candidate, at: h + Self.swapHold, now, &out)
                return
            }
        }
        guard let pid = c.selection.pid else { return }
        candidate = nil
        cancel(.candidate)
        let edge = geometry.edge(c.selection)
        if shown != nil {
            out.append(.swap(pid: pid, anchor: c.selection.itemFrame, edge: edge))
        } else {
            out.append(.show(pid: pid, anchor: c.selection.itemFrame, edge: edge))
        }
        shown = Shown(selection: c.selection, pid: pid, edge: edge, at: now)
        cancel(.grace)
        cancel(.safety)
        reassess(now, &out)
    }

    /// The pointer is in the Dock zone and the item's hit band (X2-10).
    private func agrees(_ s: DockSelection) -> Bool {
        guard let p = pointer else { return false }
        return zoneContains(p) && geometry.hitBand(s).contains(p)
    }

    /// The last 50 ms of motion point into the triangle from the pointer to the panel's two near corners.
    private func headingIn(_ now: Double) -> Bool {
        guard let s = shown, let panel, let last = motion.last, last.at >= now - Self.motionWindow else { return false }
        let recent = motion.filter { $0.at >= last.at - Self.motionWindow }
        var start = recent.first ?? last
        if recent.count < 2, motion.count >= 2 { start = motion[motion.count - 2] }
        let v = DockPoint(x: last.point.x - start.point.x, y: last.point.y - start.point.y)
        guard v.x != 0 || v.y != 0 else { return false }
        let corners = DockPolicyGeometry.nearCorners(panel, s.edge)
        let a = DockPoint(x: corners[0].x - last.point.x, y: corners[0].y - last.point.y)
        let b = DockPoint(x: corners[1].x - last.point.x, y: corners[1].y - last.point.y)
        let ab = a.x * b.y - a.y * b.x
        guard ab != 0 else { return false }
        let av = a.x * v.y - a.y * v.x
        let vb = v.x * b.y - v.y * b.x
        return av * ab >= 0 && vb * ab >= 0
    }

    // MARK: Dismissal

    /// Starts or cancels the grace and the safety net from the pointer's place (pointer mode only).
    private mutating func reassess(_ now: Double, _ out: inout [DockCommand]) {
        guard !ownMenuOpen else { return }
        guard let s = shown, s.selection.byPointer else {
            cancel(.grace)
            cancel(.safety)
            return
        }
        guard let p = pointer else { return }
        let overPanel = inPanel || panel?.contains(p) == true
        let onItem = s.selection.itemFrame.contains(p) || geometry.hitBand(s.selection).contains(p)
        let inCorridor = panel.map {
            DockPolicyGeometry.contains(geometry.corridor(s.selection.itemFrame, $0, s.edge), p)
        } ?? false
        if !overPanel && !onItem && !inCorridor {
            if deadlines[.grace] == nil { setTimer(.grace, at: now + Self.grace, now, &out) }
        } else {
            cancel(.grace)
        }
        if !overPanel && !zoneContains(p) {
            if deadlines[.safety] == nil { setTimer(.safety, at: now + Self.safetyNet, now, &out) }
        } else {
            cancel(.safety)
        }
    }

    private mutating func due(_ now: Double, _ out: inout [DockCommand]) {
        if let d = deadlines[.candidate], Self.isDue(d, now) {
            cancel(.candidate)
            attempt(now, &out)
        }
        if let d = deadlines[.grace], Self.isDue(d, now) {
            hide(graceReason(), &out)
            return
        }
        if let d = deadlines[.safety], Self.isDue(d, now) {
            hide(.safetyNet, &out)
        }
    }

    /// On the Dock but not on a running app: `noItem`. Otherwise the pointer left: `left`.
    private func graceReason() -> DockDismissReason {
        guard let p = pointer, zoneContains(p) else { return .left }
        return selection?.showsPanel == true ? .left : .noItem
    }

    private mutating func fired(_ token: Int, _ now: Double, _ out: inout [DockCommand]) {
        guard let kind = tokens.first(where: { $0.value == token })?.key, let deadline = deadlines[kind] else { return }
        if !Self.isDue(deadline, now) {
            // Early: wait the rest.
            tokens[kind] = nil
            setTimer(kind, at: deadline, now, &out)
            return
        }
        due(now, &out)
    }

    /// The latch (§4.2): hides with `reason` and holds the item until the selection leaves it or the pointer leaves
    /// the Dock zone. A pending show is cancelled.
    private mutating func latch(_ reason: DockDismissReason, item: DockSelection?, _ out: inout [DockCommand]) {
        if let s = shown {
            blockedItem = item ?? s.selection
            hide(reason, &out)
        } else if let c = candidate {
            blockedItem = item ?? c.selection
            dropCandidate(0, &out)
        } else if let item {
            blockedItem = item
        }
    }

    private mutating func ownMenuOpened() {
        guard shown != nil else { return }
        ownMenuOpen = true
        pausedTimers = Set(deadlines.keys)
        for kind in pausedTimers { cancel(kind) }
    }

    /// The timers restart from zero (X-25).
    private mutating func ownMenuClosed(_ now: Double, _ out: inout [DockCommand]) {
        guard ownMenuOpen else { return }
        ownMenuOpen = false
        if pausedTimers.contains(.candidate), var c = candidate {
            c.dueAt = shown == nil ? now + max(0, delay) : now
            c.agreeBy = now + Self.agreeWindow
            if c.lastHeadingAt != nil { c.lastHeadingAt = now }
            candidate = c
        }
        pausedTimers = []
        attempt(now, &out)
        reassess(now, &out)
    }

    private mutating func appTerminated(_ pid: Int32, _ out: inout [DockCommand]) {
        // The Dock reports the next selection after it reflows; until then there's none.
        if selection?.pid == pid { selection = nil }
        if shown?.pid == pid {
            hide(.appTerminated, &out)
            startLockout()
        } else if candidate?.selection.pid == pid {
            dropCandidate(0, &out)
        }
    }

    /// After our own action (§4.4).
    private mutating func actionDone(_ action: DockAction, _ out: inout [DockCommand]) {
        guard let s = shown else { return }
        switch action {
        case .raise, .activateApp:
            hide(.raised, &out)
            blockedItem = s.selection
        case .hideApp:
            hide(.hidApp, &out)
            blockedItem = s.selection
            startLockout()
        case .quitApp:
            hide(.quitApp, &out)
            blockedItem = s.selection
            startLockout()
        case .close, .minimize, .restore, .fullScreen, .minimizeAll, .closeAll, .showApp:
            out.append(.refresh(pid: s.pid))
        }
    }

    /// A Space, display, lock, sleep, session, switcher, pause or stop: hide if up, and drop everything pending.
    private mutating func endEverything(_ reason: DockDismissReason, _ out: inout [DockCommand]) {
        if shown != nil {
            hide(reason, &out)
        } else {
            dropCandidate(0, &out)
            endSession()
        }
        blockedItem = nil
        clearLockout()
    }

    private mutating func hide(_ reason: DockDismissReason, _ out: inout [DockCommand]) {
        out.append(.hide(reason))
        shown = nil
        candidate = nil
        for kind in [Timer.candidate, .grace, .safety] { cancel(kind) }
        inPanel = false
        panel = nil
        voiceOverFocus = false
        ownMenuOpen = false
        pausedTimers = []
        engagement.hidden()
        endSession()
    }

    // MARK: Helpers

    /// A deadline is due at `now`, allowing for the rounding of `now + after` (a timer fires at its deadline).
    private static func isDue(_ deadline: Double, _ now: Double) -> Bool { deadline <= now + 1e-9 }

    private mutating func dropCandidate(_ now: Double, _ out: inout [DockCommand]) {
        guard candidate != nil else { return }
        candidate = nil
        cancel(.candidate)
        if shown == nil { endSession() }
    }

    private mutating func endSession() {
        zone = []
        motion = []
    }

    private mutating func startLockout() {
        lockedOut = true
        lockoutFrom = pointer
    }

    private mutating func clearLockout() {
        lockedOut = false
        lockoutFrom = nil
    }

    private mutating func addZone(_ s: DockSelection) {
        for r in geometry.zone(s) where !zone.contains(r) {
            zone.append(r)
        }
        if zone.count > Self.zoneCap { zone.removeFirst(zone.count - Self.zoneCap) }
    }

    private func zoneContains(_ p: DockPoint) -> Bool {
        if zone.contains(where: { $0.contains(p) }) { return true }
        for s in [selection, shown?.selection].compactMap({ $0 }) where geometry.zone(s).contains(where: { $0.contains(p) }) {
            return true
        }
        return false
    }

    private mutating func record(_ p: DockPoint, _ now: Double) {
        pointer = p
        motion.append(Sample(at: now, point: p))
        // Keep 0.25 s, and always the sample before this one: a move after a rest is measured from the rest.
        while motion.count > 2 && (motion[0].at < now - 0.25 || motion.count > 32) { motion.removeFirst() }
    }

    private mutating func setTimer(_ kind: Timer, at deadline: Double, _ now: Double, _ out: inout [DockCommand]) {
        if deadlines[kind] == deadline, tokens[kind] != nil { return }
        nextToken += 1
        deadlines[kind] = deadline
        tokens[kind] = nextToken
        out.append(.schedule(after: max(0, deadline - now), token: nextToken))
    }

    private mutating func cancel(_ kind: Timer) {
        deadlines[kind] = nil
        tokens[kind] = nil
    }

    /// The pointer monitor and the keys tap follow the state. The monitor also runs while an item is latched or
    /// locked out: both end on the pointer.
    private mutating func sync(_ out: inout [DockCommand]) {
        let watch = !stopped && (shown != nil || candidate != nil || lockedOut || blockedItem != nil)
        if watch != watching {
            watching = watch
            out.append(.watchPointer(watch))
        }
        let keys = shown != nil && engagement.engaged && !switcherOpen && pause == nil
        if keys != keysEngaged {
            keysEngaged = keys
            out.append(.engageKeys(keys))
        }
    }
}

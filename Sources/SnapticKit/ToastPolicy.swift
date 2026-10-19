import Foundation

// Pure decisions behind ToastPresenter (lead; 0.3 PLAN §3.3, R5-1): the queue (one at a time, identical texts
// merged, 8 queued at most, 10 s expiry), action normalization, Recent Notices, suppression, presentation
// detection and guarded-click arming. The app gathers facts (session dictionary, CGWindowList, NSWorkspace) and
// applies these results; times are seconds on one monotonic clock the caller chooses.

package enum ToastRules {
    /// A toast that hasn't been acted on is gone 10 s after it was queued (queued time counts).
    package static let expiry: Double = 10
    /// A toast without actions stays 4 s once shown.
    package static let plainDuration: Double = 4
    /// Every toast that shows stays at least this long.
    package static let minimumDuration: Double = 0.5
    package static let maxQueued = 8
    package static let maxRecent = 10
    package static let maxActions = 2
    package static let maxScalars = 200
    /// A `screensaver.didstart` hint suppresses for at most this long unless ScreenSaverEngine is frontmost (L4).
    package static let screensaverHintSeconds: Double = 10
    /// A window covers a display when it reaches each edge within this many points.
    package static let coverTolerance: Double = 1

    /// At most 2 actions (the first two are kept) and at most one default (the first one marked wins).
    package static func normalizedActions(isDefault: [Bool]) -> (count: Int, defaultIndex: Int?) {
        let count = min(isDefault.count, maxActions)
        return (count, isDefault.prefix(count).firstIndex(of: true))
    }

    /// Recent Notices, newest last: an identical text moves to the end instead of repeating; at most 10.
    package static func appendingRecent(_ text: String, to list: [String]) -> [String] {
        guard !text.isEmpty else { return list }
        var out = list.filter { $0 != text }
        out.append(text)
        if out.count > maxRecent { out.removeFirst(out.count - maxRecent) }
        return out
    }

    /// How long a toast stays once shown: 4 s plain, 10 s with actions, never past its expiry, at least 0.5 s.
    package static func displayDuration(hasActions: Bool, queuedAt: Double, now: Double) -> Double {
        let wanted = hasActions ? expiry : plainDuration
        let left = expiry - max(0, now - queuedAt)
        return max(minimumDuration, min(wanted, left))
    }

    package static func isExpired(queuedAt: Double, now: Double) -> Bool {
        now - queuedAt >= expiry
    }
}

/// What the presenter reads at the moment of use (never from notifications alone, security M2).
package struct ToastSuppressionFacts: Equatable, Sendable {
    /// `CGSSessionScreenIsLocked` in the session dictionary.
    package var locked: Bool
    /// `kCGSSessionOnConsoleKey` is false (fast user switching).
    package var offConsole: Bool
    /// ScreenSaverEngine is the frontmost app (a notification can't fake it).
    package var screensaverFrontmost: Bool
    /// Seconds since a `screensaver.didstart` hint; nil without one (or after `didstop`).
    package var screensaverHintAge: Double?
    /// Some display is in a mirror set (presenting to a projector).
    package var mirroring: Bool
    /// The frontmost app (not Snaptic) has a window covering a whole display.
    package var frontmostCoversDisplay: Bool

    package init(locked: Bool = false, offConsole: Bool = false, screensaverFrontmost: Bool = false,
                 screensaverHintAge: Double? = nil, mirroring: Bool = false, frontmostCoversDisplay: Bool = false) {
        self.locked = locked
        self.offConsole = offConsole
        self.screensaverFrontmost = screensaverFrontmost
        self.screensaverHintAge = screensaverHintAge
        self.mirroring = mirroring
        self.frontmostCoversDisplay = frontmostCoversDisplay
    }

    /// The screensaver runs: its engine is frontmost, or a didstart hint is younger than 10 s.
    package var screensaverRunning: Bool {
        if screensaverFrontmost { return true }
        guard let age = screensaverHintAge else { return false }
        return age >= 0 && age < ToastRules.screensaverHintSeconds
    }

    /// Presenting: a mirror set, or the frontmost app fills a display.
    package var presenting: Bool { mirroring || frontmostCoversDisplay }

    /// Toasts wait (and go to Recent Notices) while locked, off console, in the screensaver or presenting.
    package var isSuppressed: Bool { locked || offConsole || screensaverRunning || presenting }
}

/// Rectangles here are CG global coordinates (top-left origin), like `ScreenRect` elsewhere in Kit.
package enum ToastGeometry {
    /// Cocoa (bottom-left origin, primary screen height `primaryHeight`) → CG global.
    package static func cgRect(cocoaX x: Double, y: Double, width: Double, height: Double,
                               primaryHeight: Double) -> ScreenRect {
        ScreenRect(x: x, y: primaryHeight - (y + height), width: width, height: height)
    }

    /// True when the two rectangles share some area (touching edges don't count).
    package static func intersects(_ a: ScreenRect, _ b: ScreenRect) -> Bool {
        guard a.width > 0, a.height > 0, b.width > 0, b.height > 0 else { return false }
        return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
    }

    /// The window reaches every edge of the display (1 pt tolerance).
    package static func covers(_ window: ScreenRect, display: ScreenRect) -> Bool {
        guard display.width > 0, display.height > 0 else { return false }
        let t = ToastRules.coverTolerance
        return window.x <= display.x + t && window.y <= display.y + t
            && window.x + window.width >= display.x + display.width - t
            && window.y + window.height >= display.y + display.height - t
    }

    /// Any of the frontmost app's windows covers any display.
    package static func anyCovers(windows: [ScreenRect], displays: [ScreenRect]) -> Bool {
        windows.contains { w in displays.contains { covers(w, display: $0) } }
    }
}

/// A window listed above the toast panel (`CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, panel)`).
package struct ToastWindowAbove: Equatable, Sendable {
    package var bounds: ScreenRect
    package var alpha: Double
    package var ownerPID: Int32

    package init(bounds: ScreenRect, alpha: Double, ownerPID: Int32) {
        self.bounds = bounds
        self.alpha = alpha
        self.ownerPID = ownerPID
    }
}

/// Guarded clicks (security L2, R5-1): a click is ignored, not queued, before the arm delay has passed since the
/// panel showed this content, and while another process's visible window overlaps the panel.
package enum ToastClickPolicy {
    /// Another process's window with alpha > 0 intersects the panel. A list that can't be read counts as
    /// overlapped (fail closed).
    package static func isOverlapped(panel: ScreenRect, above: [ToastWindowAbove]?, ownPID: Int32) -> Bool {
        guard let above else { return true }
        return above.contains { $0.ownerPID != ownPID && $0.alpha > 0 && ToastGeometry.intersects($0.bounds, panel) }
    }

    /// Unguarded toasts (nil `armDelay`) accept every click. A clock that went backwards counts as not armed.
    package static func accepts(armDelay: Double?, shownAt: Double, now: Double, overlapped: Bool) -> Bool {
        guard let armDelay else { return true }
        let elapsed = now - shownAt
        return elapsed >= 0 && elapsed >= armDelay && !overlapped
    }
}

/// The toast queue: one shows at a time, the rest wait in order; identical texts merge; at most 8 wait (the
/// oldest is evicted); a toast that waited 10 s expires unseen. Ids are the model's own serials.
package struct ToastQueueModel: Equatable, Sendable {
    package struct Entry: Equatable, Sendable {
        package let id: UInt64
        package let text: String
        package let hasActions: Bool
        package let queuedAt: Double
    }

    package enum Offer: Equatable, Sendable {
        /// Nothing left after cleaning.
        case empty
        /// Same text as the toast showing or one waiting: nothing new is queued.
        case merged
        /// Not queued: notices wait in Recent Notices.
        case suppressed
        /// Queued as `id`; `evicted` was dropped to make room.
        case queued(id: UInt64, evicted: UInt64?)

        /// Whether the text belongs in Recent Notices (when the caller asked to remember it).
        package var addsToRecent: Bool {
            switch self {
            case .suppressed, .queued: return true
            case .empty, .merged: return false
            }
        }
    }

    package private(set) var queue: [Entry] = []
    package private(set) var current: Entry?
    private var serial: UInt64 = 0

    package init() {}

    /// `text` is already cleaned. `suppressed` is asked only when the text would otherwise be queued.
    package mutating func offer(_ text: String, hasActions: Bool, now: Double, suppressed: () -> Bool) -> Offer {
        guard !text.isEmpty else { return .empty }
        if current?.text == text || queue.contains(where: { $0.text == text }) { return .merged }
        if suppressed() { return .suppressed }
        var evicted: UInt64?
        if queue.count >= ToastRules.maxQueued { evicted = queue.removeFirst().id }
        serial &+= 1
        queue.append(Entry(id: serial, text: text, hasActions: hasActions, queuedAt: now))
        return .queued(id: serial, evicted: evicted)
    }

    /// Removes a waiting toast (its lifetime ended). False when it wasn't waiting.
    package mutating func removeQueued(_ id: UInt64) -> Bool {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return false }
        queue.remove(at: index)
        return true
    }

    /// When nothing shows: drops the toasts that expired while waiting, then (unless suppressed) makes the oldest
    /// one current. `suppressed` is asked only when there is one to show.
    package mutating func next(now: Double, suppressed: () -> Bool) -> (presented: Entry?, expired: [UInt64]) {
        guard current == nil else { return (nil, []) }
        let expired = queue.filter { ToastRules.isExpired(queuedAt: $0.queuedAt, now: now) }.map(\.id)
        queue.removeAll { ToastRules.isExpired(queuedAt: $0.queuedAt, now: now) }
        guard !queue.isEmpty, !suppressed() else { return (nil, expired) }
        let entry = queue.removeFirst()
        current = entry
        return (entry, expired)
    }

    /// The showing toast goes away; returns it.
    package mutating func finishCurrent() -> Entry? {
        defer { current = nil }
        return current
    }

    /// Everything goes (quit, Safe Mode): the showing toast first, then the waiting ones in order.
    package mutating func removeAll() -> [UInt64] {
        let ids = (current.map { [$0.id] } ?? []) + queue.map(\.id)
        current = nil
        queue = []
        return ids
    }
}

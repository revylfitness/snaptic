import Foundation

// Dock Previews' reader rules (lead; PLAN 0.5 §4.8, A3): what `DockObserver` and `DockReader` decide without AX. The
// app reads the Dock and the running apps, converts what it read into these, and passes `now` in (monotonic
// seconds). Kit never sees an AXUIElement or a clock.

/// A running app as the item → app match sees it (§4.8, X-28).
package struct DockRunningApp: Equatable, Sendable {
    package var pid: Int32
    /// `NSRunningApplication.bundleURL`'s path.
    package var bundlePath: String?
    package var bundleID: String?
    /// `NSRunningApplication.localizedName`.
    package var name: String?

    package init(pid: Int32, bundlePath: String?, bundleID: String?, name: String?) {
        self.pid = pid
        self.bundlePath = bundlePath
        self.bundleID = bundleID
        self.name = name
    }
}

package enum DockReaderRules {
    /// What a Dock list child is, from its AX subrole (§4.1 rule 3). Spacers count as separators; URL items (web
    /// links) and anything unknown are `other`.
    package static func kind(subrole: String?) -> DockItemKind {
        switch subrole {
        case "AXApplicationDockItem": return .app
        case "AXFolderDockItem": return .folder
        case "AXTrashDockItem": return .trash
        case "AXMinimizedWindowDockItem": return .minimizedWindow
        case "AXSeparatorDockItem", "AXSpacerDockItem": return .separator
        default: return .other
        }
    }

    /// A file path without trailing slashes ("/" stays), so `…/Safari.app/` and `…/Safari.app` match.
    package static func normalizedPath(_ path: String) -> String {
        var p = Substring(path)
        while p.count > 1, p.hasSuffix("/") { p = p.dropLast() }
        return String(p)
    }

    /// The pid of the app a Dock item stands for (§4.8, X-28; §R4 S0-1), or nil.
    /// - Only an item whose `AXIsApplicationRunning` is 1 maps: tiles of apps that aren't running can share a
    ///   running app's URL.
    /// - Then, in order: the item's URL path against each app's bundle path; the bundle id from that URL's
    ///   `Info.plist` (read only when the path found nothing) against each app's bundle id, ignoring case; the item's
    ///   title against each app's name, which must match exactly one app.
    /// - Two apps at one bundle path or with one bundle id (copies launched twice) go to the lowest pid.
    package static func pid(running: Bool?, urlPath: String?, title: String?, apps: [DockRunningApp],
                            bundleIDAtURL: () -> String?) -> Int32? {
        guard running == true else { return nil }
        if let urlPath, !urlPath.isEmpty {
            let path = normalizedPath(urlPath)
            let byPath = apps.filter { $0.bundlePath.map(normalizedPath) == path }.map(\.pid)
            if let pid = byPath.min() { return pid }
            if let id = bundleIDAtURL()?.lowercased(), !id.isEmpty {
                let byID = apps.filter { $0.bundleID?.lowercased() == id }.map(\.pid)
                if let pid = byID.min() { return pid }
            }
        }
        if let title, !title.isEmpty {
            let byName = apps.filter { $0.name == title }
            if byName.count == 1 { return byName[0].pid }
        }
        return nil
    }

    /// The `allowUntitled` part of `windows(for:budget:allowUntitled:)` (§2.6): an untitled window read only from
    /// `CGWindowList` is listed only when the caller allows it. The read itself always uses `CatalogInclusion.dock`.
    package static func listed(_ w: CatalogWindow, allowUntitled: Bool) -> Bool {
        allowUntitled || w.hasAXElement || w.hasTitle
    }

    /// §4.8: when AX can't read the app in time (a timeout), its on-screen windows are listed from `CGWindowList`
    /// alone (titles only). The shared inclusion rule leaves these out, because AX normally lists them; this applies
    /// its list-only checks instead: a real id, layer 0, on screen, the list minimum size, not transparent, titled
    /// unless untitled ones are allowed.
    package static func listedOnTimeout(_ w: CatalogWindow, options: CatalogInclusion) -> Bool {
        guard !w.hasAXElement, w.hasRealID, w.layer == 0, w.onScreen, w.alpha > 0,
              WindowCatalogRules.sizeLeftOut(width: w.bounds.width, height: w.bounds.height,
                                             minimum: options.minListSide) == nil else { return false }
        return w.hasTitle || options.allowUntitled
    }
}

/// The back-off (§4.8): three timeouts within 10 s pause reads for 1 s. Each pause is one `dockSlow`.
package struct DockReadBackoff: Equatable, Sendable {
    package static let window: Double = 10
    package static let limit = 3
    package static let pause: Double = 1

    package private(set) var timeouts: [Double] = []
    package private(set) var pausedUntil: Double?
    /// How many pauses there were (`dockSlow`, §4.22).
    package private(set) var slowCount = 0

    package init() {}

    /// A read timed out at `now`. The third within 10 s starts a pause and clears the count.
    package mutating func timedOut(now: Double) {
        timeouts = timeouts.filter { now - $0 < Self.window }
        timeouts.append(now)
        guard timeouts.count >= Self.limit else { return }
        timeouts = []
        pausedUntil = now + Self.pause
        slowCount += 1
    }

    /// Seconds to wait before the next read; 0 to read now.
    package func wait(now: Double) -> Double {
        guard let pausedUntil, pausedUntil > now else { return 0 }
        return pausedUntil - now
    }
}

/// The re-attach ladder (§4.8, X-17, X2-16).
package enum DockReattachLadder {
    /// Seconds before each attempt after the first one failed.
    package static let steps: [Double] = [0.1, 0.25, 0.5, 1, 2]
    /// Added within `loginWindow` seconds of login, while the Dock may still be starting.
    package static let loginSteps: [Double] = [5, 10]
    package static let loginWindow: Double = 120
    /// After the ladder, and while attached, the health check runs this often.
    package static let healthInterval: Double = 30
    /// After a rebuild (wake, unlock, session-active, a display change) the list is checked again this long after
    /// the attach, because the Dock can rebuild its `AXList` after the notification (S0-3: previews within 2 s).
    package static let rebuildChecks: [Double] = [0.5, 1.5]

    /// The wait before retry `attempt` (0 is the first retry), or nil once the ladder has ended and the health check
    /// takes over. `sinceLogin`: seconds since login, or nil when unknown.
    package static func delay(attempt: Int, sinceLogin: Double?) -> Double? {
        let ladder = (sinceLogin.map { $0 >= 0 && $0 < loginWindow } ?? false) ? steps + loginSteps : steps
        guard attempt >= 0, attempt < ladder.count else { return nil }
        return ladder[attempt]
    }
}

/// The 30 s health check's verdict (§4.8, D2-4).
package enum DockHealthVerdict: String, Equatable, Sendable {
    case ok
    /// The observer is dead without having said so: re-attach and count `observer.silentReattach`.
    case silentDeath
}

package enum DockHealthRules {
    /// - `listValid`: the `AXList` still answers (not `kAXErrorInvalidUIElement`).
    /// - `pointer`, `lastDockFrame`: the pointer and the last Dock frame read, in AppKit global coordinates.
    /// - `selectionSame`: the selected child AX reports now is the last one notified (`CFEqual`; both nil counts).
    package static func verdict(listValid: Bool, pointer: DockPoint?, lastDockFrame: DockRect?,
                                selectionSame: Bool) -> DockHealthVerdict {
        guard listValid else { return .silentDeath }
        if let pointer, let lastDockFrame, !lastDockFrame.isDegenerate, lastDockFrame.contains(pointer),
           !selectionSame {
            return .silentDeath
        }
        return .ok
    }
}

/// What the Dock observer has done since the module started (§4.22). Counts, booleans and enums only.
package struct DockObserverStats: Equatable, Sendable {
    /// An `AXObserver` is registered on the Dock's list now.
    package private(set) var attached = false
    /// What `DockPageFacts.read` takes (§4.17 rows 5 and 9).
    package private(set) var read: DockReadState = .starting
    /// The ladder ran out of steps without attaching (`DockPageFacts.loginLadderEnded`).
    package private(set) var ladderEnded = false
    /// When the Dock was first found unreadable since the last attach (`DockPageFacts.unreadableSince`).
    package private(set) var unreadableSince: Double?
    /// Attaches to a Dock process other than the one attached before (a Dock restart).
    package private(set) var reattaches = 0
    /// Re-attaches the health check started (`observer.silentReattach`).
    package private(set) var silentReattaches = 0
    /// Rebuilds on wake, unlock, session-active or a display change, with the same Dock process or not.
    package private(set) var rebuilds = 0
    /// Back-off pauses (`dockSlow`).
    package var dockSlow = 0
    /// Selections read (an item under the pointer; the at-rest empty selection doesn't count).
    package private(set) var selections = 0
    package private(set) var lastKind: DockItemKind?
    /// The Dock process last attached to.
    package private(set) var attachedPID: Int32?

    package init() {}

    package mutating func didAttach(pid: Int32) {
        if let attachedPID, attachedPID != pid { reattaches += 1 }
        attachedPID = pid
        attached = true
        read = .attached
        ladderEnded = false
        unreadableSince = nil
    }

    /// The observer is gone (the Dock quit, or a rebuild is about to attach again).
    package mutating func didDetach() {
        attached = false
    }

    /// An attach attempt failed. `ladderEnded`: no step is left.
    package mutating func attachFailed(now: Double, ladderEnded ended: Bool) {
        attached = false
        read = .unreadable
        if unreadableSince == nil { unreadableSince = now }
        if ended { ladderEnded = true }
    }

    package mutating func didRebuild() { rebuilds += 1 }

    package mutating func didSilentReattach() { silentReattaches += 1 }

    package mutating func didRead(_ selection: DockSelection?) {
        guard let selection else { return }
        selections += 1
        lastKind = selection.kind
    }

    /// §4.22's observer lines. `observerLive`: the module holds an observer (`DockLive.observer` > 0).
    package func diagnosticsLines(observerLive: Bool) -> [String] {
        [
            "Observer attached: " + (observerLive && attached ? "yes" : "no"),
            "Dock read: " + (observerLive ? read.rawValue : "none"),
            "Re-attaches: \(reattaches)",
            "Silent re-attaches: \(silentReattaches)",
            "Observer rebuilds: \(rebuilds)",
            "Dock slow: \(dockSlow)",
            "Selections: \(selections)",
            "Last item kind: " + (lastKind?.rawValue ?? "none"),
        ]
    }
}

/// `WindowManager.windows(for:budget:allowUntitled:)`'s timings (§4.8).
package enum DockWindowCacheTiming {
    /// A read is reused for this long unless the freshness lease marks it dirty.
    package static let ttl: Double = 2
    /// An app that timed out isn't read through AX again for this long.
    package static let timeoutSkip: Double = 30
}

/// The per-app window read cache (§4.8): 2 s, marked dirty by the freshness lease, and the 30 s skip after a timeout.
package struct DockWindowCache<Value> {
    private var entries: [Int32: (value: Value, at: Double, dirty: Bool)] = [:]
    private var skippedUntil: [Int32: Double] = [:]

    package init() {}

    /// The cached read, while it's under 2 s old and not dirty.
    package func value(for pid: Int32, now: Double) -> Value? {
        guard let entry = entries[pid], !entry.dirty, now >= entry.at,
              now - entry.at < DockWindowCacheTiming.ttl else { return nil }
        return entry.value
    }

    package mutating func store(_ value: Value, for pid: Int32, now: Double) {
        entries[pid] = (value, now, false)
    }

    /// The app opened, closed, minimized, restored or retitled a window.
    package mutating func markDirty(_ pid: Int32) {
        entries[pid]?.dirty = true
    }

    /// The read couldn't read even the first window: skip AX for this app for 30 s.
    package mutating func timedOut(_ pid: Int32, now: Double) {
        skippedUntil[pid] = now + DockWindowCacheTiming.timeoutSkip
    }

    package func isSkipped(_ pid: Int32, now: Double) -> Bool {
        guard let until = skippedUntil[pid] else { return false }
        return now < until
    }

    /// Drops reads past their 2 s and skips past their 30 s.
    package mutating func prune(now: Double) {
        entries = entries.filter { !$0.value.dirty && now >= $0.value.at && now - $0.value.at < DockWindowCacheTiming.ttl }
        skippedUntil = skippedUntil.filter { now < $0.value }
    }

    package mutating func removeAll() {
        entries = [:]
        skippedUntil = [:]
    }

    package var count: Int { entries.count }
    package var skippedCount: Int { skippedUntil.count }
}

/// The last 100 window-read durations, for the p95 the DEBUG diagnostics show (S0-23).
package struct DockReadTimings: Equatable, Sendable {
    package static let capacity = 100
    package private(set) var samples: [Double] = []
    package private(set) var total = 0

    package init() {}

    package mutating func add(_ milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        samples.append(milliseconds)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
        total += 1
    }

    /// The nearest-rank 95th percentile of the kept samples, or nil with none.
    package var p95: Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = (sorted.count * 95 + 99) / 100
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }
}

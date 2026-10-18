import Foundation

// Automatic-plan rate limits (owner: B). Invariant 6: per plan, not per change; at most one
// plan per 2 s globally and three per display per 60 s. Visibility-restoring work bypasses
// both and isn't counted. Times are uptime seconds.

package struct RateLimiter: Codable, Equatable, Sendable {
    package enum Kind: String, Codable, Sendable {
        case automatic
        /// Re-enable, raise the floor, kill or un-mirror an orphaned host.
        case visibilityRestore
    }

    package var globalInterval: Double = 2
    package var perDisplayLimit: Int = 3
    package var perDisplayWindow: Double = 60

    private var lastGlobal: Double?
    private var perDisplay: [String: [Double]] = [:]

    package init() {}

    package init(globalInterval: Double, perDisplayLimit: Int, perDisplayWindow: Double) {
        self.globalInterval = globalInterval
        self.perDisplayLimit = perDisplayLimit
        self.perDisplayWindow = perDisplayWindow
    }

    /// Whether a plan touching `displays` (fingerprints) may run now.
    package func allows(displays: [String], at now: Double, kind: Kind = .automatic) -> Bool {
        if kind == .visibilityRestore { return true }
        if let last = lastGlobal, now - last < globalInterval, now >= last { return false }
        for d in Set(displays) {
            let recent = (perDisplay[d] ?? []).filter { now - $0 < perDisplayWindow && now >= $0 }
            if recent.count >= perDisplayLimit { return false }
        }
        return true
    }

    /// Counts a plan that ran (visibility restores are never counted).
    package mutating func record(displays: [String], at now: Double, kind: Kind = .automatic) {
        guard kind == .automatic else { return }
        lastGlobal = now
        for d in Set(displays) {
            var list = (perDisplay[d] ?? []).filter { now - $0 < perDisplayWindow && now >= $0 }
            list.append(now)
            perDisplay[d] = list
        }
        // Bound memory: drop displays with no recent plans.
        let window = perDisplayWindow
        perDisplay = perDisplay.filter { entry in entry.value.contains { t in now - t < window } }
    }

    /// allows + record in one step. Returns false (and records nothing) when limited.
    package mutating func consume(displays: [String], at now: Double, kind: Kind = .automatic) -> Bool {
        guard allows(displays: displays, at: now, kind: kind) else { return false }
        record(displays: displays, at: now, kind: kind)
        return true
    }

    /// Seconds until a plan for `displays` would be allowed (0 if now).
    package func retryAfter(displays: [String], at now: Double) -> Double {
        var wait = 0.0
        if let last = lastGlobal, now >= last { wait = max(wait, globalInterval - (now - last)) }
        for d in Set(displays) {
            let recent = (perDisplay[d] ?? []).filter { now - $0 < perDisplayWindow && now >= $0 }.sorted()
            if recent.count >= perDisplayLimit, let oldest = recent.first {
                wait = max(wait, perDisplayWindow - (now - oldest))
            }
        }
        return max(0, wait)
    }
}

/// At most one send per `interval`, always ending on the latest value (the OSD broadcast's
/// ≤ 10/s, FIXES-R3 9). A value offered inside the window waits for one timer; a value sent
/// right away clears whatever was waiting, so an older value is never sent after a newer one.
/// Times are uptime seconds.
package struct LatestValueThrottle: Equatable, Sendable {
    package enum Decision: Equatable, Sendable {
        /// Send this value now; cancel any outstanding timer.
        case sendNow
        /// Keep this value; start a timer firing after `seconds` (none is outstanding).
        case schedule(seconds: Double)
        /// Keep this value; the outstanding timer will send it.
        case coalesced
    }

    package let interval: Double
    package private(set) var lastSent: Double?
    /// A value is waiting for the timer.
    package private(set) var hasPending = false
    /// A timer is outstanding.
    package private(set) var isScheduled = false

    package init(interval: Double) { self.interval = max(0, interval) }

    // The window test and the delay use the same expression (`last + interval`), so a value
    // inside the window always gets a delay > 0 (no zero-second timer spinning).

    package mutating func offer(at now: Double) -> Decision {
        if let last = lastSent, now >= last, now < last + interval {
            hasPending = true
            if isScheduled { return .coalesced }
            isScheduled = true
            return .schedule(seconds: last + interval - now)
        }
        lastSent = now
        hasPending = false
        isScheduled = false
        return .sendNow
    }

    /// The timer fired: `.sendNow` sends the waiting value, `.schedule` re-arms a timer that
    /// fired early (clock skew), nil means there's nothing to do.
    package mutating func timerFired(at now: Double) -> Decision? {
        guard isScheduled else { return nil }
        isScheduled = false
        guard hasPending else { return nil }
        if let last = lastSent, now >= last, now < last + interval {
            isScheduled = true
            return .schedule(seconds: last + interval - now)
        }
        hasPending = false
        lastSent = now
        return .sendNow
    }

    /// Drop anything waiting (feature off, Displays stopping).
    package mutating func reset() {
        hasPending = false
        isScheduled = false
    }
}

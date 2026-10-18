import Foundation

// Rule evaluation (owner: G; PLAN 0.3 §2.7 "Facts and evaluation"). Facts come from J's sources; nil = unknown.
// Hysteresis is in memory on the continuous clock (N2); suppressions are persisted in the snapshot.

package struct DisplayFact: Equatable, Sendable {
    package var record: FingerprintRecord
    package var isBuiltin: Bool
    package init(record: FingerprintRecord, isBuiltin: Bool) {
        self.record = record
        self.isBuiltin = isBuiltin
    }
}

package struct USBFact: Equatable, Sendable {
    package var vendor: Int
    package var product: Int
    package var serialHash: String?
    package init(vendor: Int, product: Int, serialHash: String?) {
        self.vendor = vendor
        self.product = product
        self.serialHash = serialHash
    }
}

package struct NetworkFacts: Equatable, Sendable {
    package var addresses: [String]
    package var routerHashes: Set<String>
    package var vpn: Bool
    package init(addresses: [String], routerHashes: Set<String>, vpn: Bool) {
        self.addresses = addresses
        self.routerHashes = routerHashes
        self.vpn = vpn
    }
}

package struct BluetoothFact: Equatable, Sendable {
    package var audioUIDHashes: Set<String>
    package var inputHashes: Set<String>
    package init(audioUIDHashes: Set<String>, inputHashes: Set<String>) {
        self.audioUIDHashes = audioUIDHashes
        self.inputHashes = inputHashes
    }
}

/// nil = the source isn't running or hasn't produced a value yet ("unknown").
package struct CriterionFacts: Equatable, Sendable {
    package var runningApps: Set<String>?
    /// nil = unknown; .some(nil) = no frontmost app.
    package var frontmostApp: String??
    package var displays: [DisplayFact]?
    package var mirroring: Bool?
    package var power: PowerFacts?
    /// 0..<10080, local time, computed by the app with Calendar.autoupdatingCurrent (0 = Sunday 00:00).
    package var minuteOfWeek: Int?
    package var cpuPercent: Double?
    package var audioOutput: Bool?
    package var microphone: Bool?
    package var realIdleSeconds: Double?
    package var volumes: Set<String>?
    package var usb: [USBFact]?
    package var network: NetworkFacts?
    package var throughputKBps: Double?
    package var bluetooth: BluetoothFact?

    package init() {}
}

/// In memory only, continuous clock.
package struct TriggerHysteresis: Equatable, Sendable {
    package var trueSince: Double?
    package var falseSince: Double?
    package var active: Bool
    /// When the debounced condition became active (nil while inactive).
    package var activeSince: Double?
    package init() {
        trueSince = nil
        falseSince = nil
        active = false
        activeSince = nil
    }
}

/// Persisted in the snapshot (same boot only for `until`).
package struct TriggerSuppression: Codable, Equatable, Sendable {
    package var until: Double?
    package var untilFalse: Bool

    package init(until: Double?, untilFalse: Bool) {
        self.until = until
        self.untilFalse = untilFalse
    }

    private enum CodingKeys: String, CodingKey { case until, untilFalse }

    /// Lossy per field (rule 9).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        until = c.lossy(.until, nil)
        untilFalse = c.lossy(.untilFalse, false)
    }

    /// Still suppressing at `now`.
    package func isActive(now: Double) -> Bool {
        if untilFalse { return true }
        if let u = until, u.isFinite, u > now { return true }
        return false
    }
}

package struct TriggerStepResult: Equatable, Sendable {
    package var hysteresis: [StableID: TriggerHysteresis]
    /// Expired ones removed.
    package var suppressions: [StableID: TriggerSuppression]
    package var top: TriggerTop?
    /// Continuous instant of the next delay expiry.
    package var nextDeadline: Double?

    package init(hysteresis: [StableID: TriggerHysteresis], suppressions: [StableID: TriggerSuppression],
                 top: TriggerTop?, nextDeadline: Double?) {
        self.hysteresis = hysteresis
        self.suppressions = suppressions
        self.top = top
        self.nextDeadline = nextDeadline
    }
}

package enum TriggerEngine {
    /// "Pause Rules" for `seconds` (clamped to 60 s…`limit`) from `now` (wall). From the command line a pause may only
    /// be extended (security S-3: resuming rules is never a CLI action): the later of the running pause and the new
    /// end, so `snaptic awake pause 1m` during a pause until tomorrow changes nothing.
    package static func pausedUntil(current: Double?, now: Double, seconds: Double, limit: Double,
                                    onlyExtend: Bool) -> Double {
        let s = min(max(seconds.isFinite ? seconds : 60, 60), max(60, limit))
        let next = now + s
        guard onlyExtend, let current, current.isFinite, current > now else { return next }
        return max(current, next)
    }

    /// true / false / nil (unknown). Negation of unknown stays unknown.
    package static func holds(_ entry: AwakeCriterionEntry, facts: CriterionFacts) -> Bool? {
        guard let v = value(entry.criterion, facts: facts) else { return nil }
        return entry.negated ? !v : v
    }

    private static func value(_ criterion: AwakeCriterion, facts: CriterionFacts) -> Bool? {
        switch criterion {
        case .app(let bundleID, _, let frontmost):
            if frontmost {
                guard let front = facts.frontmostApp else { return nil }
                return front == bundleID
            }
            return facts.runningApps.map { $0.contains(bundleID) }
        case .display(let match):
            switch match {
            case .anyExternal:
                return facts.displays.map { $0.contains { !$0.isBuiltin } }
            case .specific(let record, _):
                return facts.displays.map { $0.contains { Fingerprint.matches(record, $0.record) } }
            case .mirroring:
                return facts.mirroring
            }
        case .power(let condition):
            guard let p = facts.power else { return nil }
            switch condition {
            case .onAdapter: return p.onAC
            case .onBattery: return p.batteryPresent && !p.onAC
            case .charging: return p.batteryPresent && p.charging
            case .batteryAtLeast(let n):
                guard p.batteryPresent else { return false }
                return p.percent.map { $0 >= n }
            }
        case .schedule(let days, let start, let end):
            guard let mow = facts.minuteOfWeek, (0..<10_080).contains(mow) else { return nil }
            let day = mow / 1_440, minute = mow % 1_440
            let s = AwakeMath.clamp(start, 0...1_439), e = AwakeMath.clamp(end, 0...1_439)
            if s < e { return days.contains(day: day) && minute >= s && minute < e }
            return (days.contains(day: day) && minute >= s) || (days.contains(day: day - 1) && minute < e)
        case .cpuAbove(let percent):
            return facts.cpuPercent.map { $0.isFinite && $0 > Double(percent) }
        case .audio(let condition):
            switch condition {
            case .outputActive: return facts.audioOutput
            case .microphoneActive: return facts.microphone
            }
        case .idle(let minutes):
            return facts.realIdleSeconds.map { $0.isFinite && $0 >= Double(minutes) * 60 }
        case .volumeMounted(let uuid, _):
            let wanted = uuid.uppercased()
            return facts.volumes.map { $0.contains { $0.uppercased() == wanted } }
        case .usbDevice(let vendor, let product, let serialHash, _):
            return facts.usb.map { devices in
                devices.contains { $0.vendor == vendor && $0.product == product && (serialHash == nil || $0.serialHash == serialHash) }
            }
        case .network(let condition):
            guard let n = facts.network else { return nil }
            switch condition {
            case .subnet(let cidr): return n.addresses.contains { NetworkMath.cidrContains(cidr, address: $0) }
            case .router(let hash, _): return n.routerHashes.contains(hash)
            case .vpnConnected: return n.vpn
            }
        case .networkActivity(let kbps):
            return facts.throughputKBps.map { $0.isFinite && $0 >= Double(kbps) }
        case .bluetooth(let match):
            guard let b = facts.bluetooth else { return nil }
            switch match {
            case .audio(let h, _): return b.audioUIDHashes.contains(h)
            case .input(let h, _): return b.inputHashes.contains(h)
            case .anyAudio: return !b.audioUIDHashes.isEmpty
            }
        }
    }

    /// all: every entry true (unknown → false). any: some entry true (unknowns ignored). No criteria → false.
    package static func condition(_ t: AwakeTrigger, facts: CriterionFacts) -> Bool {
        guard !t.criteria.isEmpty else { return false }
        switch t.match {
        case .all: return t.criteria.allSatisfy { holds($0, facts: facts) == true }
        case .any: return t.criteria.contains { holds($0, facts: facts) == true }
        }
    }

    /// Advances hysteresis for every trigger (disabled, suppressed, paused and guard-held ones too, so they resume
    /// correctly) and returns the governing candidate: the first active, eligible trigger in list order. A duplicate
    /// id after the first is ignored. Suppressions expire (`until` passed, `untilFalse` once the rule went inactive)
    /// and are dropped for rules that no longer exist.
    package static func step(_ triggers: [AwakeTrigger], facts: CriterionFacts, now: Double,
                             hysteresis: [StableID: TriggerHysteresis], suppressions: [StableID: TriggerSuppression],
                             paused: Bool, guardsHold: Bool) -> TriggerStepResult {
        guard now.isFinite else {
            return TriggerStepResult(hysteresis: hysteresis, suppressions: suppressions, top: nil, nextDeadline: nil)
        }
        var newHysteresis: [StableID: TriggerHysteresis] = [:]
        var newSuppressions: [StableID: TriggerSuppression] = [:]
        var top: TriggerTop?
        var next: Double?
        func later(_ t: Double) { if t > now { next = min(next ?? t, t) } }
        var seen = Set<StableID>()
        for (index, t) in triggers.enumerated() {
            guard seen.insert(t.id).inserted else { continue }
            let startDelay = Double(AwakeMath.clamp(t.startDelaySeconds, AwakeTrigger.delayRange))
            let endDelay = Double(AwakeMath.clamp(t.endDelaySeconds, AwakeTrigger.delayRange))
            var h = hysteresis[t.id] ?? TriggerHysteresis()
            if condition(t, facts: facts) {
                h.falseSince = nil
                let since = h.trueSince.flatMap { $0.isFinite ? min($0, now) : nil } ?? now
                h.trueSince = since
                if !h.active {
                    if now - since >= startDelay {
                        h.active = true
                        h.activeSince = min(now, since + startDelay)
                    } else {
                        later(since + startDelay)
                    }
                }
            } else {
                h.trueSince = nil
                let since = h.falseSince.flatMap { $0.isFinite ? min($0, now) : nil } ?? now
                h.falseSince = since
                if h.active {
                    if now - since >= endDelay {
                        h.active = false
                        h.activeSince = nil
                    } else {
                        later(since + endDelay)
                    }
                }
            }
            if !h.active { h.activeSince = nil }
            newHysteresis[t.id] = h

            var suppressed = false
            if var s = suppressions[t.id] {
                if let u = s.until, !(u.isFinite && u > now) { s.until = nil }
                if s.untilFalse && !h.active { s.untilFalse = false }
                if s.isActive(now: now) {
                    newSuppressions[t.id] = s
                    suppressed = true
                    if let u = s.until { later(u) }
                }
            }
            if top == nil, t.enabled, !paused, !guardsHold, !suppressed, h.active, !t.criteria.isEmpty {
                top = TriggerTop(id: t.id, index: index, options: t.options.sanitized().withoutNudge(),
                                 since: h.activeSince ?? now)
            }
        }
        return TriggerStepResult(hysteresis: newHysteresis, suppressions: newSuppressions, top: top, nextDeadline: next)
    }

    /// The user ended a trigger session: suppress per resumeAfterManualEndMinutes (nil = until the rule goes
    /// inactive and becomes true again).
    package static func manualEnd(_ t: AwakeTrigger, now: Double) -> TriggerSuppression {
        if let minutes = t.resumeAfterManualEndMinutes {
            let m = AwakeMath.clamp(minutes, AwakeTrigger.resumeRange)
            return TriggerSuppression(until: now + Double(m) * 60, untilFalse: false)
        }
        return TriggerSuppression(until: nil, untilFalse: true)
    }

    package static func requiredKinds(_ triggers: [AwakeTrigger]) -> Set<AwakeCriterionKind> {
        Set(triggers.filter(\.enabled).flatMap { $0.criteria.map(\.criterion.kind) })
    }

    /// Minutes of week (0..<10080) where some enabled schedule criterion flips.
    package static func scheduleBoundaries(_ triggers: [AwakeTrigger]) -> Set<Int> {
        var out = Set<Int>()
        for t in triggers where t.enabled {
            for e in t.criteria {
                guard case .schedule(let days, let start, let end) = e.criterion else { continue }
                let s = AwakeMath.clamp(start, 0...1_439), en = AwakeMath.clamp(end, 0...1_439)
                for d in 0..<7 where days.contains(day: d) {
                    out.insert((d * 1_440 + s) % 10_080)
                    let endDay = s < en ? d : (d + 1) % 7
                    out.insert((endDay * 1_440 + en) % 10_080)
                }
            }
        }
        return out
    }

    /// Sentence for list rows and the menu: "When Xcode is open and the power adapter is connected".
    package static func summary(_ t: AwakeTrigger) -> String { summary(t, text: .standard) }

    package static func summary(_ t: AwakeTrigger, text: AwakeTextContext) -> String {
        guard !t.criteria.isEmpty else { return L("No conditions") }
        let parts = t.criteria.map { phrase($0, text: text) }
        return L("When ") + parts.joined(separator: t.match == .all ? L(" and ") : L(" or "))
    }

    /// One condition as a clause ("Xcode is open", "the battery is below 50%").
    package static func phrase(_ entry: AwakeCriterionEntry, text: AwakeTextContext) -> String {
        let not = entry.negated
        func quoted(_ s: String, _ fallback: String) -> String { s.isEmpty ? fallback : "“" + s + "”" }
        switch entry.criterion {
        case .app(let bundleID, let name, let frontmost):
            let n = name.isEmpty ? bundleID : name
            if frontmost { return not ? L("\(n) is not in front") : L("\(n) is in front") }
            return not ? L("\(n) is not open") : L("\(n) is open")
        case .display(let match):
            switch match {
            case .anyExternal:
                return not ? L("no external display is connected") : L("an external display is connected")
            case .specific(_, let name):
                let n = quoted(name, L("a saved display"))
                return not ? L("\(n) is not connected") : L("\(n) is connected")
            case .mirroring:
                return not ? L("displays are not mirrored") : L("displays are mirrored")
            }
        case .power(let condition):
            switch condition {
            case .onAdapter:
                return not ? L("the power adapter is not connected") : L("the power adapter is connected")
            case .onBattery:
                return not ? L("your Mac is not on battery") : L("your Mac is on battery")
            case .charging:
                return not ? L("the battery is not charging") : L("the battery is charging")
            case .batteryAtLeast(let p):
                return not ? L("the battery is below \(p)%") : L("the battery is at least \(p)%")
            }
        case .schedule(let days, let start, let end):
            let s = AwakeMath.clamp(start, 0...1_439), e = AwakeMath.clamp(end, 0...1_439)
            let range = AwakeCountdown.clock(hour: s / 60, minute: s % 60, uses24Hour: text.uses24Hour) + "–"
                + AwakeCountdown.clock(hour: e / 60, minute: e % 60, uses24Hour: text.uses24Hour)
            let when = range + " " + daysText(days)
            return not ? L("it's outside \(when)") : L("it's \(when)")
        case .cpuAbove(let p):
            return not ? L("CPU use is \(p)% or less") : L("CPU use is above \(p)%")
        case .audio(let condition):
            switch condition {
            case .outputActive: return not ? L("no audio is playing") : L("audio is playing")
            case .microphoneActive:
                return not ? L("the microphone is not in use") : L("the microphone is in use")
            }
        case .idle(let m):
            let span = AwakeCountdown.unit(m, L("minute"), L("minutes"))
            return not ? L("you were active in the last \(span)") : L("you've been idle for \(span)")
        case .volumeMounted(_, let name):
            let n = quoted(name, L("a drive"))
            return not ? L("\(n) is not mounted") : L("\(n) is mounted")
        case .usbDevice(_, _, _, let name):
            let n = quoted(name, L("a USB device"))
            return not ? L("\(n) is not connected") : L("\(n) is connected")
        case .network(let condition):
            switch condition {
            case .subnet(let cidr): return not ? L("your Mac is not on \(cidr)") : L("your Mac is on \(cidr)")
            case .router(_, let label):
                let n = quoted(label, L("a saved network"))
                return not ? L("your Mac is not connected to \(n)") : L("your Mac is connected to \(n)")
            case .vpnConnected: return not ? L("no VPN is connected") : L("a VPN is connected")
            }
        case .networkActivity(let k):
            return not ? L("network traffic is below \(k) KB/s") : L("network traffic is at least \(k) KB/s")
        case .bluetooth(let match):
            switch match {
            case .audio(_, let name), .input(_, let name):
                let n = quoted(name, L("a Bluetooth device"))
                return not ? L("\(n) is not connected") : L("\(n) is connected")
            case .anyAudio:
                return not ? L("no Bluetooth audio is connected") : L("Bluetooth audio is connected")
            }
        }
    }

    /// "every day", "on weekdays", "on weekends", "on Mon, Wed, Fri".
    package static func daysText(_ days: WeekdaySet) -> String {
        if days == .everyDay { return L("every day") }
        if days == .weekdays { return L("on weekdays") }
        if days == .weekend { return L("on weekends") }
        let names = [L("Sun"), L("Mon"), L("Tue"), L("Wed"), L("Thu"), L("Fri"), L("Sat")]
        let picked = (0..<7).filter { days.contains(day: $0) }.map { names[$0] }
        return picked.isEmpty ? L("on no days") : L("on ") + picked.joined(separator: ", ")
    }
}

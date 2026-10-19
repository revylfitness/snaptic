import Foundation

// `snaptic awake …` (owner: G; PLAN 0.3 §2.10, §3.1, N12, R5-13). A closed grammar: no free-form string reaches an
// assertion or a log; numbers go through AwakeDurationGrammar's limits. Never traps (seeded fuzz).

extension AwakeActionID {
    /// Keep Awake on/off with the default preset (off = Turn Off).
    package static let toggle = AwakeActionID(rawValue: "awake.toggle")
    package static let keepDisplayOn = AwakeActionID(rawValue: "awake.keepDisplayOn")
    package static let preset1 = AwakeActionID(rawValue: "awake.preset1")
    package static let preset2 = AwakeActionID(rawValue: "awake.preset2")
    package static let preset3 = AwakeActionID(rawValue: "awake.preset3")
    package static let preset4 = AwakeActionID(rawValue: "awake.preset4")
    /// Shortcut title "Pause or Resume Rules"; the raw value is kept (M1 moves the 0.2 sleep-prevention hotkey here, R5-12).
    package static let pauseAutomatic = AwakeActionID(rawValue: "awake.pauseAutomatic")

    /// Every Awake hotkey action, in Settings order.
    package static let allAwake: [AwakeActionID] = [.toggle, .keepDisplayOn, .preset1, .preset2, .preset3, .preset4,
                                                    .pauseAutomatic]

    /// The preset hotkey for slot 1...4.
    package static func preset(_ slot: Int) -> AwakeActionID? {
        switch slot {
        case 1: return .preset1
        case 2: return .preset2
        case 3: return .preset3
        case 4: return .preset4
        default: return nil
        }
    }
}

package enum PresetSelector: Equatable, Sendable {
    /// 1-based.
    case index(Int)
    /// ≤ 64 scalars.
    case name(String)
}

package enum AwakeCommand: Equatable, Sendable {
    case status(json: Bool)
    /// nil = 1 h (C10).
    case start(AwakeDurationRequest?, displayMaySleep: Bool)
    /// --pid N (> 1), --max <duration> (≤ 24 h).
    case hold(pid: Int32?, maxSeconds: Int?)
    case preset(PresetSelector)
    case extend(seconds: Int)
    case stop
    /// ≤ 24 h, nil = 1 h.
    case pause(seconds: Int?)
}

package enum AwakeStatusSource: String, Sendable { case manual, automatic, holds }

package struct AwakeStatusFacts: Equatable, Sendable {
    package var active: Bool
    package var source: AwakeStatusSource?
    package var kind: AwakeHistoryKind?
    package var display: AwakeDisplayPolicy?
    package var endUnix: Double?
    package var remaining: Double?
    package var triggerNumber: Int?
    package var holdPIDs: [Int32]

    package init(active: Bool, source: AwakeStatusSource?, kind: AwakeHistoryKind?, display: AwakeDisplayPolicy?,
                 endUnix: Double?, remaining: Double?, triggerNumber: Int?, holdPIDs: [Int32]) {
        self.active = active
        self.source = source
        self.kind = kind
        self.display = display
        self.endUnix = endUnix
        self.remaining = remaining
        self.triggerNumber = triggerNumber
        self.holdPIDs = holdPIDs
    }

    /// The facts for a governing state (no names: rule numbers, kinds and pids only).
    package init(governing: AwakeGoverning, holds: [AwakeHold], now: ClockNow) {
        let pids = holds.map(\.binding.pid)
        switch governing {
        case .inactive:
            self.init(active: false, source: nil, kind: nil, display: nil, endUnix: nil, remaining: nil,
                      triggerNumber: nil, holdPIDs: pids)
        case .manual(let s):
            let r = AwakeClock.remaining(s, now: now)
            self.init(active: true, source: .manual, kind: s.kind.historyKind, display: s.options.display,
                      endUnix: AwakeClock.endWall(s, now: now), remaining: r.map { max(0, $0) }, triggerNumber: nil,
                      holdPIDs: pids)
        case .trigger(let top):
            self.init(active: true, source: .automatic, kind: .automatic, display: top.options.display, endUnix: nil,
                      remaining: nil, triggerNumber: top.index + 1, holdPIDs: pids)
        case .holds(let stack):
            let end = stack.map(\.deadline).filter(\.isFinite).max()
            let r = end.map { max(0, $0 - now.continuous) }
            self.init(active: true, source: .holds, kind: .process, display: .maySleep,
                      endUnix: r.map { now.wall + $0 }, remaining: r, triggerNumber: nil, holdPIDs: pids)
        }
    }
}

package enum AwakeCommandGrammar {
    /// Longest pid accepted (macOS pids are < 100 000).
    package static let maxPIDDigits = 7
    package static let maxPresetIndex = 99
    package static let maxPauseSeconds = 24 * 3_600

    /// verb is the word after "awake"; flags "--json", "--pid", "--max", "--display-may-sleep". nil = usage error
    /// (exit 2). `start indefinite` parses (SessionController refuses it, exit 4).
    package static func parse(verb: String, args: [String]) -> AwakeCommand? {
        guard args.count <= 16, args.allSatisfy({ $0.utf8.count <= 256 }) else { return nil }
        switch verb {
        case "status":
            if args.isEmpty { return .status(json: false) }
            return args == ["--json"] ? .status(json: true) : nil
        case "start":
            var words: [String] = []
            var maySleep = false
            for a in args {
                if a == "--display-may-sleep" {
                    guard !maySleep else { return nil }
                    maySleep = true
                } else if a.hasPrefix("-") {
                    return nil
                } else {
                    words.append(a)
                }
            }
            if words.isEmpty { return .start(nil, displayMaySleep: maySleep) }
            guard let request = AwakeDurationGrammar.parse(words) else { return nil }
            return .start(request, displayMaySleep: maySleep)
        case "hold":
            var pid: Int32?
            var cap: Int?
            var i = 0
            while i < args.count {
                let a = args[i]
                guard i + 1 < args.count else { return nil }
                let value = args[i + 1]
                switch a {
                case "--pid":
                    guard pid == nil, let p = parsePID(value) else { return nil }
                    pid = p
                case "--max":
                    guard cap == nil, let s = AwakeDurationGrammar.durationSeconds([value]),
                          s <= AwakeClock.holdMaxCapSeconds else { return nil }
                    cap = s
                default:
                    return nil
                }
                i += 2
            }
            return .hold(pid: pid, maxSeconds: cap)
        case "preset":
            guard !args.isEmpty, args.allSatisfy({ !$0.hasPrefix("-") }) else { return nil }
            let joined = args.joined(separator: " ")
            if joined.utf8.allSatisfy({ (0x30...0x39).contains($0) }) {
                guard joined.utf8.count <= 2, let n = Int(joined), (1...maxPresetIndex).contains(n) else { return nil }
                return .preset(.index(n))
            }
            guard joined.unicodeScalars.count <= AwakeCriterion.maxNameScalars else { return nil }
            let name = TextSanitizer.clean(joined, maxScalars: AwakeCriterion.maxNameScalars)
            guard !name.isEmpty, name == joined else { return nil }
            return .preset(.name(name))
        case "extend":
            guard !args.isEmpty, args.allSatisfy({ !$0.hasPrefix("-") }),
                  let s = AwakeDurationGrammar.durationSeconds(args) else { return nil }
            return .extend(seconds: s)
        case "stop":
            return args.isEmpty ? .stop : nil
        case "pause":
            if args.isEmpty { return .pause(seconds: nil) }
            guard args.allSatisfy({ !$0.hasPrefix("-") }), let s = AwakeDurationGrammar.durationSeconds(args),
                  s <= maxPauseSeconds else { return nil }
            return .pause(seconds: s)
        default:
            return nil
        }
    }

    /// A pid: ASCII digits only, ≤ 7 of them, > 1.
    private static func parsePID(_ s: String) -> Int32? {
        guard (1...maxPIDDigits).contains(s.utf8.count), s.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
              let n = Int(s), n > 1, n <= Int(Int32.max) else { return nil }
        return Int32(n)
    }

    /// `awake status` line: "inactive", or
    /// "active\t<manual|automatic|holds>\t<kind>\t<display policy>\t<ISO end or ->\t<remaining s or ->\t<hold count>".
    package static func statusLine(_ s: AwakeStatusFacts) -> String {
        guard s.active else { return "inactive" }
        var fields: [String] = ["active"]
        fields.append(s.source?.rawValue ?? "-")
        fields.append(s.kind?.rawValue ?? "-")
        fields.append(s.display?.rawValue ?? "-")
        fields.append(s.endUnix.flatMap(isoUTC) ?? "-")
        let remaining: Int? = s.remaining.flatMap(wholeSeconds)
        fields.append(remaining.map { String($0) } ?? "-")
        fields.append(String(s.holdPIDs.count))
        return fields.joined(separator: "\t")
    }

    /// One JSON object with a fixed key order; `holds` is the count and `pids` the numbers (never names).
    package static func statusJSON(_ s: AwakeStatusFacts) -> String {
        func str(_ v: String?) -> String { v.map { "\"" + $0 + "\"" } ?? "null" }
        func num(_ v: Int?) -> String { v.map { "\($0)" } ?? "null" }
        let pids = s.holdPIDs.map { "\($0)" }.joined(separator: ",")
        let shown = s.active
        var parts: [String] = []
        parts.append("\"active\":" + (shown ? "true" : "false"))
        parts.append("\"source\":" + str(shown ? s.source?.rawValue : nil))
        parts.append("\"kind\":" + str(shown ? s.kind?.rawValue : nil))
        parts.append("\"display\":" + str(shown ? s.display?.rawValue : nil))
        let end: String? = shown ? s.endUnix.flatMap(isoUTC) : nil
        parts.append("\"end\":" + str(end))
        let remaining: Int? = shown ? s.remaining.flatMap(wholeSeconds) : nil
        parts.append("\"remaining\":" + num(remaining))
        parts.append("\"rule\":" + num(shown ? s.triggerNumber : nil))
        parts.append("\"holds\":" + String(s.holdPIDs.count))
        parts.append("\"pids\":[" + pids + "]")
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// First reply line of a hold, with the actual cap ("at most 12 h", "at most 1 h 30 min").
    package static func holdReply(pid: Int32?, capSeconds: Int) -> String {
        let cap = capText(capSeconds)
        if let pid = pid { return L("Holding while process \(pid) runs (at most \(cap)).") }
        return L("Holding until this command ends (at most \(cap)). Press Control-C to stop.")
    }

    /// "12 h", "1 h 30 min", "45 min" (rounded up to the minute; at least 1 min).
    package static func capText(_ seconds: Int) -> String {
        let minutes = max(1, (AwakeMath.clamp(seconds, 0...AwakeClock.maxSessionSeconds) + 59) / 60)
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    private static func wholeSeconds(_ r: Double) -> Int? {
        guard r.isFinite else { return nil }
        return Int(min(max(0, r), 1e12).rounded(.up))
    }

    /// "2026-10-18T17:30:00Z" from explicit UTC civil components (N12): no formatter, no time zone database.
    package static func isoUTC(_ unix: Double) -> String? {
        guard unix.isFinite, unix >= 0, unix < 253_402_300_800 else { return nil }
        let secs = Int(unix.rounded(.down))
        let days = secs / 86_400, rem = secs % 86_400
        // Howard Hinnant's civil_from_days.
        let z = days + 719_468
        let era = z / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        func four(_ n: Int) -> String { String(repeating: "0", count: max(0, 4 - "\(n)".count)) + "\(n)" }
        let date = four(year) + "-" + two(month) + "-" + two(day)
        let time = two(rem / 3_600) + ":" + two(rem % 3_600 / 60) + ":" + two(rem % 60)
        return date + "T" + time + "Z"
    }
}

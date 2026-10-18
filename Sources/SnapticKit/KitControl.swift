import Foundation

/// How a CLI verb may act (PLAN §4.10).
package enum ControlPolicy: String, Codable, CaseIterable, Sendable { case read, low, trial, preConfirm }

/// One CLI request: a verb (one or more words) and its arguments.
package struct ControlRequest: Codable, Equatable, Sendable {
    package var verb: String
    package var arguments: [String]
    /// `--json`: the reply's output is JSON.
    package var json: Bool
    /// `--yes`, already filtered by the server: true only when the user also allowed
    /// "Let commands skip the confirmation panel". Trial handlers read this.
    package var skipConfirmation: Bool

    package init(verb: String, arguments: [String], json: Bool = false, skipConfirmation: Bool = false) {
        self.verb = verb
        self.arguments = arguments
        self.json = json
        self.skipConfirmation = skipConfirmation
    }

    private enum CodingKeys: String, CodingKey { case verb, arguments, json, skipConfirmation }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verb = try c.decode(String.self, forKey: .verb)
        arguments = c.lossy(.arguments, [])
        json = c.lossy(.json, false)
        skipConfirmation = c.lossy(.skipConfirmation, false)
    }
}

/// Also an Error, so request validation can return the reply to send as a failure.
package struct ControlResponse: Codable, Equatable, Sendable, Error {
    /// Process exit code for the CLI (`ControlExit`; the README lists them).
    package var exitCode: Int32
    package var output: String
    /// 0.3 §2.10: the server keeps the connection open after this reply (a connection hold). The client prints the
    /// output, keeps reading (ignoring ping lines) and exits with the final line's code, or 5 on EOF without one.
    package var holding: Bool

    package init(exitCode: Int32, output: String, holding: Bool = false) {
        self.exitCode = exitCode
        self.output = output
        self.holding = holding
    }
    package static func ok(_ output: String = "") -> ControlResponse { ControlResponse(exitCode: 0, output: output) }
    package static func failure(_ code: Int32, _ message: String) -> ControlResponse {
        ControlResponse(exitCode: code, output: message)
    }
    /// The first reply of a connection hold.
    package static func holding(_ output: String) -> ControlResponse {
        ControlResponse(exitCode: ControlExit.ok, output: output, holding: true)
    }

    private enum CodingKeys: String, CodingKey { case exitCode, output, holding }

    /// Hand-written so replies from a 0.2 server (no `holding` key) still decode.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exitCode = try c.decode(Int32.self, forKey: .exitCode)
        output = c.lossy(.output, "")
        holding = c.lossy(.holding, false)
    }

    /// `holding` is written only when true, so ordinary replies keep their 0.2 bytes.
    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(exitCode, forKey: .exitCode)
        try c.encode(output, forKey: .output)
        if holding { try c.encode(true, forKey: .holding) }
    }
}

/// CLI exit codes (PLAN §11: 0 / 2 / 3 / 4 / 5 / 6).
package enum ControlExit {
    package static let ok: Int32 = 0
    /// Bad command line or unknown verb.
    package static let usage: Int32 = 2
    /// The selector matched no display, action or item.
    package static let notFound: Int32 = 3
    /// Refused by policy: off-only, protected setting, not allowed from the CLI.
    package static let refused: Int32 = 4
    /// Snaptic isn't running, command-line control is off, or the feature is unavailable.
    package static let unavailable: Int32 = 5
    /// The confirmation was declined or timed out, or the request timed out.
    package static let cancelled: Int32 = 6

    package static func describe(_ code: Int32) -> String {
        switch code {
        case ok: return L("success")
        case usage: return L("usage error or unknown command")
        case notFound: return L("nothing matched")
        case refused: return L("refused")
        case unavailable: return L("unavailable")
        case cancelled: return L("cancelled or timed out")
        default: return L("error")
        }
    }
}

/// A verb whose command-line rules the host owns, whoever registers it (0.3 §2.10, §3.1): the registry applies these
/// instead of what a module passes, so a module can't make `awake stop` turn things on or let another verb hold.
package struct ControlVerbRule: Equatable, Sendable {
    package let verb: String
    package let policy: ControlPolicy
    package let offOnly: Bool
    /// May keep its connection open with a `holding` reply.
    package let holds: Bool
    /// Shares the `KitControl.sessionVerbsPerSecond` window (security L3).
    package let sessionLimited: Bool

    package init(_ verb: String, _ policy: ControlPolicy, offOnly: Bool = false, holds: Bool = false,
                 sessionLimited: Bool = false) {
        self.verb = verb
        self.policy = policy
        self.offOnly = offOnly
        self.holds = holds
        self.sessionLimited = sessionLimited
    }
}

/// The command-line protocol and its rules (PLAN §4.10(3), §11): one JSON line per
/// request and per reply, over a per-user Unix socket.
package enum KitControl {
    package static let protocolVersion = 1
    package static let maxMessageBytes = 64 * 1024
    package static let maxConcurrentConnections = 4
    package static let maxRequestsPerSecond = 20
    package static let readTimeoutSeconds: Double = 2
    /// The longest confirmation panel a user can set (Settings → Displays → Safety).
    package static var confirmSeconds: Double { Double(SafetyConfig.confirmSecondsRange.upperBound) }
    /// Applying, settling and the guard's stages around the panel.
    package static let applyMarginSeconds: Double = 30
    /// How long the client waits for a reply: the longest panel plus the margin, so a
    /// command that waits for "Keep this change?" is never cut off early (N7).
    package static var clientTimeoutSeconds: Double { confirmSeconds + applyMarginSeconds }
    /// `sun_path` holds 104 bytes including the terminating NUL.
    package static let maxSocketPathBytes = 103
    package static let maxArguments = 32
    package static let maxArgumentBytes = 1024
    package static let maxVerbWords = 4
    /// 0.3 §2.10: held connections (`awake hold`) have their own pool and never use the 4 request slots.
    package static let maxHeldConnections = 8
    /// Seconds between `{"ping":true}` lines on a held connection (a write failure ends the hold).
    package static let holdPingSeconds = 300
    /// A held connection only carries pings and one final line, so its send buffer is kept small: a client that
    /// stops reading can make Snaptic queue at most this much for it before the hold ends (security L5).
    package static let heldSendBufferBytes: Int32 = 1024

    /// 0.3 §3.1 (security L3): `awake start`, `hold`, `stop` and `extend` together, per second, on top of
    /// `maxRequestsPerSecond`.
    package static let sessionVerbsPerSecond = 1

    /// The §2.10 Awake verb table. `hold` is the only verb that may hold its connection; `stop` and `pause` only
    /// turn things off.
    package static let awakeVerbRules: [ControlVerbRule] = [
        ControlVerbRule("awake status", .read),
        ControlVerbRule("awake start", .low, sessionLimited: true),
        ControlVerbRule("awake hold", .low, holds: true, sessionLimited: true),
        ControlVerbRule("awake preset", .low, sessionLimited: true),
        ControlVerbRule("awake extend", .low, sessionLimited: true),
        ControlVerbRule("awake stop", .low, offOnly: true, sessionLimited: true),
        ControlVerbRule("awake pause", .low, offOnly: true),
    ]

    /// The host's rule for a verb, if it has one.
    package static func verbRule(_ verb: String) -> ControlVerbRule? {
        awakeVerbRules.first { $0.verb == verb }
    }

    /// The ping line servers write on held connections (with its newline).
    package static var pingLine: Data { Data(#"{"ping":true}"#.utf8) + [0x0A] }

    /// A ping line (without its newline): `{"ping":true}`, whitespace between tokens ignored. The client drops these.
    /// Compared as bytes: JSONSerialization would also read `1` as true.
    package static func isPing(_ line: Data) -> Bool {
        guard line.count <= 64 else { return false }
        let compact = line.filter { $0 != 0x20 && $0 != 0x09 && $0 != 0x0D && $0 != 0x0A }
        return compact.elementsEqual(#"{"ping":true}"#.utf8)
    }

    // MARK: Paths

    /// The socket lives in a 0700 directory under the account's Application Support.
    package static func socketDirectory(home: String) -> String {
        home + "/Library/Application Support/Snaptic/control"
    }

    package static func socketPath(home: String) -> String {
        socketDirectory(home: home) + "/snaptic.sock"
    }

    package static func isUsableSocketPath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.utf8.contains(0) && path.utf8.count <= maxSocketPathBytes
    }

    // MARK: Wire format

    package static func encode(_ request: ControlRequest) -> Data? { line(request) }
    package static func encode(_ response: ControlResponse) -> Data? { line(response) }

    private static func line<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(value), data.count < maxMessageBytes else { return nil }
        data.append(0x0A)
        return data
    }

    /// Decodes and validates one request line (without the newline). Failures come back
    /// as the response to send.
    package static func decodeRequest(_ data: Data) -> Result<ControlRequest, ControlResponse> {
        guard data.count <= maxMessageBytes else {
            return .failure(.failure(ControlExit.usage, L("Request too large.")))
        }
        guard let request = try? JSONDecoder().decode(ControlRequest.self, from: data) else {
            return .failure(.failure(ControlExit.usage, L("Malformed request.")))
        }
        let words = request.verb.split(separator: " ", omittingEmptySubsequences: false)
        guard !words.isEmpty, words.count <= maxVerbWords, words.allSatisfy({ isVerbWord(String($0)) }) else {
            return .failure(.failure(ControlExit.usage, L("Malformed command.")))
        }
        guard request.arguments.count <= maxArguments,
              request.arguments.allSatisfy({ $0.utf8.count <= maxArgumentBytes && !$0.utf8.contains(0) }) else {
            return .failure(.failure(ControlExit.usage, L("Too many or too long arguments.")))
        }
        return .success(request)
    }

    package static func decodeResponse(_ data: Data) -> ControlResponse? {
        guard data.count <= maxMessageBytes else { return nil }
        return try? JSONDecoder().decode(ControlResponse.self, from: data)
    }

    /// Lowercase letters, digits and dashes; 1–24 characters ("open-settings", "layout").
    package static func isVerbWord(_ word: String) -> Bool {
        let utf8 = word.utf8
        guard !utf8.isEmpty, utf8.count <= 24 else { return false }
        return utf8.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D }
    }

    // MARK: Client command line

    package struct ParsedCommand: Equatable, Sendable {
        /// Words and arguments as typed (the server matches verbs).
        package var words: [String]
        package var json: Bool
        package var yes: Bool
        package var help: Bool
    }

    /// `snaptic [--json] [--yes] [--help] [--] <verb words> [arguments]`. Only the client's
    /// own options before the verb are read here; everything from the verb on goes to the
    /// server as typed, so verb options such as `pip start --display 2` work. A `--`
    /// before the verb ends the client's options; one bare `--` after the verb (the old
    /// workaround) is dropped.
    package struct UsageError: Error, Equatable, Sendable {
        package let message: String
        package init(_ message: String) { self.message = message }
    }

    package static func parseCommandLine(_ arguments: [String]) -> Result<ParsedCommand, UsageError> {
        var command = ParsedCommand(words: [], json: false, yes: false, help: false)
        var index = 0
        options: while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json": command.json = true
            case "--yes", "-y": command.yes = true
            case "--help", "-h": command.help = true
            case "--":
                index += 1
                break options
            default:
                // Before the verb, only the client's options exist.
                if argument.hasPrefix("-") && argument.count > 1 {
                    return .failure(UsageError(L("Unknown option: ") + TextSanitizer.clean(argument, maxScalars: 40)
                                               + L(". Options for a command go after it.")))
                }
                break options
            }
            index += 1
        }
        var droppedSeparator = false
        for argument in arguments[index...] {
            if argument == "--" && !droppedSeparator && !command.words.isEmpty {
                droppedSeparator = true
                continue
            }
            command.words.append(argument)
        }
        if command.words.isEmpty { command.help = true }
        guard command.words.count <= maxArguments + maxVerbWords else { return .failure(UsageError(L("Too many arguments."))) }
        return .success(command)
    }

    /// One POSIX shell word in single quotes ("it's" → 'it'\''s'), for commands that
    /// Settings shows to copy (the `ln -s` line).
    package static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The command Settings offers to install `snaptic` as a symlink to our executable.
    package static func installCommand(executable: String) -> String {
        "sudo ln -sf " + shellQuoted(executable) + " /usr/local/bin/snaptic"
    }

    // MARK: Verb matching

    /// Longest registered verb that prefixes `words` ("layout apply Office" → verb
    /// "layout apply", arguments ["Office"]). Verb words compare case-insensitively.
    package static func match(_ words: [String], verbs: [String]) -> (verb: String, arguments: [String])? {
        var best: (verb: String, count: Int)?
        let lowered = words.map { $0.lowercased() }
        for verb in verbs {
            let parts = verb.split(separator: " ").map(String.init)
            guard !parts.isEmpty, parts.count <= lowered.count, Array(lowered.prefix(parts.count)) == parts else { continue }
            if best == nil || parts.count > best!.count { best = (verb, parts.count) }
        }
        guard let best else { return nil }
        return (best.verb, Array(words.dropFirst(best.count)))
    }

    /// 0.2 verbs that are gone, with the answer the CLI gets (R5-12): `ControlCommandRegistry.dispatch` answers them
    /// before lookup with exit 2 (usage), whatever modules run; help never lists them. Removed in 0.4.
    package static let retiredVerbs: [String: String] = [
        "prevent-sleep": "Moved to Awake: use “snaptic awake …”.",
    ]

    /// The retired verb `words` start with (verb words compare case-insensitively, like `match`), or nil.
    package static func retiredVerb(_ words: [String]) -> (verb: String, message: String)? {
        let lowered = words.map { $0.lowercased() }
        var best: (verb: String, count: Int)?
        for verb in retiredVerbs.keys {
            let parts = verb.split(separator: " ").map(String.init)
            guard !parts.isEmpty, parts.count <= lowered.count, Array(lowered.prefix(parts.count)) == parts else { continue }
            if best == nil || parts.count > best!.count { best = (verb, parts.count) }
        }
        guard let best, let message = retiredVerbs[best.verb] else { return nil }
        return (best.verb, L(message))
    }

    // MARK: Policy

    /// Verbs that change settings; their arguments are checked against the protected list.
    package static let settingVerbs: Set<String> = ["set", "toggle", "features", "feature", "enable", "disable", "module"]

    /// Never touchable from the CLI (PLAN §4.10(3); 0.3 §2.10 adds the Awake words; the 0.2 "sleepprevention" and
    /// "preventsleep" went with Displays' sleep prevention, R5-14).
    package static let protectedSettings: Set<String> = [
        "hooks", "customactions", "actions", "cli", "commandline", "disconnect", "autodisconnectbuiltin",
        "dimtoblack", "unlocks", "unlock", "allowwithoutasking", "allow", "trust",
        "awake", "nudge", "pointernudge", "drivealive", "activity", "guards", "batteryguard", "thermalguard",
    ]

    private static let onWords: Set<String> = ["on", "true", "yes", "enable", "enabled", "start"]

    /// An off-only verb may not be asked to turn anything on. Only the first argument is the
    /// on/off position (`smart-hidpi off 1`, `protect off`); later arguments are displays or
    /// names. Numbers never count: "1" is display number 1 (`toggle smart-hidpi 1`), and
    /// every off-only handler accepts only "off" or a selector there anyway (FIXES-R3 2).
    package static func requestsTurningOn(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        return onWords.contains(first.lowercased())
    }

    /// `--yes` skips the "Keep this change?" panel only when the user also allowed it and the
    /// verb is a trial verb (FIXES-R3 1). The server applies this before any handler runs.
    package static func skipsConfirmation(requested: Bool, allowed: Bool, policy: ControlPolicy) -> Bool {
        requested && allowed && policy == .trial
    }

    // MARK: JSON output

    /// With `--json`, every successful reply is JSON (FIXES-R3 10): a handler's own JSON object
    /// or array passes through; anything else becomes `{"ok":true}` or
    /// `{"ok":true,"output":"…"}`. Failures are left alone (the client formats those).
    /// `holding` is kept (0.3 §2.10).
    package static func jsonReply(_ response: ControlResponse) -> ControlResponse {
        guard response.exitCode == ControlExit.ok else { return response }
        let text = response.output
        if let first = text.unicodeScalars.first(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }),
           first == "{" || first == "[",
           let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
           object is [String: Any] || object is [Any] {
            return response
        }
        var object: [String: Any] = ["ok": true]
        if !text.isEmpty { object["output"] = text }
        var wrapped = response
        wrapped.output = jsonText(object) ?? #"{"ok":true}"#
        return wrapped
    }

    /// The client's error object: `{"error":"…","exitCode":N}`.
    package static func errorJSON(_ code: Int32, _ message: String) -> String {
        jsonText(["exitCode": Int(code), "error": message]) ?? #"{"exitCode":\#(code)}"#
    }

    /// Whether the raw client arguments ask for `--json` before the verb (so the client's own
    /// errors, even a usage error, come out as JSON).
    package static func wantsJSON(_ arguments: [String]) -> Bool {
        for argument in arguments {
            if argument == "--json" { return true }
            if argument == "--" || !argument.hasPrefix("-") || argument.count == 1 { return false }
        }
        return false
    }

    /// Sorted-key JSON text for an object or array.
    package static func jsonText(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// "xdr", "night-shift", "NightShift" → the feature; case, dashes and underscores ignored.
    package static func feature(named text: String) -> DisplayFeature? {
        func normalize(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        }
        let wanted = normalize(text)
        guard !wanted.isEmpty, wanted.utf8.count <= 64 else { return nil }
        return DisplayFeature.allCases.first { normalize($0.rawValue) == wanted }
    }

    /// The protected setting a request would touch, if any. A module id after `module` names the module, not a
    /// setting: `module disable awake` stays reachable (the verb is off-only and its help lists Awake, 0.3 §2.10),
    /// while `set awake …` and `toggle awake …` are refused.
    package static func protectedSetting(verb: String, arguments: [String]) -> String? {
        let words = verb.split(separator: " ").map { $0.lowercased() } + arguments.map { $0.lowercased() }
        guard let first = words.first, settingVerbs.contains(first) else { return nil }
        let normalized = words.dropFirst().map { $0.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") }
        let moduleNames = first == "module" ? Set(ModuleID.allCases.map { $0.rawValue.lowercased() }) : []
        return normalized.first { protectedSettings.contains($0) && !moduleNames.contains($0) }
    }
}

/// Which display a command targets (PLAN §11): name prefix, key, id, main, mouse, focus, all.
package enum ControlSelector: Equatable, Sendable {
    case main, mouse, focus, all
    case key(DisplayKey)
    case id(UInt32)
    /// Case-insensitive prefix of the display's name.
    case name(String)

    package static func parse(_ text: String) -> ControlSelector? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.utf8.count <= 128 else { return nil }
        switch t.lowercased() {
        case "main": return .main
        case "mouse", "pointer": return .mouse
        case "focus", "focused": return .focus
        case "all": return .all
        default: break
        }
        if t.lowercased().hasPrefix("id:"), let n = UInt32(t.dropFirst(3)) { return .id(n) }
        if let key = DisplayKey(rawValue: t.lowercased()), t.utf8.count == 32 { return .key(key) }
        return .name(TextSanitizer.clean(t, maxScalars: 64))
    }

    /// Name-prefix match for `.name`; other cases are resolved by the caller.
    package func matchesName(_ name: String) -> Bool {
        guard case .name(let prefix) = self else { return false }
        return name.lowercased().hasPrefix(prefix.lowercased())
    }
}

/// A value from the command line: absolute ("50"), relative ("+10", "-5"), either as a
/// percentage of the control's range ("50%", "+10%").
package struct ControlValue: Equatable, Sendable {
    package var amount: Double
    package var relative: Bool
    package var percent: Bool

    package init(amount: Double, relative: Bool, percent: Bool) {
        self.amount = amount
        self.relative = relative
        self.percent = percent
    }

    package static func parse(_ text: String) -> ControlValue? {
        var t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.utf8.count <= 16 else { return nil }
        var percent = false
        if t.hasSuffix("%") { percent = true; t.removeLast() }
        let relative = t.hasPrefix("+") || t.hasPrefix("-")
        guard let amount = Double(t), amount.isFinite else { return nil }
        return ControlValue(amount: amount, relative: relative, percent: percent)
    }

    /// Applies to `current` within `range`; percentages are of the range's width.
    package func apply(to current: Double, in range: ClosedRange<Double>) -> Double {
        let width = range.upperBound - range.lowerBound
        let delta = percent ? amount / 100 * width : amount
        let target = relative ? current + delta : (percent ? range.lowerBound + delta : amount)
        return min(range.upperBound, max(range.lowerBound, target))
    }
}

/// At most `limit` events in any `window`-second span (the server's 20 requests/s).
package struct ControlRateWindow: Sendable {
    package let limit: Int
    package let window: Double
    private var stamps: [Double] = []

    package init(limit: Int, window: Double) {
        self.limit = max(1, limit)
        self.window = window
    }

    /// Records the event and returns true when it's within the limit.
    package mutating func allow(now: Double) -> Bool {
        stamps.removeAll { now - $0 >= window || $0 > now }
        guard stamps.count < limit else { return false }
        stamps.append(now)
        return true
    }
}

/// Splits a byte stream into newline-terminated lines (the CLI client's reader, 0.3 §2.10). Bytes after a newline are
/// kept for the next line, never dropped; a line longer than `maxLineBytes` sets `overflowed` and drops what was pending.
package struct ControlLineReader: Sendable {
    package let maxLineBytes: Int
    private var pending: [UInt8] = []
    package private(set) var overflowed = false

    package init(maxLineBytes: Int = KitControl.maxMessageBytes) {
        self.maxLineBytes = max(1, maxLineBytes)
    }

    /// Appends `bytes` and returns the lines they completed, in order, without their newlines.
    package mutating func append<S: Sequence>(_ bytes: S) -> [Data] where S.Element == UInt8 {
        var lines: [Data] = []
        for byte in bytes {
            if byte == 0x0A {
                if !overflowed { lines.append(Data(pending)) }
                pending.removeAll(keepingCapacity: true)
                overflowed = false
            } else if !overflowed {
                pending.append(byte)
                if pending.count > maxLineBytes {
                    overflowed = true
                    pending.removeAll()
                }
            }
        }
        return lines
    }

    /// Bytes after the last newline (a final line without one), or nil when there are none.
    package var remainder: Data? { pending.isEmpty || overflowed ? nil : Data(pending) }

    /// Whether a partial line is waiting.
    package var hasPartialLine: Bool { !pending.isEmpty || overflowed }
}

/// The control server's two connection pools (0.3 §2.10 "Slots"): 4 request slots and 8 held slots. A `holding` reply
/// moves a connection from the request pool to the held pool exactly once; its finish then frees the held slot only.
package struct ControlSlotPool: Equatable, Sendable {
    package private(set) var active = 0
    package private(set) var held = 0
    package let maxActive: Int
    package let maxHeld: Int

    package init(maxActive: Int = KitControl.maxConcurrentConnections, maxHeld: Int = KitControl.maxHeldConnections) {
        self.maxActive = max(1, maxActive)
        self.maxHeld = max(0, maxHeld)
    }

    /// Takes a request slot for a new connection; false when all are busy.
    package mutating func admit() -> Bool {
        guard active < maxActive else { return false }
        active += 1
        return true
    }

    /// Moves one connection from the request pool to the held pool; false (nothing changes) when the held pool is
    /// full, and the caller then refuses the hold and releases the request slot as usual.
    package mutating func promote() -> Bool {
        guard held < maxHeld, active > 0 else { return false }
        active -= 1
        held += 1
        return true
    }

    /// Frees the slot of a finished connection: the held one if it was promoted, else its request slot.
    package mutating func release(wasHeld: Bool) {
        if wasHeld {
            held = max(0, held - 1)
        } else {
            active = max(0, active - 1)
        }
    }
}

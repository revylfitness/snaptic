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
    package init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
    package static func ok(_ output: String = "") -> ControlResponse { ControlResponse(exitCode: 0, output: output) }
    package static func failure(_ code: Int32, _ message: String) -> ControlResponse {
        ControlResponse(exitCode: code, output: message)
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

/// The command-line protocol and its rules (PLAN §4.10(3), §11): one JSON line per
/// request and per reply, over a per-user Unix socket.
package enum KitControl {
    package static let protocolVersion = 1
    package static let maxMessageBytes = 64 * 1024
    package static let maxConcurrentConnections = 4
    package static let maxRequestsPerSecond = 20
    package static let readTimeoutSeconds: Double = 2
    /// The confirmation panel's own timeout; the client waits that long plus 15 s.
    package static let confirmSeconds: Double = 15
    package static var clientTimeoutSeconds: Double { confirmSeconds + 15 }
    /// `sun_path` holds 104 bytes including the terminating NUL.
    package static let maxSocketPathBytes = 103
    package static let maxArguments = 32
    package static let maxArgumentBytes = 1024
    package static let maxVerbWords = 4

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

    /// `snaptic [--json] [--yes] <verb words> [arguments]`. `--` ends option parsing.
    package struct UsageError: Error, Equatable, Sendable {
        package let message: String
        package init(_ message: String) { self.message = message }
    }

    package static func parseCommandLine(_ arguments: [String]) -> Result<ParsedCommand, UsageError> {
        var command = ParsedCommand(words: [], json: false, yes: false, help: false)
        var optionsDone = false
        for argument in arguments {
            if !optionsDone {
                switch argument {
                case "--json": command.json = true; continue
                case "--yes", "-y": command.yes = true; continue
                case "--help", "-h": command.help = true; continue
                case "--": optionsDone = true; continue
                default:
                    // "-10" is a value; only "--something" is an (unknown) option.
                    if argument.hasPrefix("--") {
                        return .failure(UsageError(L("Unknown option: ") + TextSanitizer.clean(argument, maxScalars: 40)))
                    }
                }
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

    // MARK: Policy

    /// Verbs that change settings; their arguments are checked against the protected list.
    package static let settingVerbs: Set<String> = ["set", "toggle", "features", "feature", "enable", "disable", "module"]

    /// Never touchable from the CLI (PLAN §4.10(3)).
    package static let protectedSettings: Set<String> = [
        "hooks", "customactions", "actions", "cli", "commandline", "disconnect", "autodisconnectbuiltin",
        "dimtoblack", "unlocks", "unlock", "allowwithoutasking", "allow", "trust",
        "sleepprevention", "preventsleep",
    ]

    private static let onWords: Set<String> = ["on", "true", "yes", "1", "enable", "enabled", "start"]

    /// An off-only verb may not be asked to turn anything on.
    package static func requestsTurningOn(_ arguments: [String]) -> Bool {
        arguments.contains { onWords.contains($0.lowercased()) }
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

    /// The protected setting a request would touch, if any.
    package static func protectedSetting(verb: String, arguments: [String]) -> String? {
        let words = verb.split(separator: " ").map { $0.lowercased() } + arguments.map { $0.lowercased() }
        guard let first = words.first, settingVerbs.contains(first) else { return nil }
        let normalized = words.dropFirst().map { $0.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") }
        return normalized.first { protectedSettings.contains($0) }
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

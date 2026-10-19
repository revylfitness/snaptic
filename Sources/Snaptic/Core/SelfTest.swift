import Darwin
import Foundation
import SnapticKit
import SnapticShims

/// The helper fd-inheritance self-test (PLAN §14.1, R5.5, R4C §4.3). Built in every
/// configuration and kept out of help texts; it grants nothing.
///
/// `--selftest-helpers <token-file>`: runs only when the environment variable
/// SNAPTIC_SELFTEST_TOKEN equals the contents of `<token-file>` (written by the CI step).
/// Spawns two `--selftest-child` helpers through HelperSpawner, prints
/// `child <pid> <startTime>` for each, then SIGKILLs itself. The CI script asserts that
/// both children exit within 3 s (they see EOF on stdin only if no pipe end leaked).
///
/// `--selftest-child`: a helper that goes through HelperPrologue (signal resets, fd
/// closing, parent identity check) and exits when its stdin reaches EOF.
///
/// `--selftest-controls <token-file>` (0.3 §4.8, token-gated): walks a Switcher `Config` with every optional set and
/// one shortcut, in process, and exits 1 unless every key has a control (a legacy path, a Switcher table key or an
/// internal key) and every legacy path still exists or was removed, and that the Displays menu contributors'
/// `menuItemIDs` cover every frozen 0.2 menu id (R5-13). Then (0.3 §2.10, §3.1) it sends every documented
/// `snaptic awake …` command line, both `awake hold` forms included, through the client's parsing and the real
/// `ControlCommandRegistry.dispatch` to probe handlers that parse with `AwakeCommandGrammar`, and checks the exit
/// codes, `holding`, which handler got the connection's hold, the host's verb rules, the shared 1/s window and help.
///
/// `--selftest-control-server <token-file>` (0.3 R5-5, token-gated): no modules, only a `ControlServer` with a test
/// registry on SNAPTIC_SELFTEST_SOCKET (under the token file's directory). Before it says `listening` it checks both
/// `awake hold` forms over its own socket (the connection form holds until the client closes; `--pid` replies and
/// closes); then it prints `held=<n> active=<n>` on every pool change and `closed <reason>` per `selftest hold`;
/// exits on SIGTERM or after 120 s. Driven by scripts/selftest-control-server.sh.
enum SelfTest {
    static let tokenVariable = "SNAPTIC_SELFTEST_TOKEN"
    /// The CLI client's token-mode override (R5-5): the token file to compare with, and the socket to use.
    static let tokenFileVariable = "SNAPTIC_SELFTEST_TOKEN_FILE"
    static let socketVariable = "SNAPTIC_SELFTEST_SOCKET"

    static func run(_ arguments: [String]) -> Never {
        switch arguments.dropFirst().first {
        case "--selftest-child": runChild(arguments)
        case "--selftest-helpers": runParent(arguments)
        case "--selftest-controls": runControls(arguments)
        case "--selftest-control-server": runControlServer(arguments)
        case "--selftest-launch": runLaunch(arguments)
        default: exit(KitArgs.exitUsage)
        }
    }

    // MARK: --selftest-launch

    /// 0.3.1 E3 (HW-37 in CI): `--selftest-launch <token-file>` starts the ad-hoc app far enough to build ModuleHost
    /// and the updater gate (Sparkle absent), then exits. Step 0 stub: the token gate only; T-update builds the rest.
    private static func runLaunch(_ arguments: [String]) -> Never {
        guard arguments.count == 3, tokenMatches(file: arguments[2]) else { exit(KitArgs.exitUsage) }
        say("selftest-launch: not built yet\n")
        exit(0)
    }

    // MARK: --selftest-controls

    /// The Switcher's control tables (settings page, sheets and its menu section).
    private static func isSwitcherSurface(_ surface: String) -> Bool {
        surface == "switcher" || surface.hasPrefix("switcher.") || surface == "menu.switcher"
    }

    private static func runControls(_ arguments: [String]) -> Never {
        guard arguments.count == 3, tokenMatches(file: arguments[2]) else { exit(KitArgs.exitUsage) }
        var config = Config()
        // Every optional set, one element in every list (R5-13), so each key path shows up.
        config.shortcuts = [Shortcut()]
        config.gatherShortcut = HotkeyCombo(keyCode: 5, carbonModifiers: 0x0800)
        config.excludedBundleIDs = ["com.example.excluded"]
        config.passthroughBundleIDs = ["com.example.passthrough"]
        config.privateBundleIDs = ["com.example.private"]
        let walked = KitKeyPaths.paths(config)
        let tables = ControlRegistry.tables.filter { isSwitcherSurface($0.surface) }
        let declared = Set(tables.flatMap { $0.controls.flatMap(\.keys) })
        let problems = KitKeyPaths.coverageProblems(walked: walked, legacy: ControlLegacy.switcherKeyPaths,
                                                    declared: declared, internalKeys: ControlLegacy.internalKeys,
                                                    removed: Set(ControlRemovals.removed.keys))
        say("selftest-controls: \(walked.count) paths, \(KitKeyPaths.leaves(walked).count) keys, "
            + "\(tables.count) Switcher tables\n")
        for problem in problems { say("selftest: controls: " + problem + "\n") }
        // R5-13: the Displays menu contributors' static ids cover every frozen 0.2 menu id (review5 code N1).
        let (menu, contributors) = MainActor.assumeIsolated {
            (DisplaysModule.menuCoverageProblems(), DisplaysModule.menuContributorTypes.count)
        }
        say("selftest-controls: \(contributors) Displays menu contributors\n")
        for problem in menu { say("selftest: menu items: " + problem + "\n") }
        let awake = runAwakeVerbCheck()
        say("selftest-controls: \(KitControl.awakeVerbRules.count) Awake verbs, \(awakeCases.count) command lines, "
            + "\(KitControl.retiredVerbs.count) retired verbs\n")
        for problem in awake { say("selftest: awake verbs: " + problem + "\n") }
        exit(problems.isEmpty && menu.isEmpty && awake.isEmpty ? 0 : 1)
    }

    // MARK: Awake verbs (0.3 §2.10, §3.1)

    /// How long the in-process Awake checks may take.
    static let awakeCheckSeconds: Double = 5

    /// A command line (the words after `snaptic`) and what dispatch must make of it.
    private struct AwakeCase {
        let words: [String]
        let exit: Int32
        let holding: Bool
        /// Reaches the probe handler (false: refused by the registry first).
        let handled: Bool

        init(_ words: [String], exit: Int32 = ControlExit.ok, holding: Bool = false, handled: Bool = true) {
            self.words = words
            self.exit = exit
            self.holding = holding
            self.handled = handled
        }
    }

    /// Every documented form (§2.10 table, README usage), plus the refusals the registry owns.
    private static var awakeCases: [AwakeCase] {
        let me = String(getpid())
        return [
            AwakeCase(["awake", "status"]),
            AwakeCase(["awake", "status", "--json"]),
            AwakeCase(["--json", "awake", "status"]),
            AwakeCase(["awake", "start"]),
            AwakeCase(["awake", "start", "2h"]),
            AwakeCase(["awake", "start", "1h", "30m", "--display-may-sleep"]),
            AwakeCase(["awake", "start", "until", "5:30", "pm"]),
            AwakeCase(["awake", "start", "idle"]),
            AwakeCase(["awake", "start", "soon"], exit: ControlExit.usage),
            // `awake hold`, both forms: the connection form holds, `--pid` answers and closes.
            AwakeCase(["awake", "hold"], holding: true),
            AwakeCase(["awake", "hold", "--max", "2h"], holding: true),
            AwakeCase(["AWAKE", "Hold"], holding: true),
            AwakeCase(["awake", "hold", "--pid", me]),
            AwakeCase(["awake", "hold", "--pid", me, "--max", "30m"]),
            AwakeCase(["awake", "hold", "--pid"], exit: ControlExit.usage),
            AwakeCase(["awake", "hold", "--max", "25h"], exit: ControlExit.usage),
            AwakeCase(["awake", "preset", "1"]),
            AwakeCase(["awake", "preset", "Focus", "Time"]),
            AwakeCase(["awake", "extend", "15m"]),
            AwakeCase(["awake", "stop"]),
            AwakeCase(["awake", "stop", "on"], exit: ControlExit.refused, handled: false),
            AwakeCase(["awake", "pause"]),
            AwakeCase(["awake", "pause", "2h"]),
            AwakeCase(["awake", "pause", "on"], exit: ControlExit.refused, handled: false),
        ]
    }

    /// Runs the Awake verb checks on main, bounded by `awakeCheckSeconds`. Returns the problems.
    private static func runAwakeVerbCheck() -> [String] {
        MainActor.assumeIsolated {
            let run = AwakeCheckRun()
            Task { @MainActor in
                run.problems = await awakeVerbProblems()
                run.done = true
            }
            let deadline = Date().addingTimeInterval(awakeCheckSeconds)
            while !run.done && Date() < deadline {
                _ = CFRunLoopRunInMode(.defaultMode, 0.02, false)
            }
            return run.done ? run.problems : ["timed out after \(Int(awakeCheckSeconds)) s"]
        }
    }

    @MainActor private static func awakeVerbProblems() async -> [String] {
        let lifetime = Lifetime()
        defer { lifetime.end() }
        let registry = ControlCommandRegistry()
        let log = AwakeProbeLog()
        let clock = AwakeCheckClock()
        registry.now = { clock.seconds }
        registerAwakeProbes(registry, lifetime: lifetime, log: log)
        var problems: [String] = []
        for rule in KitControl.awakeVerbRules {
            guard let entry = registry.entry(rule.verb) else {
                problems.append(rule.verb + " isn't registered")
                continue
            }
            if entry.policy != rule.policy || entry.offOnly != rule.offOnly || entry.holds != rule.holds {
                problems.append(rule.verb + ": the host's rules weren't applied")
            }
        }
        let peer = ControlPeer(pid: getpid(), uid: getuid(), startTime: SNProcess.startTime(for: getpid()))
        for item in awakeCases {
            clock.seconds += 2
            let line = item.words.joined(separator: " ")
            let before = log.calls.count
            let response = await dispatch(item.words, registry: registry, peer: peer)
            if response.exitCode != item.exit {
                problems.append("\(line): exit \(response.exitCode), expected \(item.exit) (\(response.output))")
            }
            if response.holding != item.holding { problems.append("\(line): holding is \(response.holding)") }
            let handled = log.calls.count > before
            if handled != item.handled { problems.append("\(line): " + (handled ? "reached" : "didn't reach") + " the handler") }
            if handled, let call = log.calls.last, call.hadHold != (KitControl.verbRule(call.verb)?.holds == true) {
                problems.append("\(line): the handler " + (call.hadHold ? "got" : "didn't get") + " the connection's hold")
            }
        }
        // The shared 1/s window: a second session verb within the second is refused before its handler; `status`
        // isn't limited; a second later the next one runs.
        clock.seconds += 2
        _ = await dispatch(["awake", "start", "2h"], registry: registry, peer: peer)
        let calls = log.calls.count
        let quick = await dispatch(["awake", "hold", "--pid", String(getpid())], registry: registry, peer: peer)
        if quick.exitCode != ControlExit.unavailable || log.calls.count != calls {
            problems.append("a second session verb within 1 s wasn't refused (exit \(quick.exitCode))")
        }
        if await dispatch(["awake", "status"], registry: registry, peer: peer).exitCode != ControlExit.ok {
            problems.append("awake status was rate-limited")
        }
        clock.seconds += 1.01
        if await dispatch(["awake", "extend", "15m"], registry: registry, peer: peer).exitCode != ControlExit.ok {
            problems.append("a session verb a second later was refused")
        }
        let help = await dispatch(["help", "awake"], registry: registry, peer: peer)
        for rule in KitControl.awakeVerbRules where !help.output.contains(rule.verb) {
            problems.append("help doesn't list " + rule.verb)
        }
        // Security S-4: the Awake requests above were only counted; no exported `.control` line names one.
        let timeline = EventLog.shared.recent(500).filter { $0.category == .control && $0.message.hasPrefix("CLI awake") }
        if let first = timeline.first { problems.append("\(timeline.count) Awake request(s) logged with a time: " + first.message) }
        for key in ["cli.awake.hold.holding", "cli.awake.stop.refused.offonly", "cli.awake.hold.refused.rate"]
        where (EventLog.shared.awakeCounts[key] ?? 0) == 0 {
            problems.append(key + " wasn't counted")
        }
        problems += await retiredVerbProblems(registry, peer: peer, lifetime: lifetime)
        return problems
    }

    /// R5-12: every retired 0.2 verb answers exit 2 with its pointer before lookup (even when something registered
    /// it, which reaches no handler), in any case, with or without arguments, and `help` never lists it.
    @MainActor private static func retiredVerbProblems(_ registry: ControlCommandRegistry, peer: ControlPeer,
                                                       lifetime: Lifetime) async -> [String] {
        var problems: [String] = []
        let log = AwakeProbeLog()
        for verb in KitControl.retiredVerbs.keys.sorted() {
            registry.register(verb, policy: .read, offOnly: false, cliAllowed: true, holds: false,
                              summary: "Self-test retired " + verb, lifetime: lifetime) { _, _ in
                log.calls.append((verb, false))
                return .ok("reached")
            }
            let message = KitControl.retiredVerbs[verb] ?? ""
            for words in [[verb], [verb, "off"], [verb.uppercased(), "on"], ["--json", verb, "off"]] {
                let line = words.joined(separator: " ")
                let response = await dispatch(words, registry: registry, peer: peer)
                if response.exitCode != ControlExit.usage {
                    problems.append("\(line): exit \(response.exitCode), expected \(ControlExit.usage)")
                }
                if response.output != L(message) { problems.append("\(line): answered “\(response.output)”") }
            }
            let help = await dispatch(["help"], registry: registry, peer: peer)
            if help.exitCode != ControlExit.ok || help.output.contains(verb) { problems.append("help lists " + verb) }
        }
        if !log.calls.isEmpty { problems.append("a retired verb reached a handler \(log.calls.count) time(s)") }
        return problems
    }

    /// One command line as the CLI client sends it (its own options before the verb, the rest as typed).
    @MainActor private static func dispatch(_ words: [String], registry: ControlCommandRegistry,
                                            peer: ControlPeer) async -> ControlResponse {
        guard case .success(let command) = KitControl.parseCommandLine(words) else {
            return .failure(ControlExit.usage, "the client refused it")
        }
        let all = command.help ? ["help"] + command.words : command.words
        guard let first = all.first else { return .failure(ControlExit.usage, "no verb") }
        let request = ControlRequest(verb: first.lowercased(), arguments: Array(all.dropFirst()), json: command.json,
                                     skipConfirmation: command.yes)
        return await registry.dispatch(request, peer: peer, hold: ControlHold(), skipConfirmationAllowed: false)
    }

    /// Registers every `KitControl.awakeVerbRules` verb with a probe standing in for Awake's handler: it parses with
    /// `AwakeCommandGrammar` (usage error otherwise), answers `holding` for the connection form of `awake hold` and
    /// an ordinary reply for `--pid` (a live process only). Registered with the opposite flags on purpose: the
    /// registry must apply the host's rules.
    @MainActor private static func registerAwakeProbes(_ registry: ControlCommandRegistry, lifetime: Lifetime,
                                                       log: AwakeProbeLog) {
        for rule in KitControl.awakeVerbRules {
            let word = String(rule.verb.split(separator: " ").last ?? "")
            registry.register(rule.verb, policy: .trial, offOnly: !rule.offOnly, cliAllowed: true, holds: !rule.holds,
                              summary: "Self-test " + rule.verb, lifetime: lifetime) { request, context in
                log.calls.append((rule.verb, context.hold != nil))
                guard let command = AwakeCommandGrammar.parse(verb: word, args: request.arguments) else {
                    return .failure(ControlExit.usage, "usage")
                }
                guard case .hold(let pid, let cap) = command else { return .ok(word) }
                guard let hold = context.hold else { return .failure(ControlExit.usage, "no hold") }
                let capSeconds = cap ?? AwakeClock.holdDefaultCapSeconds
                if let pid {
                    guard pid > 1, SNProcess.startTime(for: pid) != 0 else {
                        return .failure(ControlExit.refused, L("Snaptic couldn’t identify the caller."))
                    }
                    return .ok(AwakeCommandGrammar.holdReply(pid: pid, capSeconds: capSeconds))
                }
                // Strong on purpose, as in `selftest hold`: the hold drops its handlers once they ran.
                hold.onClose { log.closes.append(hold.closeReason?.rawValue ?? "eof") }
                return .holding(AwakeCommandGrammar.holdReply(pid: nil, capSeconds: capSeconds))
            }
        }
    }

    // MARK: --selftest-control-server

    /// How long the server lives without a SIGTERM.
    static let controlServerSeconds: Double = 120
    /// A watched pid's exit finishes its hold this much later, so a client's own EOF (kill -9 closes the socket at
    /// the same moment) is reported as `eof`, and only a hold whose fd outlived the process says `pid`.
    static let pidGraceSeconds: Double = 0.2
    /// The final line `selftest hold`'s handler writes when the server stops on SIGUSR1.
    static let stopFinalLine = "Hold ended by its handler."

    private static func runControlServer(_ arguments: [String]) -> Never {
        guard arguments.count == 3, tokenMatches(file: arguments[2]) else { exit(KitArgs.exitUsage) }
        guard let socket = ProcessInfo.processInfo.environment[socketVariable],
              isUnder(directoryOf: arguments[2], socket) else {
            say("selftest: \(socketVariable) must name a socket in the token file's directory\n")
            exit(KitArgs.exitUsage)
        }
        MainActor.assumeIsolated {
            let lifetime = Lifetime()
            let registry = ControlCommandRegistry()
            let watches = HoldWatches()
            registerTestVerbs(registry, watches: watches, lifetime: lifetime)
            // The Awake probes, with a clock that steps 2 s per request: the script never sends Awake verbs, and the
            // hold check below sends two holds in a row.
            let log = AwakeProbeLog()
            let clock = AwakeCheckClock()
            registry.now = {
                clock.seconds += 2
                return clock.seconds
            }
            registerAwakeProbes(registry, lifetime: lifetime, log: log)
            let server = ControlServer(registry: registry)
            server.holdPingInterval = 1
            // Quiet until the hold check is done, so the script's counts see only its own connections.
            let gate = PoolGate()
            server.onPoolChange = { held, active in
                if gate.record(held: held, active: active) { say("held=\(held) active=\(active)\n") }
            }
            server.start(socketPath: socket)
            guard case .listening = server.status else {
                say("selftest: control server didn't start: \(server.status)\n")
                exit(1)
            }
            let problems = awakeHoldCheck(socket: socket, log: log, gate: gate)
            for problem in problems { say("selftest: awake hold: " + problem + "\n") }
            guard problems.isEmpty else {
                server.stop()
                exit(1)
            }
            gate.open()
            say("awake hold: both forms ok\n")
            say("listening\n")
            signal(SIGTERM, SIG_IGN)
            let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            term.setEventHandler {
                MainActor.assumeIsolated {
                    server.stop()
                    exit(0)
                }
            }
            term.resume()
            // SIGUSR1: the server stops but the process stays (command-line control turned off, R5-14a). Like Awake,
            // the first open hold's handler writes its own final line a turn later; the others get the server's
            // after the grace. Either way the client exits 0 with a final line, never on a bare EOF.
            signal(SIGUSR1, SIG_IGN)
            let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            usr1.setEventHandler {
                MainActor.assumeIsolated {
                    say("stopping\n")
                    server.stop()
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { watches.finishFirstOpen(.ok(stopFinalLine)) }
                    }
                }
            }
            usr1.resume()
            DispatchQueue.main.asyncAfter(deadline: .now() + controlServerSeconds) {
                MainActor.assumeIsolated {
                    say("selftest: control server timed out after \(Int(controlServerSeconds)) s\n")
                    server.stop()
                    exit(0)
                }
            }
            withExtendedLifetime((lifetime, registry, watches, server, term, usr1)) {
                CFRunLoopRun()
            }
        }
        exit(0)
    }

    /// `selftest hold` (a connection hold that also ends when the peer pid exits), `selftest slow` (3 s) and
    /// `selftest echo`.
    @MainActor private static func registerTestVerbs(_ registry: ControlCommandRegistry, watches: HoldWatches,
                                                     lifetime: Lifetime) {
        registry.register("selftest hold", policy: .low, offOnly: false, cliAllowed: true, holds: true,
                          summary: "Self-test hold", lifetime: lifetime) { _, context in
            guard let hold = context.hold else { return .failure(ControlExit.usage, "not a hold") }
            let pid = context.peer.pid
            guard pid > 1, let started = context.peer.startTime else {
                return .failure(ControlExit.refused, L("Snaptic couldn’t identify the caller."))
            }
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak hold] in
                MainActor.assumeIsolated {
                    source.cancel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + pidGraceSeconds) {
                        MainActor.assumeIsolated {
                            hold?.finish(.ok("Awake hold ended: the process exited."))
                        }
                    }
                }
            }
            source.resume()
            let id = watches.add(source)
            watches.track(hold)
            // Armed first, then re-verified (security M4): the same process, still there, and the client still on.
            guard !hold.isClosed, SNProcess.startTime(for: pid) == started else {
                watches.remove(id)
                return .failure(ControlExit.refused, L("Snaptic couldn’t identify the caller."))
            }
            // Strong on purpose: the connection may be gone when this runs, and the hold drops its handlers once
            // they ran, so there is no lasting cycle.
            hold.onClose {
                watches.remove(id)
                let reason = hold.closeReason ?? .eof
                say("closed " + (reason == .finished ? "pid" : reason.rawValue) + "\n")
            }
            return .holding("Holding until this command ends. Press Control-C to stop.")
        }
        registry.register("selftest slow", policy: .read, offOnly: false, cliAllowed: true,
                          summary: "Self-test slow request", lifetime: lifetime) { _, _ in
            try? await Task.sleep(for: .seconds(3))
            return .ok("slow")
        }
        registry.register("selftest echo", policy: .read, offOnly: false, cliAllowed: true,
                          summary: "Self-test echo", lifetime: lifetime) { request, _ in
            .ok(request.arguments.isEmpty ? "echo" : request.arguments.joined(separator: " "))
        }
    }

    /// Both `awake hold` forms over the server's own socket, from a client on a background queue (the handlers run on
    /// main): the connection form answers `holding` and its hold ends with `eof` when the client closes; the `--pid`
    /// form answers once, isn't held and the server closes the connection. Bounded by `awakeCheckSeconds`.
    @MainActor private static func awakeHoldCheck(socket: String, log: AwakeProbeLog, gate: PoolGate) -> [String] {
        let result = HoldClientResult()
        let pid = getpid()
        DispatchQueue.global(qos: .userInitiated).async {
            result.finish(holdClientProblems(socket: socket, pid: pid))
        }
        let deadline = Date().addingTimeInterval(awakeCheckSeconds)
        while Date() < deadline {
            if result.isDone && !log.closes.isEmpty && gate.isIdle { break }
            _ = CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        guard result.isDone else { return ["the client timed out"] }
        var problems = result.problems
        if log.closes != ["eof"] { problems.append("the connection hold closed as \(log.closes), expected [eof]") }
        if !gate.isIdle { problems.append("a slot leaked") }
        if log.calls.map({ $0.verb }) != ["awake hold", "awake hold"] || !log.calls.allSatisfy({ $0.hadHold }) {
            problems.append("the hold handler saw \(log.calls)")
        }
        return problems
    }

    /// The client side of `awakeHoldCheck` (any thread; plain sockets with poll timeouts).
    private static func holdClientProblems(socket path: String, pid: pid_t) -> [String] {
        var problems: [String] = []
        // Connection form.
        if let fd = connectTo(path) {
            let lines = exchange(fd, ControlRequest(verb: "awake", arguments: ["hold", "--max", "5m"], json: false,
                                                    skipConfirmation: false), waitForEOF: false)
            let reply = lines.lines.first.flatMap(KitControl.decodeResponse)
            if reply?.holding != true || reply?.exitCode != ControlExit.ok
                || reply?.output.hasPrefix("Holding until this command ends") != true {
                problems.append("connection form: \(String(describing: reply))")
            }
            if lines.eof { problems.append("connection form: the server closed a held connection") }
            close(fd)
        } else {
            problems.append("couldn't connect")
        }
        // `--pid` form.
        if let fd = connectTo(path) {
            let lines = exchange(fd, ControlRequest(verb: "awake", arguments: ["hold", "--pid", String(pid)],
                                                    json: false, skipConfirmation: false), waitForEOF: true)
            let reply = lines.lines.first.flatMap(KitControl.decodeResponse)
            if reply?.holding != false || reply?.exitCode != ControlExit.ok
                || reply?.output.hasPrefix("Holding while process \(pid) runs") != true {
                problems.append("--pid form: \(String(describing: reply))")
            }
            if !lines.eof { problems.append("--pid form: the server kept the connection open") }
            if lines.lines.count != 1 { problems.append("--pid form: \(lines.lines.count) lines") }
            close(fd)
        } else {
            problems.append("couldn't connect")
        }
        return problems
    }

    private static func connectTo(_ path: String) -> Int32? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    /// Sends one request, then reads lines for at most 2 s: until the first line, or (`waitForEOF`) until EOF.
    private static func exchange(_ fd: Int32, _ request: ControlRequest,
                                             waitForEOF: Bool) -> (lines: [Data], eof: Bool) {
        guard let line = KitControl.encode(request) else { return ([], false) }
        let sent = line.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base + offset, raw.count - offset)
                if n > 0 { offset += n } else if n < 0 && errno == EINTR { continue } else { return false }
            }
            return true
        }
        guard sent else { return ([], false) }
        var reader = ControlLineReader()
        var lines: [Data] = []
        var chunk = [UInt8](repeating: 0, count: 4_096)
        let deadline = Date().addingTimeInterval(2)
        while true {
            if !lines.isEmpty && !waitForEOF { return (lines, false) }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return (lines, false) }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, Int32(remaining * 1000) + 1)
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { continue }
            let n = chunk.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
            if n < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            guard n > 0 else {
                if let rest = reader.remainder { lines.append(rest) }
                return (lines.filter { !KitControl.isPing($0) }, true)
            }
            lines += reader.append(chunk[0..<n]).filter { !KitControl.isPing($0) }
        }
    }

    /// Whether `path`'s directory is the token file's directory or below it (both resolved, no symlink games).
    private static func isUnder(directoryOf tokenFile: String, _ path: String) -> Bool {
        guard KitControl.isUsableSocketPath(path), !path.split(separator: "/").contains(".."),
              let base = resolved((tokenFile as NSString).deletingLastPathComponent),
              let directory = resolved((path as NSString).deletingLastPathComponent) else { return false }
        return directory == base || directory.hasPrefix(base + "/")
    }

    private static func resolved(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    /// What a child writes once its prologue (fd closing, parent identity check) passed.
    static let readyLine = "ready"
    /// How long the parent waits for both children to report ready.
    static let readySeconds: Double = 5

    private static func runChild(_ arguments: [String]) -> Never {
        _ = HelperPrologue.run(arguments, kind: .selftestChild, onLine: { _ in }, onEOF: { exit(0) })
        // The parent waits for this before it kills itself, so the test proves that a child
        // which passed the real prologue still sees EOF (not that it never started).
        say(readyLine + "\n")
        CFRunLoopRun()
        exit(0)
    }

    private static func runParent(_ arguments: [String]) -> Never {
        guard arguments.count == 3, tokenMatches(file: arguments[2]) else { exit(KitArgs.exitUsage) }
        MainActor.assumeIsolated {
            let spawner = HelperSpawner()
            // Identity and canary run off main, as in the app; the run loop delivers the result.
            spawner.prepare()
            let prepared = Date().addingTimeInterval(readySeconds)
            while !spawner.isReady && spawner.unavailable == nil && Date() < prepared {
                _ = CFRunLoopRunInMode(.defaultMode, 0.05, false)
            }
            guard spawner.isReady else {
                say("helpers unavailable: \(spawner.unavailable ?? "preparation timed out")\n")
                exit(1)
            }
            let ready = ReadyCounter()
            var lines: [String] = []
            for _ in 0..<2 {
                // The spawner verifies each suspended child off main; the run loop delivers
                // the result, as it does in the app.
                let attempt = SpawnAttempt()
                Task { @MainActor in
                    do {
                        attempt.handle = try await spawner.spawn(.selftestChild, arguments: [], onLine: { line in
                            if String(decoding: line, as: UTF8.self) == readyLine { ready.count += 1 }
                        }, onExit: { status in ready.exits.append(status) })
                    } catch {
                        attempt.failure = "\(error)"
                    }
                    attempt.done = true
                }
                let spawned = Date().addingTimeInterval(readySeconds)
                while !attempt.done && Date() < spawned {
                    _ = CFRunLoopRunInMode(.defaultMode, 0.05, false)
                }
                guard let handle = attempt.handle else {
                    say("spawn failed: \(attempt.failure ?? "timed out")\n")
                    exit(1)
                }
                lines.append("child \(handle.pid) \(handle.startTime)\n")
            }
            // Lines arrive on the main queue; the run loop services it.
            let deadline = Date().addingTimeInterval(readySeconds)
            while ready.count < 2 && ready.exits.isEmpty && Date() < deadline {
                _ = CFRunLoopRunInMode(.defaultMode, 0.05, false)
            }
            guard ready.count == 2 else {
                say("children not ready: \(ready.count) ready, exits \(ready.exits)\n")
                exit(1)
            }
            for line in lines { say(line) }
            // No cleanup on purpose: the children must notice our death by themselves.
            kill(getpid(), SIGKILL)
        }
        exit(1)
    }

    /// Constant-time compare of the environment token with the file's contents.
    static func tokenMatches(file path: String) -> Bool {
        guard let expected = ProcessInfo.processInfo.environment[tokenVariable], expected.utf8.count >= 16 else {
            return false
        }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_size <= 256 else {
            return false
        }
        var buffer = [UInt8](repeating: 0, count: 256)
        let n = buffer.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
        guard n > 0 else { return false }
        var stored = Array(buffer[0..<n])
        while let last = stored.last, last == 0x0A || last == 0x0D || last == 0x20 { stored.removeLast() }
        let wanted = Array(expected.utf8)
        guard stored.count == wanted.count else { return false }
        var difference: UInt8 = 0
        for i in 0..<wanted.count { difference |= stored[i] ^ wanted[i] }
        return difference == 0
    }

    /// Unbuffered stdout (print is reserved for the CLI client).
    private static func say(_ text: String) {
        text.withCString { pointer in _ = write(STDOUT_FILENO, pointer, strlen(pointer)) }
    }
}

/// One spawn's result for the self-test parent (main thread only).
private final class SpawnAttempt {
    var handle: HelperHandle?
    var failure: String?
    var done = false
}

/// The control-server self-test's process watches, by hold (main thread only).
@MainActor private final class HoldWatches {
    private var sources: [UInt64: DispatchSourceProcess] = [:]
    private var next: UInt64 = 0

    func add(_ source: DispatchSourceProcess) -> UInt64 {
        next &+= 1
        sources[next] = source
        return next
    }

    func remove(_ id: UInt64) {
        sources.removeValue(forKey: id)?.cancel()
    }

    /// Every `selftest hold` hold, for the SIGUSR1 stop check (a test process: they are never released).
    private var holds: [ControlHold] = []

    func track(_ hold: ControlHold) {
        holds.append(hold)
    }

    /// Finishes the oldest hold that is still open (the other open ones are left to the server's grace).
    func finishFirstOpen(_ final: ControlResponse) {
        holds.first { !$0.isClosed }?.finish(final)
    }
}

/// Main-thread-only tallies for the self-test parent.
private final class ReadyCounter {
    var count = 0
    var exits: [Int32] = []
}

/// What the Awake probe handlers saw (main thread only).
@MainActor private final class AwakeProbeLog {
    var calls: [(verb: String, hadHold: Bool)] = []
    var closes: [String] = []
}

/// The Awake verb check's result (main thread only).
@MainActor private final class AwakeCheckRun {
    var problems: [String] = []
    var done = false
}

/// The registry clock the Awake checks drive (main thread only).
@MainActor private final class AwakeCheckClock {
    var seconds: Double = 1_000
}

/// The control server's pool lines: silent until `open()`, the last counts kept either way (any thread).
private final class PoolGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var held = 0
    private var active = 0

    /// Records the counts; true when the line should be printed.
    func record(held: Int, active: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        self.held = held
        self.active = active
        return opened
    }

    func open() {
        lock.lock(); defer { lock.unlock() }
        opened = true
    }

    var isIdle: Bool {
        lock.lock(); defer { lock.unlock() }
        return held == 0 && active == 0
    }
}

/// The hold check client's result (any thread).
private final class HoldClientResult: @unchecked Sendable {
    private let lock = NSLock()
    private var finished: [String]?

    func finish(_ problems: [String]) {
        lock.lock(); defer { lock.unlock() }
        finished = problems
    }

    var isDone: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished != nil
    }

    var problems: [String] {
        lock.lock(); defer { lock.unlock() }
        return finished ?? []
    }
}


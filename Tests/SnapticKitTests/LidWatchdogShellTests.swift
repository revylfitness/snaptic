import Foundation
import XCTest
@testable import SnapticKit
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// The B3.2 shell test (owner: T-lid-kit; PLAN 0.3.1 B3.2 "Shell test (CI)", B5). The real watchdog script and command
// run under real shells with every tool stubbed: on Linux under dash (/bin/sh) and `bash --posix`, on macOS under
// bash 3.2 (/bin/sh and `/bin/bash --posix`). The stubs record their calls and keep a fake SleepDisabled (the
// preference and the kernel's value), lid, battery, heat and clock; the loop period is 0.2 s. Every process the
// test starts is killed at the end.

final class LidWatchdogShellTests: XCTestCase {
    private var envs: [StubEnv] = []

    override func tearDown() {
        for e in envs { e.cleanup() }
        envs = []
        super.tearDown()
    }

    private func env(_ shell: StubEnv.Shell) throws -> StubEnv {
        let e = try StubEnv(shell: shell)
        envs.append(e)
        return e
    }

    private var shells: [StubEnv.Shell] {
        var out: [StubEnv.Shell] = [.sh]
        if StubEnv.bashPath != nil { out.append(.bashPosix) }
        return out
    }

    // MARK: The command

    /// `check`'s 3 and 64 become the command's exit status, before anything is set.
    func testCheckExitBecomesTheCommandsStatus() throws {
        for shell in shells {
            let held = try env(shell)
            held.ctl("pref", "1")
            let r1 = try held.runCommand()
            XCTAssertEqual(r1.status, 3, "\(shell): someone else holds it")
            XCTAssertEqual(r1.stdout, "", "\(shell): no pid")

            let invalid = try env(shell)
            var argv = invalid.argv
            argv[4] = "9"
            let r2 = try invalid.runCommand(argv: argv)
            XCTAssertEqual(r2.status, 64, "\(shell): floor 9")
            XCTAssertEqual(r2.stdout, "", "\(shell)")

            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertTrue(held.sets.isEmpty, "\(shell): nothing set")
            XCTAssertTrue(invalid.sets.isEmpty, "\(shell): nothing set")
            XCTAssertFalse(held.log.contains { $0.hasPrefix("nohup") }, "\(shell): run never started")
        }
    }

    /// `$!` is the watchdog's pid, the command returns at once while the watchdog runs on, and the stop file ends
    /// it with sleep turned back on.
    func testCommandBackgroundsTheWatchdog() throws {
        for shell in shells {
            let e = try env(shell)
            let r = try e.runCommand()
            XCTAssertEqual(r.status, 0, "\(shell)")
            XCTAssertLessThan(r.seconds, 3, "\(shell): returns at once")
            let pid = try XCTUnwrap(Int32(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)), "\(shell): \(r.stdout)")
            e.watch(pid)
            XCTAssertTrue(e.waitFor("pref", "1"), "\(shell): turned sleep off")
            XCTAssertEqual(e.sets.first?.value, "1")
            XCTAssertEqual(e.sets.first?.parent, pid, "\(shell): $! is the process that runs the script")
            XCTAssertFalse(StubEnv.isGone(pid), "\(shell): still running after the command returned")
            e.touch(e.stopFile)
            XCTAssertTrue(e.waitFor("pref", "0"), "\(shell): the stop file restores")
            XCTAssertTrue(e.waitGone(pid), "\(shell): and ends the watchdog")
        }
    }

    // MARK: The watchdog

    private struct Scenario {
        var name: String
        var setup: (StubEnv) -> Void = { _ in }
        var act: (StubEnv, Process) -> Void
        /// `pmset -a disablesleep 1` happens.
        var sets = true
        /// The last write is `disablesleep 0`.
        var restores = true
        var sleepnow = false
    }

    private static let discharging20 = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=4653155)\t20%; discharging; 1:02 remaining present: true\n"
    private static let discharging21 = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=4653155)\t21%; discharging; 1:02 remaining present: true\n"
    private static let dischargingUnreadable = "Now drawing from 'Battery Power'\n -InternalBattery-0 discharging\n"

    private var scenarios: [Scenario] {
        [
            // The EXIT trap restores after every way out (B3.2).
            Scenario(name: "stop file", act: { e, _ in e.touch(e.stopFile) }),
            Scenario(name: "beacon removed", act: { e, _ in e.remove(e.beatFile) }),
            Scenario(name: "beacon replaced by a symlink", act: { e, _ in
                e.remove(e.beatFile)
                e.symlink(e.beatFile, to: e.dir + "/ctl/owner")
            }),
            Scenario(name: "beacon owned by someone else", act: { e, _ in e.ctl("owner", "4242") }),
            Scenario(name: "stale beacon", act: { e, _ in e.ctl("mtime", String(Int(Date().timeIntervalSince1970) - 100)) }),
            Scenario(name: "unreadable clock", act: { e, _ in e.ctl("date_text", "12abc") }),
            // START is the third clock read (after the start and the 5 s limit before the set).
            Scenario(name: "induced arithmetic error", setup: { e in
                e.ctl("date_skip", "2")
                e.ctl("date_once", "12abc")
            }, act: { _, _ in }),
            Scenario(name: "unreadable beacon time", act: { e, _ in e.ctl("mtime", "x1") }),
            Scenario(name: "TERM (shutdown: no sleepnow)", setup: { e in e.ctl("clamshell", "Yes") },
                     act: { _, p in p.terminate() }),
            // A TERM while `pmset -a disablesleep 1` runs is handled once it returns: WESET is already 1 (r2 S2-1).
            Scenario(name: "TERM while setting", setup: { e in
                e.ctl("clamshell", "Yes")
                e.ctl("set_delay", "6")
            }, act: { _, p in p.terminate() }),
            // A terminal's ^Z can't stop it (r1 S4): still answers the stop file.
            Scenario(name: "TSTP ignored", act: { e, p in
                _ = kill(p.processIdentifier, SIGTSTP)
                Thread.sleep(forTimeInterval: 0.5)
                e.touch(e.stopFile)
            }),
            Scenario(name: "cap", act: { e, _ in e.ctl("date_jump", "200000") }),
            Scenario(name: "Snaptic gone", act: { e, _ in e.ctl("alive", nil) }),
            Scenario(name: "battery at the floor", act: { e, _ in e.ctl("batt", Self.discharging20) }),
            Scenario(name: "battery unreadable twice", act: { e, _ in e.ctl("batt", Self.dischargingUnreadable) }),
            Scenario(name: "heat", act: { e, _ in e.ctl("thermal", "2") }),
            // Fails safe like the battery (r1 S3): an unreadable heat level twice in a row restores.
            Scenario(name: "heat unreadable twice", act: { e, _ in e.ctl("thermal", "x") }),
            // A beacon lookup that never returns (a stalled mount) holds only the checking child (r1 S3).
            Scenario(name: "beacon check hangs", act: { e, _ in e.ctl("stat_hang", "") }),
            Scenario(name: "kernel disagrees", act: { e, _ in e.ctl("kernel", "0") }),
            Scenario(name: "kernel unreadable", act: { e, _ in e.ctl("kernel", "none") }),
            Scenario(name: "preference unreadable", act: { e, _ in e.ctl("pref_fail", "") }),
            // sleepnow runs only with the lid shut, closing it sleeping the Mac, not shutting down (B3.2).
            Scenario(name: "stop with the lid shut", setup: { e in e.ctl("clamshell", "Yes") },
                     act: { e, _ in e.touch(e.stopFile) }, sleepnow: true),
            Scenario(name: "lid shut, closing it doesn't sleep", setup: { e in
                e.ctl("clamshell", "Yes")
                e.ctl("causes", "No")
            }, act: { e, _ in e.touch(e.stopFile) }),
            // The kernel is slow to follow: cleanup waits for it, then still tries (the kernel refuses while set).
            Scenario(name: "kernel slow to clear", setup: { e in e.ctl("clamshell", "Yes") }, act: { e, _ in
                e.ctl("kernel", "1")
                e.touch(e.stopFile)
            }, sleepnow: true),
            // WESET=0 only when both sources read 0, twice (B3.2).
            Scenario(name: "reset by another app", setup: { e in e.ctl("clamshell", "Yes") },
                     act: { e, _ in e.ctl("pref", "0") }, restores: false),
            // Never taken, and the late password (B3.2).
            Scenario(name: "stop file before the start", setup: { e in e.touch(e.stopFile) }, act: { _, _ in },
                     sets: false),
            // The stop-file lookup stalls past the app's verify while the stop file is taken away (r2 S2-3): over 5 s
            // after it started, it never sets.
            Scenario(name: "stalled before the start", setup: { e in
                e.touch(e.stopFile)
                e.ctl("stop_hang", "8")
            }, act: { e, _ in e.remove(e.stopFile) }, sets: false),
            Scenario(name: "already turned off", setup: { e in e.ctl("pref", "1") }, act: { _, _ in }, sets: false),
            Scenario(name: "preference odd", setup: { e in e.ctl("pref", "2") }, act: { _, _ in }, sets: false),
            Scenario(name: "no root domain", setup: { e in e.ctl("kernel", "none") }, act: { _, _ in }, sets: false),
            // D is entered once, and only as U's own 0700 directory on /var/folders's volume (r1 S3).
            Scenario(name: "beacon directory on another volume", setup: { e in e.ctl("dir_dev", "2") },
                     act: { _, _ in }, sets: false),
            Scenario(name: "beacon directory someone else's", setup: { e in e.ctl("dir_owner", "4242") },
                     act: { _, _ in }, sets: false),
            Scenario(name: "beacon directory not 0700", setup: { e in e.ctl("dir_mode", "755") },
                     act: { _, _ in }, sets: false),
            // The post-set check: set, but the kernel never follows → restore.
            Scenario(name: "kernel never sets", setup: { e in e.ctl("kernel", "absent") }, act: { _, _ in }),
        ]
    }

    /// Every scenario runs at once (each in its own directory), so the whole table takes a few seconds per shell.
    func testEveryExitRestores() throws {
        for shell in shells {
            var running: [(scenario: Scenario, env: StubEnv, process: Process)] = []
            for s in scenarios {
                let e = try env(shell)
                s.setup(e)
                let p = try e.runScript(mode: "run")
                running.append((s, e, p))
            }
            for r in running where r.scenario.sets {
                XCTAssertTrue(r.env.waitFor("pref", "1") || r.env.sets.first?.value == "1", "\(shell) – \(r.scenario.name): sets")
            }
            Thread.sleep(forTimeInterval: 0.5)
            for r in running { r.scenario.act(r.env, r.process) }
            for r in running {
                let label = "\(shell) – \(r.scenario.name)"
                // By pid, not `Process.isRunning`: on Linux Foundation sees an exit through a descriptor the children
                // inherit, and a hanging stub (the "beacon check hangs" scenario) keeps it open after the watchdog exits.
                XCTAssertTrue(r.env.waitGone(r.process.processIdentifier, seconds: 20), "\(label): exits")
                let sets = r.env.sets.map(\.value)
                if r.scenario.sets {
                    XCTAssertEqual(sets.first, "1", "\(label): \(sets)")
                    XCTAssertEqual(sets.last == "0", r.scenario.restores, "\(label): restores \(sets)")
                    if r.scenario.restores { XCTAssertEqual(r.env.read("pref"), "0", label) }
                } else {
                    XCTAssertEqual(sets, [], label)
                }
                XCTAssertEqual(r.env.log.contains("pmset sleepnow"), r.scenario.sleepnow, "\(label): sleepnow")
                r.env.cleanup()
            }
        }
    }

    /// INT and QUIT never end it (r2 S2-2). Its real launch (`&` in a shell without job control) starts it with both
    /// ignored, and the script ignores them itself, so a direct run behaves the same; the stop file still restores.
    func testIntAndQuitDontEndIt() throws {
        for shell in shells {
            for viaCommand in [true, false] {
                let label = "\(shell), \(viaCommand ? "launched by the command" : "run directly")"
                let e = try env(shell)
                e.ctl("clamshell", "Yes")
                let pid: Int32
                if viaCommand {
                    let r = try e.runCommand()
                    pid = try XCTUnwrap(Int32(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)), "\(label): \(r.stdout)")
                    e.watch(pid)
                } else {
                    pid = try e.runScript(mode: "run").processIdentifier
                }
                XCTAssertTrue(e.waitFor("pref", "1"), label)
                _ = kill(pid, SIGINT)
                _ = kill(pid, SIGQUIT)
                Thread.sleep(forTimeInterval: 1)
                XCTAssertFalse(StubEnv.isGone(pid), "\(label): still running")
                XCTAssertEqual(e.sets.map(\.value), ["1"], label)
                e.touch(e.stopFile)
                XCTAssertTrue(e.waitGone(pid), "\(label): the stop file ends it")
                XCTAssertEqual(e.sets.map(\.value), ["1", "0"], label)
                XCTAssertTrue(e.log.contains("pmset sleepnow"), "\(label): through the stop path, not a signal's")
            }
        }
    }

    /// The loop keeps going while everything is in order: a fresh beacon, Snaptic alive, both sources at 1, power.
    func testHealthyWatchdogKeepsRunning() throws {
        for shell in shells {
            let e = try env(shell)
            e.ctl("batt", Self.discharging21)
            let p = try e.runScript(mode: "run")
            XCTAssertTrue(e.waitFor("pref", "1"), "\(shell)")
            Thread.sleep(forTimeInterval: 2)
            XCTAssertTrue(p.isRunning, "\(shell): still running")
            XCTAssertGreaterThanOrEqual(e.log.filter { $0 == "sleep 0.2" }.count, 3, "\(shell): the 0.2 s period")
            XCTAssertEqual(e.sets.map(\.value), ["1"], "\(shell)")
            p.terminate()
            XCTAssertNotNil(e.waitExit(p, seconds: 10), "\(shell)")
            XCTAssertEqual(e.sets.map(\.value), ["1", "0"], "\(shell)")
        }
    }

    /// `check` reads both sources: 0 and 0 (an absent kernel property counts as 0, r3 NB1) passes; anything else is 3.
    func testCheckReadsBothSources() throws {
        let cases: [(String, String?, String, Int32)] = [
            ("pref 0, kernel follows", nil, "follow", 0),
            ("kernel property absent", nil, "absent", 0),
            ("preference block without SleepDisabled", "pref_absent", "follow", 0),
            ("preference 1", "pref1", "follow", 3),
            ("preference odd", "pref_odd", "follow", 3),
            ("preference unreadable", "pref_fail", "follow", 3),
            ("kernel 1", nil, "1", 3),
            ("no root domain", nil, "none", 3),
        ]
        for shell in shells {
            var running: [(name: String, expected: Int32, env: StubEnv, process: Process)] = []
            for (name, pref, kernel, expected) in cases {
                let e = try env(shell)
                switch pref {
                case "pref1"?: e.ctl("pref", "1")
                case "pref_odd"?: e.ctl("pref", "x")
                case let flag?: e.ctl(flag, "")
                case nil: break
                }
                e.ctl("kernel", kernel)
                let p = try e.runScript(mode: "check")
                running.append((name, expected, e, p))
            }
            for r in running {
                XCTAssertEqual(r.env.waitExit(r.process, seconds: 15), r.expected, "\(shell) – \(r.name)")
                XCTAssertTrue(r.env.sets.isEmpty, "\(shell) – \(r.name)")
            }
        }
    }

    /// The script's argument rules and `Arguments.validated` agree on every case (B3.2: "validated in Kit by the
    /// same rules as the script").
    func testScriptAndSwiftValidationAgree() throws {
        var rng = SeededGenerator(seed: 0x64)
        let alphabet = Array("abcdefABCDEF0123456789g_/+.-' \"$*?~")
        func pick(_ n: Int) -> Int { Int(rng.next() % UInt64(max(1, n))) }
        func randomString(_ maxLength: Int) -> String {
            String((0..<pick(maxLength + 1)).map { _ in alphabet[pick(alphabet.count)] })
        }
        for shell in shells {
            let e = try env(shell)
            var running: [(argv: [String], valid: Bool, process: Process)] = []
            for i in 0..<60 {
                var token = e.token
                if i % 4 == 1 { token = String(token.dropLast()) + String(alphabet[pick(alphabet.count)]) }
                if i % 4 == 2 { token = randomString(34) }
                var dir = e.beacon
                if i % 3 == 1 { dir = e.root + "/" + randomString(6) + "/snaptic-lid" }
                if i % 3 == 2 { dir = randomString(30) }
                let cap = [3_599, 3_600, 86_400, 86_401, 50_000][pick(5)]
                let floor = [9, 10, 20, 50, 51][pick(5)]
                let valid = LidWatchdog.Arguments.validated(uid: getuid(), pid: getpid(), token: token, capSeconds: cap,
                                                            floor: floor, dir: dir, tempRoot: e.root) != nil
                let argv = [String(getuid()), String(getpid()), token, String(cap), String(floor), dir]
                let p = try e.runScript(mode: "check", argv: argv)
                running.append((argv, valid, p))
            }
            XCTAssertTrue(running.contains { $0.valid } && running.contains { !$0.valid }, "both kinds are tried")
            for r in running {
                let status = e.waitExit(r.process, seconds: 20)
                // bash 3.2 in a UTF-8 locale reads the token's `[0-9a-f]` by collation, which can take uppercase
                // too: there the script may accept a token Swift refuses (Swift is the stricter side, and only Swift
                // makes tokens). Everything Swift accepts, the script accepts.
                if r.valid || !r.argv[2].contains(where: { $0.isUppercase }) {
                    XCTAssertEqual(status, r.valid ? 0 : 64, "\(shell): \(r.argv)")
                } else {
                    XCTAssertNotNil(status, "\(shell): \(r.argv)")
                }
            }
        }
    }

    /// `quoted` survives a real shell for any text (the round trip B5 asks for).
    func testQuotingThroughARealShell() throws {
        var rng = SeededGenerator(seed: 0x51)
        let alphabet = Array("a'\"\\$`!*?[]{}()<>|&;~# \n\té→")
        for shell in shells {
            let e = try env(shell)
            var words: [String] = []
            for _ in 0..<40 {
                words.append(String((0..<Int(rng.next() % 16)).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] }))
            }
            let line = "for w in " + words.map(LidWatchdog.quoted).joined(separator: " ") + #"; do printf '%s\0' "$w"; done"#
            let r = try e.runOuter(line)
            XCTAssertEqual(r.status, 0)
            let back = r.stdoutData.split(separator: 0, omittingEmptySubsequences: false).dropLast()
                .map { String(decoding: $0, as: UTF8.self) }
            XCTAssertEqual(back, words, "\(shell)")
        }
    }
}

/// One stub directory: `bin/` (the stubs), `ctl/` (their state), `log`, `sets`, `pids`, and the beacon directory
/// under `folders/zz/T/snaptic-lid` (the script's root is swapped from /var/folders to `folders`).
private final class StubEnv {
    enum Shell: CustomStringConvertible {
        /// /bin/sh: dash on Linux, bash 3.2 (POSIX mode) on macOS.
        case sh
        /// `bash --posix`.
        case bashPosix

        var description: String { self == .sh ? "sh" : "bash --posix" }
    }

    static let bashPath = ["/bin/bash", "/usr/bin/bash"].first { FileManager.default.isExecutableFile(atPath: $0) }
    static let realTools: [String: String] = {
        var out: [String: String] = [:]
        for (name, candidates) in [("awk", ["/usr/bin/awk", "/bin/awk"]), ("sed", ["/usr/bin/sed", "/bin/sed"]),
                                   ("sleep", ["/bin/sleep", "/usr/bin/sleep"]), ("date", ["/bin/date", "/usr/bin/date"])] {
            out[name] = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
        }
        return out
    }()

    let shell: Shell
    let dir: String
    let root: String
    let beacon: String
    let token = "0123456789abcdef0123456789abcdef"
    let script: String
    let commandTools: [String: String]
    private var watched: [Int32] = []
    private var cleaned = false

    var stopFile: String { beacon + "/stop-" + token }
    var beatFile: String { beacon + "/beat-" + token }
    var argv: [String] { [String(getuid()), String(getpid()), token, String(LidWatchdog.capSeconds), "20", beacon] }

    init(shell: Shell) throws {
        self.shell = shell
        let base = NSTemporaryDirectory().hasSuffix("/") ? NSTemporaryDirectory() : NSTemporaryDirectory() + "/"
        dir = base + "lidtest-" + UUID().uuidString
        root = dir + "/folders"
        beacon = root + "/zz/T/snaptic-lid"
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir + "/bin", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dir + "/ctl", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: beacon, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var tools: [String: String] = [:]
        for path in LidWatchdog.toolPaths {
            let name = (path as NSString).lastPathComponent
            tools[path] = dir + "/bin/" + name
        }
        var commandTools = [LidWatchdog.nohupPath: dir + "/bin/nohup", LidWatchdog.shellPath: "/bin/sh"]
        if shell == .bashPosix { commandTools[LidWatchdog.shellPath] = dir + "/bin/sh" }
        self.commandTools = commandTools
        script = LidWatchdog.script(tools: tools, period: 0.2, stale: 20, tempRoot: root)
        try writeStubs()
        for (k, v) in ["pref": "0", "kernel": "follow", "clamshell": "No", "causes": "Yes", "owner": String(getuid()),
                       "dir_owner": String(getuid()), "dir_mode": "700", "dir_dev": "1",
                       "date_jump": "0", "alive": "", "thermal": "0",
                       "batt": "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1234)\t80%; charged; 0:00 remaining present: true\n"] {
            ctl(k, v)
        }
        touch(beatFile)
    }

    // MARK: Stubs

    private func stub(_ name: String, _ body: String) throws {
        let path = dir + "/bin/" + name
        try ("#!/bin/sh\nS='" + dir + "'\n" + body + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private func writeStubs() throws {
        let t = Self.realTools
        let now = #"$(( $(\#(t["date"] ?? "/bin/date") +%s) + $(cat "$S/ctl/date_jump") ))"#
        try stub("pmset", #"""
        echo "pmset $*" >> "$S/log"
        case "$1" in
        -g)
          if [ "$2" = batt ]; then cat "$S/ctl/batt"; exit 0; fi
          [ -f "$S/ctl/pref_fail" ] && exit 1
          printf 'System-wide power settings:\n'
          [ -f "$S/ctl/pref_absent" ] || printf ' SleepDisabled\t\t%s\n' "$(cat "$S/ctl/pref")"
          printf 'Currently in use:\n standby              1\n SleepDisabled        9\n';;
        -a)
          [ "$2" = disablesleep ] || exit 1
          echo "$3 $PPID" >> "$S/sets"
          echo "$3" > "$S/ctl/pref"
          [ "$3" = 1 ] && [ -f "$S/ctl/set_delay" ] && \#(t["sleep"] ?? "/bin/sleep") "$(cat "$S/ctl/set_delay")"
          exit 0;;
        sleepnow) ;;
        *) exit 1;;
        esac
        """#)
        try stub("ioreg", #"""
        echo "ioreg $*" >> "$S/log"
        k=$(cat "$S/ctl/kernel")
        [ "$k" = none ] && exit 1
        [ "$k" = follow ] && k=$(cat "$S/ctl/pref")
        printf '+-o IOPMrootDomain  <class IOPMrootDomain, id 0x100000103, registered, matched, active, busy 0 (0 ms), retain 30>\n'
        printf '    {\n'
        printf '      "AppleClamshellState" = %s\n' "$(cat "$S/ctl/clamshell")"
        printf '      "AppleClamshellCausesSleep" = %s\n' "$(cat "$S/ctl/causes")"
        case "$k" in 1) printf '      "SleepDisabled" = Yes\n';; 0) printf '      "SleepDisabled" = No\n';; esac
        printf '    }\n'
        """#)
        try stub("awk", "echo awk >> \"$S/log\"\nexec " + (t["awk"] ?? "/usr/bin/awk") + " \"$@\"")
        try stub("sed", "echo sed >> \"$S/log\"\nexec " + (t["sed"] ?? "/usr/bin/sed") + " \"$@\"")
        // BSD stat without -L (lstat), run from inside D: names are relative. The type is real, owners, modes and
        // devices come from ctl; `stat_hang` makes a beacon lookup never return, `stop_hang` makes a stop-file lookup
        // take that many seconds and then find nothing.
        try stub("stat", #"""
        echo "stat $*" >> "$S/log"
        [ "$1" = -f ] || exit 1
        case "$2" in
        '%HT %u')
          case "$3" in
          beat-*) [ -f "$S/ctl/stat_hang" ] && { echo $$ >> "$S/hung"; exec \#(t["sleep"] ?? "/bin/sleep") 60; };;
          stop-*) [ -f "$S/ctl/stop_hang" ] && { echo $$ >> "$S/hung"; \#(t["sleep"] ?? "/bin/sleep") "$(cat "$S/ctl/stop_hang")"; exit 1; };;
          esac
          if [ -L "$3" ]; then y='Symbolic Link'; elif [ -f "$3" ]; then y='Regular File'; elif [ -d "$3" ]; then y=Directory; else exit 1; fi
          echo "$y $(cat "$S/ctl/owner")";;
        '%HT %u %Lp %d')
          [ -d "$3" ] && [ ! -L "$3" ] || exit 1
          echo "Directory $(cat "$S/ctl/dir_owner") $(cat "$S/ctl/dir_mode") $(cat "$S/ctl/dir_dev")";;
        %d) echo 1;;
        %m) if [ -f "$S/ctl/mtime" ]; then cat "$S/ctl/mtime"; else echo \#(now); fi;;
        *) exit 1;;
        esac
        """#)
        try stub("date", #"""
        echo "date $*" >> "$S/log"
        if [ -f "$S/ctl/date_once" ]; then
          n=$(cat "$S/ctl/date_skip" 2>/dev/null); n=${n:-0}
          if [ "$n" -gt 0 ]; then echo $((n-1)) > "$S/ctl/date_skip"
          else cat "$S/ctl/date_once"; rm -f "$S/ctl/date_once"; exit 0; fi
        fi
        if [ -f "$S/ctl/date_text" ]; then cat "$S/ctl/date_text"; exit 0; fi
        echo \#(now)
        """#)
        try stub("kill", "echo \"kill $*\" >> \"$S/log\"\n[ -f \"$S/ctl/alive\" ]")
        // The loop's 0.2 s period is real; the restore loops' 0.5 s and 1 s waits are shortened.
        try stub("sleep", #"""
        echo "sleep $*" >> "$S/log"
        echo "$$" >> "$S/pids"
        case "$1" in 0.2) t=0.2;; *) t=0.05;; esac
        exec \#(t["sleep"] ?? "/bin/sleep") "$t"
        """#)
        try stub("notifyutil", "echo \"notifyutil $*\" >> \"$S/log\"\necho \"com.apple.system.thermalpressurelevel $(cat \"$S/ctl/thermal\")\"")
        try stub("nohup", "echo nohup >> \"$S/log\"\nexec \"$@\"")
        if let bash = Self.bashPath { try stub("sh", "exec " + bash + " --posix \"$@\"") }
    }

    // MARK: State

    func ctl(_ name: String, _ value: String?) {
        let path = dir + "/ctl/" + name
        if let value {
            try? value.write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func read(_ name: String) -> String {
        ((try? String(contentsOfFile: dir + "/ctl/" + name, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func touch(_ path: String) { FileManager.default.createFile(atPath: path, contents: Data()) }
    func remove(_ path: String) { try? FileManager.default.removeItem(atPath: path) }
    func symlink(_ path: String, to target: String) {
        try? FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
    }

    private func lines(_ name: String) -> [String] {
        ((try? String(contentsOfFile: dir + "/" + name, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    var log: [String] { lines("log") }

    /// Each `pmset -a disablesleep` call: the value and the calling shell's pid.
    var sets: [(value: String, parent: Int32?)] {
        lines("sets").map { line in
            let parts = line.split(separator: " ").map(String.init)
            return (parts.first ?? "", parts.count > 1 ? Int32(parts[1]) : nil)
        }
    }

    func waitFor(_ name: String, _ value: String, seconds: Double = 8) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if read(name) == value { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return read(name) == value
    }

    // MARK: Processes

    private var environment: [String: String] { ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"] }

    /// The interpreter for a command line: /bin/sh, or `bash --posix`.
    private var outer: (path: String, args: [String]) {
        switch shell {
        case .sh: return ("/bin/sh", [])
        case .bashPosix: return (Self.bashPath ?? "/bin/bash", ["--posix"])
        }
    }

    /// `sh -c <script> snaptic-lid <mode> <argv>`, run directly (stdin and output to /dev/null).
    func runScript(mode: String, argv: [String]? = nil) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: outer.path)
        p.arguments = outer.args + ["-c", script, "snaptic-lid", mode] + (argv ?? self.argv)
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        watched.append(p.processIdentifier)
        return p
    }

    /// The generated three-line command, run the way `do shell script` runs it (`/bin/sh -c`), in a subshell whose
    /// status the outer shell writes to a file: on Linux, Foundation learns that a child exited through a socket the
    /// child inherits, so a backgrounded grandchild (the watchdog) would keep the outer shell "running".
    func runCommand(argv: [String]? = nil) throws -> (status: Int32, stdout: String, seconds: Double) {
        let command = LidWatchdog.command(argv: argv ?? self.argv, script: script, tools: commandTools)
        let id = UUID().uuidString
        let out = dir + "/stdout-" + id, status = dir + "/status-" + id
        let line = "(\n" + command + "\n) >" + LidWatchdog.quoted(out) + " 2>/dev/null </dev/null; echo $? >"
            + LidWatchdog.quoted(status + ".tmp") + " && mv " + LidWatchdog.quoted(status + ".tmp") + " "
            + LidWatchdog.quoted(status)
        let start = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: outer.path)
        p.arguments = outer.args + ["-c", line]
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        watched.append(p.processIdentifier)
        let end = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: status) && Date() < end { Thread.sleep(forTimeInterval: 0.02) }
        let seconds = Date().timeIntervalSince(start)
        let code = (try? String(contentsOfFile: status, encoding: .utf8))
            .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? -1
        let stdout = (try? String(contentsOfFile: out, encoding: .utf8)) ?? ""
        return (code, stdout, seconds)
    }

    /// stdout goes to a file, not a pipe: where spawned children inherit every open descriptor (Linux), the
    /// backgrounded watchdog would hold a pipe's write end and EOF would never come.
    func runOuter(_ line: String) throws -> (status: Int32, stdoutData: Data) {
        let path = dir + "/stdout-" + UUID().uuidString
        FileManager.default.createFile(atPath: path, contents: Data())
        let out = try XCTUnwrap(FileHandle(forWritingAtPath: path))
        defer { try? out.close() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: outer.path)
        p.arguments = outer.args + ["-c", line]
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        watched.append(p.processIdentifier)
        let status = waitExit(p, seconds: 30) ?? -1
        return (status, FileManager.default.contents(atPath: path) ?? Data())
    }

    func watch(_ pid: Int32) { watched.append(pid) }

    /// The exit status, or nil after `seconds`.
    func waitExit(_ p: Process, seconds: Double) -> Int32? {
        let end = Date().addingTimeInterval(seconds)
        while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.02) }
        if p.isRunning { return nil }
        p.waitUntilExit()
        return p.terminationStatus
    }

    func waitGone(_ pid: Int32, seconds: Double = 10) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if Self.isGone(pid) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return Self.isGone(pid)
    }

    /// Exited: no such process, or (in a container whose init doesn't reap orphans) a zombie.
    static func isGone(_ pid: Int32) -> Bool {
        if kill(pid, 0) != 0 { return true }
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
              let close = stat.range(of: ")", options: .backwards) else { return false }
        return stat[close.upperBound...].trimmingCharacters(in: .whitespaces).hasPrefix("Z")
    }

    /// Kills whatever this environment started and is still running, then removes the directory.
    func cleanup() {
        guard !cleaned else { return }
        cleaned = true
        // The shells this environment started, the watchdogs they ran (their 0.2 s sleeps end on their own) and any
        // beacon lookup a stub keeps hanging.
        let pids = watched + sets.compactMap(\.parent) + lines("hung").compactMap { Int32($0) }
        for pid in Set(pids) where pid > 1 && pid != getpid() && !Self.isGone(pid) { kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(atPath: dir)
    }
}

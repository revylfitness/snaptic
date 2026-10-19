import Foundation
import XCTest
@testable import SnapticKit

// LidWatchdog (owner: T-lid-kit; PLAN 0.3.1 B3.2, B5): the golden script, quoting and escaping round trips, the
// command's shape, validation fuzz, result parsing and prompts. The script's behaviour under real shells is in
// LidWatchdogShellTests.

final class LidWatchdogTests: XCTestCase {
    private let token = "0123456789abcdef0123456789abcdef"
    private let dir = "/var/folders/zz/abc_d+e-f.g/T/snaptic-lid"

    private func args(uid: UInt32 = 501, pid: Int32 = 4_242, token: String? = nil, cap: Int = LidWatchdog.capSeconds,
                      floor: Int = 20, dir: String? = nil) -> LidWatchdog.Arguments? {
        LidWatchdog.Arguments.validated(uid: uid, pid: pid, token: token ?? self.token, capSeconds: cap, floor: floor,
                                        dir: dir ?? self.dir)
    }

    // MARK: The script

    /// The exact B3.2 text (a second copy, so any edit to the source shows up here).
    static let golden = #"""
unset IFS; PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
umask 077; trap '' HUP
MODE=$1; U=$2; P=$3; T=$4; C=$5; F=$6; D=$7
case "$MODE" in check|run) ;; *) exit 64;; esac
num() { case "$1" in ''|*[!0-9]*) return 1;; esac; }
num "$U" && num "$P" && num "$C" && num "$F" || exit 64
case "$T" in *[!0-9a-f]*|'') exit 64;; esac; [ ${#T} -eq 32 ] || exit 64
case "$D" in /var/folders/*/snaptic-lid) ;; *) exit 64;; esac
case "$D" in *..*|*[!A-Za-z0-9_/+.-]*) exit 64;; esac
[ "$F" -ge 10 ] && [ "$F" -le 50 ] && [ "$C" -ge 3600 ] && [ "$C" -le 86400 ] || exit 64
C=$((C+60))
# Stored preference: the "System-wide power settings:" block only, first match; 1, 0 (absent) or ? (odd/unreadable)
sd() { O=$(/usr/bin/pmset -g 2>/dev/null) || { echo '?'; return; }
  printf '%s\n' "$O" | /usr/bin/awk '/^System-wide power settings:/{s=1;next} s&&/^[^ \t]/{s=0}
    s&&$1=="SleepDisabled"&&!d{v=$2;d=1} END{if(!d)print 0; else if(v=="0"||v=="1")print v; else print "?"}'; }
rd() { /usr/sbin/ioreg -r -n IOPMrootDomain -d 1 2>/dev/null; }
# Kernel value on IOPMrootDomain: 1, 0 (root domain present, property absent: powerd creates it only once
# SystemPowerSettings exists), or ? (no root domain output at all)
ksd() { rd | /usr/bin/awk '/IOPMrootDomain/{r=1} /"SleepDisabled" = /{f=1; v=($NF=="Yes")?1:0}
                          END{if(f)print v; else if(r)print 0; else print "?"}'; }
key() { rd | /usr/bin/awk -v k="\"$1\" = " 'index($0,k){print $NF; exit}'; }
owned() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(/usr/bin/stat -f %u "$1" 2>/dev/null)" = "$U" ]; }
[ "$(sd)" = 0 ] && [ "$(ksd)" = 0 ] || exit 3      # someone else holds it, or unreadable: never take it
[ "$MODE" = check ] && exit 0
owned "$D/stop-$T" && exit 0                         # stopped before we started (late password)
WESET=0; HALT=0
cleanup() {
  trap '' TERM INT
  [ "$WESET" = 1 ] || return
  i=0; while [ $i -lt 3 ]; do [ "$(sd)" = 0 ] && break
    /usr/bin/pmset -a disablesleep 0; /bin/sleep 1; i=$((i+1)); done
  [ "$HALT" = 1 ] && return                          # shutting down: never sleepnow
  i=0; while [ $i -lt 5 ] && [ "$(ksd)" != 0 ]; do /bin/sleep 1; i=$((i+1)); done   # powerd → kernel
  j=0; while [ $j -lt 3 ]; do
    [ "$(key AppleClamshellState)" = Yes ] || return
    [ "$(key AppleClamshellCausesSleep)" = Yes ] && { /usr/bin/pmset sleepnow; return; }
    /bin/sleep 1; j=$((j+1)); done
}
trap 'cleanup' EXIT; trap 'HALT=1; exit 0' TERM; trap 'exit 0' INT
/usr/bin/pmset -a disablesleep 1; WESET=1
i=0; until [ "$(sd)" = 1 ] && [ "$(ksd)" = 1 ]; do       # post-set check, up to 3 s
  i=$((i+1)); [ $i -ge 6 ] && exit 0; /bin/sleep 0.5; done
START=$(/bin/date +%s); Z=0; Q=0; LB=0
while :; do
  /bin/sleep 5 & wait $!                               # traps run without waiting out the sleep
  N=$(/bin/date +%s); num "$N" || exit 0
  [ $((N-START)) -ge "$C" ] && exit 0                  # hard cap
  /bin/kill -0 "$P" 2>/dev/null || exit 0              # liveness hint only (any pid answers root)
  owned "$D/stop-$T" && exit 0                         # asked to stop
  owned "$D/beat-$T" || exit 0                         # beacon gone
  M=$(/usr/bin/stat -f %m "$D/beat-$T" 2>/dev/null); num "$M" || exit 0
  [ $((N-M)) -le 20 ] || exit 0                        # Snaptic hung: the beacon is the real bound
  S=$(sd); K=$(ksd)
  if [ "$S" = 1 ] && [ "$K" = 1 ]; then Z=0; Q=0
  elif [ "$S" = 0 ] && [ "$K" = 0 ]; then Z=$((Z+1)); [ $Z -ge 2 ] && { WESET=0; exit 0; }   # reset by someone else, both sources, twice: not ours
  else Q=$((Q+1)); [ $Q -ge 2 ] && exit 0; fi           # disagreement or unreadable: restore
  B=$(/usr/bin/pmset -g batt 2>/dev/null)
  case "$B" in *discharging*)
    PC=$(printf '%s' "$B" | /usr/bin/sed -n 's/.*[^0-9]\([0-9][0-9]*\)%.*/\1/p' | /usr/bin/awk 'NR==1')
    if num "$PC"; then LB=0; [ "$PC" -le "$F" ] && exit 0
    else LB=$((LB+1)); [ $LB -ge 2 ] && exit 0; fi;; esac
  TP=$(/usr/bin/notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null | /usr/bin/awk '{print $2}')
  num "$TP" && [ "$TP" -ge 2 ] && exit 0               # heavy or worse (= ProcessInfo .serious)
done
"""#

    func testScriptIsTheGoldenText() {
        XCTAssertEqual(LidWatchdog.defaultScript, Self.golden)
        XCTAssertEqual(LidWatchdog.script(), Self.golden, "the defaults change nothing")
        XCTAssertEqual(LidWatchdog.script(tools: LidWatchdog.defaultTools, period: 5, stale: 20), Self.golden)
    }

    /// The script is exactly the plan's B3.2 block (when the docs are checked out next to the tests).
    func testScriptIsThePlansText() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let plan = root.appendingPathComponent("docs/design/0.3.1/PLAN.md").path
        guard let text = try? String(contentsOfFile: plan, encoding: .utf8) else { return }
        let marker = try XCTUnwrap(text.range(of: "**Script.**"))
        let open = try XCTUnwrap(text.range(of: "```sh\n", range: marker.upperBound..<text.endIndex))
        let close = try XCTUnwrap(text.range(of: "\n```", range: open.upperBound..<text.endIndex))
        XCTAssertEqual(String(text[open.upperBound..<close.lowerBound]), LidWatchdog.defaultScript)
    }

    /// LF is the only byte below 0x20 (no tab can reach `IFS`, NM1), and there is no DEL.
    func testScriptHasNoControlBytesButLF() {
        for s in [LidWatchdog.defaultScript, LidWatchdog.script(tools: stubTools, period: 0.2, stale: 20)] {
            XCTAssertTrue(s.utf8.allSatisfy { ($0 >= 0x20 && $0 != 0x7F) || $0 == 0x0A })
        }
        XCTAssertTrue(LidWatchdog.defaultScript.contains("\n"))
    }

    /// Every absolute path the script runs is in the tool table, and every tool is used; the script resets IFS and
    /// PATH first and writes only through pmset.
    func testToolTableIsComplete() throws {
        let s = LidWatchdog.defaultScript
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_./+-])/(?:usr/)?s?bin/[a-z]+"#)
        let found = Set(regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
            Range($0.range, in: s).map { String(s[$0]) }
        })
        XCTAssertEqual(found, Set(LidWatchdog.toolPaths))
        XCTAssertEqual(Set(LidWatchdog.defaultTools.keys), Set(LidWatchdog.toolPaths))
        XCTAssertTrue(s.hasPrefix("unset IFS; PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH\n"))
        let writes = s.components(separatedBy: "/usr/bin/pmset ").dropFirst().map { $0.prefix(16) }
        for w in writes {
            XCTAssertTrue(w.hasPrefix("-g") || w.hasPrefix("-a disablesleep ") || w.hasPrefix("sleepnow"), String(w))
        }
        for word in ["rm ", "mv ", "> \"$D", ">\"$D", "cat ", "chmod", "chown", "ln ", "eval", ". \"", "source "] {
            XCTAssertFalse(s.contains(word), word)
        }
    }

    private var stubTools: [String: String] {
        Dictionary(uniqueKeysWithValues: LidWatchdog.toolPaths.map { ($0, "/tmp/stub" + $0) })
    }

    func testScriptVariants() {
        let s = LidWatchdog.script(tools: stubTools, period: 0.2, stale: 7)
        XCTAssertTrue(s.contains("/tmp/stub/bin/sleep 0.2 & wait $!"))
        XCTAssertTrue(s.contains("[ $((N-M)) -le 7 ]"))
        for path in LidWatchdog.toolPaths {
            XCTAssertTrue(s.contains("/tmp/stub" + path), path)
            // Every use was replaced: what is left of the default path is only inside the stub's own path.
            XCTAssertEqual(s.components(separatedBy: path).count, s.components(separatedBy: "/tmp/stub" + path).count,
                           path)
        }
        XCTAssertEqual(s.components(separatedBy: "\n").count, Self.golden.components(separatedBy: "\n").count)
        // Each anchor occurs once.
        for anchor in [LidWatchdog.periodAnchor, LidWatchdog.staleAnchor, LidWatchdog.rootAnchor] {
            XCTAssertEqual(Self.golden.components(separatedBy: anchor).count, 2, anchor)
        }
        // Refused overrides keep the defaults.
        let bad = ["/usr/bin/pmset": "pmset", "/bin/date": "/tmp/a b", "/bin/kill": "/tmp/../kill", "/bin/sleep": "/x;y"]
        XCTAssertEqual(LidWatchdog.script(tools: bad, period: .nan, stale: 0), Self.golden)
        XCTAssertEqual(LidWatchdog.script(tools: [:], period: 61, stale: 3_601), Self.golden)
        XCTAssertEqual(LidWatchdog.periodText(0.2), "0.2")
        XCTAssertEqual(LidWatchdog.periodText(10), "10")
        XCTAssertEqual(LidWatchdog.periodText(0.05), "5")
        XCTAssertEqual(LidWatchdog.periodText(-1), "5")
        XCTAssertEqual(LidWatchdog.periodText(.infinity), "5")
        XCTAssertTrue(LidWatchdog.script(tools: [:], period: 5, stale: 20, tempRoot: "/tmp/x")
            .contains(#"case "$D" in /tmp/x/*/snaptic-lid)"#))
        XCTAssertEqual(LidWatchdog.script(tools: [:], period: 5, stale: 20, tempRoot: "/tmp/x*"), Self.golden)
        XCTAssertEqual(LidWatchdog.script(tools: [:], period: 5, stale: 20, tempRoot: "/tmp/x/"), Self.golden)
    }

    // MARK: Arguments

    func testArgumentsValidation() {
        XCTAssertEqual(args()?.argv, ["501", "4242", token, "86400", "20", dir])
        XCTAssertNotNil(args(uid: 0))
        XCTAssertNotNil(args(uid: .max))
        XCTAssertNil(args(pid: 0))
        XCTAssertNil(args(pid: 1), "kill -0 1 answers for launchd")
        XCTAssertNotNil(args(pid: 2))
        XCTAssertNotNil(args(pid: 99_999))
        XCTAssertNil(args(pid: 100_000))
        XCTAssertNil(args(pid: -5))
        XCTAssertNil(args(token: ""))
        XCTAssertNil(args(token: String(token.dropLast())))
        XCTAssertNil(args(token: token + "0"))
        XCTAssertNil(args(token: token.uppercased()))
        XCTAssertNil(args(token: "g" + token.dropFirst()))
        XCTAssertNil(args(token: "'" + token.dropFirst()))
        XCTAssertNotNil(args(cap: 3_600))
        XCTAssertNil(args(cap: 3_599))
        XCTAssertNil(args(cap: 86_401))
        XCTAssertNil(args(cap: -86_400))
        XCTAssertNotNil(args(floor: 10))
        XCTAssertNotNil(args(floor: 50))
        XCTAssertNil(args(floor: 9))
        XCTAssertNil(args(floor: 51))
        XCTAssertNotNil(args(dir: "/var/folders//snaptic-lid"), "the script's `*` matches nothing too")
        XCTAssertNotNil(args(dir: "/var/folders/a/snaptic-lid"))
        for bad in ["/var/folders/snaptic-lid", "/var/folders/a/snaptic-lid/", "/var/folders/a/b/snaptic-lidx",
                    "/var/folders/../snaptic-lid", "/var/folders/a/../snaptic-lid", "/var/folders/a b/snaptic-lid",
                    "/var/folders/a'b/snaptic-lid", "/var/folders/a$b/snaptic-lid", "/var/folders/a\nb/snaptic-lid",
                    "/var/folders/a*b/snaptic-lid", "/var/folders/é/snaptic-lid", "/tmp/a/snaptic-lid",
                    "var/folders/a/snaptic-lid", "/private/var/folders/a/snaptic-lid", "",
                    "/var/folders/" + String(repeating: "a", count: 1_000) + "/snaptic-lid"] {
            XCTAssertNil(args(dir: bad), bad)
        }
    }

    func testBeaconDirAndFileNames() {
        XCTAssertEqual(LidWatchdog.beaconDir(userTempDir: "/var/folders/7z/k3r_hy2j0x9fq0+4cdmv0000gn/T/"),
                       "/var/folders/7z/k3r_hy2j0x9fq0+4cdmv0000gn/T/snaptic-lid")
        XCTAssertEqual(LidWatchdog.beaconDir(userTempDir: "/var/folders/ab/cd/T"), "/var/folders/ab/cd/T/snaptic-lid")
        XCTAssertEqual(LidWatchdog.beaconDir(userTempDir: "/var/folders/ab/cd/T//"), "/var/folders/ab/cd/T/snaptic-lid")
        XCTAssertNil(LidWatchdog.beaconDir(userTempDir: "/tmp/"))
        XCTAssertNil(LidWatchdog.beaconDir(userTempDir: "/var/folders/a b/T/"))
        XCTAssertNil(LidWatchdog.beaconDir(userTempDir: ""))
        XCTAssertEqual(LidWatchdog.stopFileName(token: token), "stop-" + token)
        XCTAssertEqual(LidWatchdog.beatFileName(token: token), "beat-" + token)
        XCTAssertNil(LidWatchdog.stopFileName(token: "../x"))
        XCTAssertNil(LidWatchdog.beatFileName(token: ""))
        XCTAssertEqual(LidWatchdog.token(randomBytes: [0x00, 0x01, 0x7f, 0x80, 0xab, 0xff] + Array(repeating: 0x10, count: 10)),
                       "00017f80abff" + String(repeating: "10", count: 10))
        XCTAssertNil(LidWatchdog.token(randomBytes: Array(repeating: 0, count: 15)))
        XCTAssertNil(LidWatchdog.token(randomBytes: Array(repeating: 0, count: 17)))
        var rng = SeededGenerator(seed: 0x11D)
        for _ in 0..<200 {
            let bytes = (0..<16).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            let t = LidWatchdog.token(randomBytes: bytes) ?? ""
            XCTAssertTrue(LidWatchdog.isToken(t), t)
        }
    }

    /// Charset and range fuzz: whatever the inputs, a validated argv is plain and in range, and only what
    /// `validated` accepts ever reaches the command.
    func testArgumentsFuzz() {
        var rng = SeededGenerator(seed: 0x51D)
        let alphabet = Array("abcdefABCDEF0123456789g_/+.-' \"$`\\*?[]~;&|<>()\n\té→")
        func pick(_ n: Int) -> Int { Int(rng.next() % UInt64(max(1, n))) }
        func randomString(_ maxLength: Int) -> String {
            String((0..<pick(maxLength + 1)).map { _ in alphabet[pick(alphabet.count)] })
        }
        var accepted = 0
        for i in 0..<5_000 {
            var token = i % 3 == 2 ? randomString(40) : self.token
            if i % 3 == 1 {
                var chars = Array(token)
                chars[pick(chars.count)] = alphabet[pick(alphabet.count)]
                token = String(chars)
            }
            let dir = i % 2 == 0 ? "/var/folders/" + randomString(12) + "/snaptic-lid" : randomString(40)
            let cap = [3_599, 3_600, 86_400, 86_401, Int(rng.next() % 200_000) - 50_000][pick(5)]
            let floor = [9, 10, 50, 51, Int(rng.next() % 120) - 30][pick(5)]
            let pid = Int32(truncatingIfNeeded: rng.next() % 300_000) - 100_000
            guard let a = LidWatchdog.Arguments.validated(uid: UInt32(truncatingIfNeeded: rng.next()), pid: pid,
                                                          token: token, capSeconds: cap, floor: floor, dir: dir) else {
                continue
            }
            accepted += 1
            XCTAssertTrue(LidWatchdog.isToken(a.token))
            XCTAssertTrue(LidWatchdog.capRange.contains(a.capSeconds) && LidWatchdog.floorRange.contains(a.floor))
            XCTAssertTrue(a.pid > 1 && a.pid < 100_000)
            XCTAssertTrue(a.dir.hasPrefix("/var/folders/") && a.dir.hasSuffix("/snaptic-lid") && !a.dir.contains(".."))
            for v in a.argv {
                XCTAssertTrue(v.utf8.allSatisfy { b in
                    (0x30...0x39).contains(b) || (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b)
                        || [0x2B, 0x2D, 0x2E, 0x2F, 0x5F].contains(b)
                }, v)
            }
        }
        XCTAssertGreaterThan(accepted, 50, "the fuzz reaches valid arguments")
    }

    // MARK: Quoting and the command

    func testQuoting() {
        XCTAssertEqual(LidWatchdog.quoted(""), "''")
        XCTAssertEqual(LidWatchdog.quoted("a b"), "'a b'")
        XCTAssertEqual(LidWatchdog.quoted("it's"), #"'it'\''s'"#)
        XCTAssertEqual(LidWatchdog.quoted("'"), #"''\'''"#)
        var rng = SeededGenerator(seed: 0x0A7)
        let alphabet = Array("a'\"\\$`!*?[]{}()<>|&;~# \n\té→\u{1}") + ["\r\n"]
        for _ in 0..<2_000 {
            let s = String((0..<Int(rng.next() % 24)).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
            XCTAssertEqual(ShellWords.split(LidWatchdog.quoted(s)), [s], s)
        }
    }

    func testCommandShape() throws {
        let a = try XCTUnwrap(args())
        let c = LidWatchdog.command(a)
        let lines = c.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("/bin/sh -c '"))
        XCTAssertTrue(lines[0].hasSuffix(" </dev/null >/dev/null 2>&1 || exit $?"))
        XCTAssertTrue(lines[1].hasPrefix("/usr/bin/nohup /bin/sh -c '"))
        XCTAssertTrue(lines[1].hasSuffix(" </dev/null >/dev/null 2>&1 &"))
        XCTAssertEqual(lines[2], "echo $!")
        XCTAssertEqual(lines.filter { $0.hasSuffix("&") }.count, 1, "only the second line is backgrounded")
        // The quoted words come back exactly: the script, then the mode and the six arguments.
        for (line, mode) in [(lines[0], "check"), (lines[1], "run")] {
            let words = ShellWords.split(line)
            let at = try XCTUnwrap(words.firstIndex(of: "-c"))
            XCTAssertEqual(words[at + 1], LidWatchdog.defaultScript)
            XCTAssertEqual(Array(words[(at + 2)...(at + 3)]), ["snaptic-lid", mode])
            XCTAssertEqual(Array(words[(at + 4)...(at + 9)]), a.argv)
            XCTAssertEqual(words[(at + 10)...].first, "</dev/null")
        }
    }

    // MARK: AppleScript

    func testAppleScriptEscaping() {
        XCTAssertEqual(LidWatchdog.appleScriptString(#"a\b"c"#), #"a\\b\"c"#)
        XCTAssertEqual(LidWatchdog.appleScriptString("a\nb"), #"a\nb"#)
        XCTAssertEqual(LidWatchdog.appleScriptString("it’s → 20%"), "it’s → 20%")
        for refused in ["a\tb", "a\rb", "\u{0}", "\u{1B}[0m", "\u{7F}", "\u{85}", "\u{2028}", "\u{2029}", "\u{202E}",
                        "\u{200B}", "\u{E000}", "\u{FEFF}"] {
            XCTAssertNil(LidWatchdog.appleScriptString(refused), refused.unicodeScalars.map { String($0.value, radix: 16) }.joined())
            XCTAssertNil(LidWatchdog.appleScript(command: "x" + refused, prompt: "p"))
            XCTAssertNil(LidWatchdog.appleScript(command: "x", prompt: "p" + refused))
        }
        XCTAssertNil(LidWatchdog.appleScript(command: "x", prompt: ""))
        var rng = SeededGenerator(seed: 0xA5)
        let alphabet = Array("ab\\\"\n'$`→ é")
        for _ in 0..<2_000 {
            let s = String((0..<Int(rng.next() % 30)).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
            let e = LidWatchdog.appleScriptString(s) ?? "<nil>"
            XCTAssertFalse(e.contains("\n"))
            XCTAssertEqual(AppleScriptText.unescape(e), s)
        }
    }

    /// B5: shell-unquote(AppleScript-unescape(x)) gives back the argv, through the whole start script.
    func testStartScriptRoundTrip() throws {
        let a = try XCTUnwrap(args())
        let prompt = LidWatchdog.promptText(floor: a.floor)
        let script = try XCTUnwrap(LidWatchdog.startScript(a, prompt: prompt)).source
        let lines = script.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 6)
        XCTAssertEqual(lines[0], "try")
        XCTAssertEqual(lines[2], #"return "ok " & r"#)
        XCTAssertEqual(Array(lines[3...]), ["on error number n", #"return "err " & n"#, "end try"])
        let call = lines[1]
        XCTAssertTrue(call.hasPrefix(#"set r to do shell script ""#))
        XCTAssertTrue(call.hasSuffix(#"" with administrator privileges"#))
        let literals = AppleScriptText.stringLiterals(call)
        XCTAssertEqual(literals.count, 2)
        let command = AppleScriptText.unescape(literals[0])
        XCTAssertEqual(command, LidWatchdog.command(a))
        XCTAssertEqual(AppleScriptText.unescape(literals[1]), prompt)
        let first = ShellWords.split(command.components(separatedBy: "\n")[0])
        XCTAssertEqual(Array(first[5...10]), a.argv)
        XCTAssertEqual(first[2], LidWatchdog.defaultScript)
        XCTAssertTrue(script.utf8.allSatisfy { $0 >= 0x20 || $0 == 0x0A })
    }

    func testRestoreScriptIsFixed() throws {
        let script = try XCTUnwrap(LidWatchdog.restoreScript(prompt: LidWatchdog.restorePromptText)).source
        let lines = script.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 6)
        XCTAssertEqual(lines[2], #"return "ok""#)
        let literals = AppleScriptText.stringLiterals(lines[1])
        XCTAssertEqual(AppleScriptText.unescape(literals[0]), "/usr/bin/pmset -a disablesleep 0 </dev/null >/dev/null 2>&1")
        XCTAssertEqual(AppleScriptText.unescape(literals[1]), LidWatchdog.restorePromptText)
        XCTAssertNil(LidWatchdog.restoreScript(prompt: "a\u{1}"))
        XCTAssertEqual(LidWatchdog.displaySleepArgv.argv, ["/usr/bin/pmset", "displaysleepnow"])
        XCTAssertEqual(LidWatchdog.osascriptPath, "/usr/bin/osascript")
        XCTAssertEqual(LidWatchdog.osascriptRequirement, #"anchor apple and identifier "com.apple.osascript""#)
        XCTAssertEqual(LidWatchdog.toolRequirement, "anchor apple")
        XCTAssertEqual(LidWatchdog.capSeconds, 86_400)
    }

    // MARK: Results

    func testParseResult() {
        let table: [(String, LidWatchdog.Outcome)] = [
            ("ok 4242", .launched(pid: 4_242)), ("ok 4242\n", .launched(pid: 4_242)), ("ok 2", .launched(pid: 2)),
            ("ok 99999", .launched(pid: 99_999)), ("ok 1", .failed(-1)), ("ok 0", .failed(-1)),
            ("ok 100000", .failed(-1)), ("ok -5", .failed(-1)), ("ok ", .failed(-1)), ("ok", .failed(-1)),
            ("ok 12 ", .failed(-1)), (" ok 12", .failed(-1)), ("ok 12\n\n", .failed(-1)), ("ok 12\r\n", .failed(-1)),
            ("ok 1a", .failed(-1)), ("ok ٣٤", .failed(-1)), ("ok 99999999999", .failed(-1)), ("OK 12", .failed(-1)),
            ("err -128", .canceled), ("err -128\n", .canceled), ("err 3", .failed(3)), ("err 64", .failed(64)),
            ("err -60005", .failed(-60_005)), ("err 0", .failed(0)), ("err", .failed(-1)), ("err ", .failed(-1)),
            ("err --1", .failed(-1)), ("err 1x", .failed(-1)), ("err 99999999999", .failed(-1)),
            ("err 2147483648", .failed(-1)), ("err -2147483648", .failed(Int32.min)), ("", .failed(-1)),
            ("\n", .failed(-1)), ("ok 12\nok 13", .failed(-1)), ("ok\t12", .failed(-1)), ("garbage", .failed(-1)),
        ]
        for (text, outcome) in table {
            XCTAssertEqual(LidWatchdog.parseResult(text), outcome, text.debugDescription)
        }
        XCTAssertEqual(LidWatchdog.parseResult(String(repeating: "1", count: 100)), .failed(-1))
        XCTAssertEqual(LidWatchdog.parseRestoreResult("ok"), .restored)
        XCTAssertEqual(LidWatchdog.parseRestoreResult("ok\n"), .restored)
        XCTAssertEqual(LidWatchdog.parseRestoreResult("ok 12"), .failed(-1))
        XCTAssertEqual(LidWatchdog.parseRestoreResult("err -128"), .canceled)
        XCTAssertEqual(LidWatchdog.parseRestoreResult("err 1"), .failed(1))
        XCTAssertEqual(LidWatchdog.parseRestoreResult(""), .failed(-1))
        // Never traps on any input.
        var rng = SeededGenerator(seed: 0xBAD)
        let alphabet = Array("ok err-0123456789\n\r\t é")
        for _ in 0..<3_000 {
            let s = String((0..<Int(rng.next() % 20)).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
            if case .launched(let pid) = LidWatchdog.parseResult(s) { XCTAssertTrue(pid > 1 && pid < 100_000) }
            _ = LidWatchdog.parseRestoreResult(s)
        }
    }

    // MARK: Prompts

    func testPrompts() {
        XCTAssertEqual(LidWatchdog.promptText(floor: 20),
                       "Snaptic wants to keep your Mac awake with the lid closed for up to 24 hours. Sleep turns back on when the session ends, when Snaptic quits, at 20% battery, or if your Mac gets hot. Enter an administrator password to allow this.")
        XCTAssertTrue(LidWatchdog.promptText(floor: 35).contains(" at 35% battery,"))
        XCTAssertTrue(LidWatchdog.promptText(floor: 3).contains(" at 10% battery,"), "clamped to the script's range")
        XCTAssertTrue(LidWatchdog.promptText(floor: 90).contains(" at 50% battery,"))
        XCTAssertEqual(LidWatchdog.restorePromptText,
                       "Snaptic wants to turn sleep back on. It may have been left off by an earlier lid-closed session. Enter an administrator password to allow this.")
        for floor in 10...50 {
            XCTAssertNotNil(LidWatchdog.appleScriptString(LidWatchdog.promptText(floor: floor)))
        }
    }
}

/// A POSIX shell word splitter for what `quoted` and `command` produce: single quotes, backslash escapes outside
/// them, blanks between words (no expansions).
enum ShellWords {
    static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quoted = false
        var escaped = false
        for c in line {
            if escaped {
                current.append(c)
                escaped = false
            } else if quoted {
                if c == "'" { quoted = false } else { current.append(c) }
            } else if c == "'" {
                quoted = true
                inWord = true
            } else if c == "\\" {
                escaped = true
                inWord = true
            } else if c == " " || c == "\t" {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(c)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}

/// AppleScript string literals, read back.
enum AppleScriptText {
    /// `\\` → `\`, `\"` → `"`, `\n` → LF.
    static func unescape(_ s: String) -> String {
        var out = ""
        var escaped = false
        for c in s {
            if escaped {
                switch c {
                case "n": out.append("\n")
                default: out.append(c)
                }
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    /// The raw (still escaped) contents of each `"…"` literal in one line.
    static func stringLiterals(_ line: String) -> [String] {
        var out: [String] = []
        var current: String?
        var escaped = false
        for c in line {
            if var cur = current {
                if escaped {
                    cur.append(c)
                    escaped = false
                    current = cur
                } else if c == "\\" {
                    cur.append(c)
                    escaped = true
                    current = cur
                } else if c == "\"" {
                    out.append(cur)
                    current = nil
                } else {
                    cur.append(c)
                    current = cur
                }
            } else if c == "\"" {
                current = ""
            }
        }
        return out
    }
}

import Foundation

// Lid-closed mode's root side and its prompts (owner: T-lid-kit; PLAN 0.3.1 B3.2, B5, B6). The only file in Sources/
// that may spell the root command's words, and the only one that can make an `AdminScript` or a `ToolCommand` (lint
// L18). Nothing here reads user text: the script is a fixed literal, every argument is validated by the same rules
// the script applies (stricter where Swift can be), and each layer is quoted for the next one (POSIX single quotes
// for the shell, then AppleScript string escapes), so no byte of any argument is ever interpreted as code.

/// An AppleScript source for `osascript -e`. Only this file can make one (`fileprivate` init), so the spawner can't be
/// handed anything but the fixed watchdog and restore scripts.
package struct AdminScript: Equatable, Sendable {
    package let source: String

    fileprivate init(source: String) { self.source = source }
}

/// A fixed user-level command (`pmset displaysleepnow`). Only this file can make one.
package struct ToolCommand: Equatable, Sendable {
    /// argv[0] is the absolute path.
    package let argv: [String]

    fileprivate init(argv: [String]) { self.argv = argv }
}

package enum LidWatchdog {
    package static let osascriptPath = "/usr/bin/osascript"
    /// The spawned osascript must satisfy this before SIGCONT (B3.1 step 4).
    package static let osascriptRequirement = #"anchor apple and identifier "com.apple.osascript""#
    /// `spawnTool`'s children must satisfy this before SIGCONT (B3.3).
    package static let toolRequirement = "anchor apple"
    /// The fixed time limit (B1): 24 hours. The script adds 60 s to its own cap.
    package static let capSeconds = 86_400
    /// Display sleep as the user while the lid is shut (B3.3); needs no root.
    package static let displaySleepArgv = ToolCommand(argv: ["/usr/bin/pmset", "displaysleepnow"])

    /// The script's own limits (B3.2): the cap it accepts and the battery floor.
    package static let capRange = 3_600...86_400
    package static let floorRange = 10...50
    /// The beacon directory's last component and the root the script accepts it under (B3.1 step 3, B3.2).
    package static let beaconDirName = "snaptic-lid"
    package static let defaultTempRoot = "/var/folders"

    /// What osascript printed (B3.1 step 5).
    package enum Outcome: Equatable, Sendable {
        /// `ok <pid>`: the watchdog's pid (1 < pid < 100 000).
        case launched(pid: Int32)
        /// `err -128`: the user clicked Cancel.
        case canceled
        /// `err <n>`, or -1 for anything else.
        case failed(Int32)
    }

    /// What osascript printed for Turn Sleep Back On… (B3.4).
    package enum RestoreOutcome: Equatable, Sendable {
        /// `ok`: `pmset` exited 0.
        case restored
        /// `err -128`: the user clicked Cancel.
        case canceled
        /// `err <n>`, or -1 for anything else.
        case failed(Int32)
    }

    /// `uid pid token capSeconds floor dir`, valid by the script's own rules (B3.2).
    package struct Arguments: Equatable, Sendable {
        package let uid: UInt32
        package let pid: Int32
        /// 32 lowercase hex characters.
        package let token: String
        /// 3 600–86 400.
        package let capSeconds: Int
        /// 10–50.
        package let floor: Int
        /// `<confstr(_CS_DARWIN_USER_TEMP_DIR) without its trailing />/snaptic-lid`.
        package let dir: String

        fileprivate init(uid: UInt32, pid: Int32, token: String, capSeconds: Int, floor: Int, dir: String) {
            self.uid = uid
            self.pid = pid
            self.token = token
            self.capSeconds = capSeconds
            self.floor = floor
            self.dir = dir
        }

        /// nil when any value breaks the script's rules. Stricter than the script where that costs nothing: the pid
        /// must be a real process's (1 < pid < 100 000; `kill -0 0` would answer for the whole process group) and
        /// the directory at most 1 024 bytes.
        package static func validated(uid: UInt32, pid: Int32, token: String, capSeconds: Int, floor: Int,
                                      dir: String) -> Arguments? {
            validated(uid: uid, pid: pid, token: token, capSeconds: capSeconds, floor: floor, dir: dir,
                      tempRoot: LidWatchdog.defaultTempRoot)
        }

        /// The shell test's variant: the directory under `tempRoot` instead of /var/folders.
        static func validated(uid: UInt32, pid: Int32, token: String, capSeconds: Int, floor: Int, dir: String,
                              tempRoot: String) -> Arguments? {
            guard pid > 1, pid < 100_000, LidWatchdog.isToken(token), LidWatchdog.capRange.contains(capSeconds),
                  LidWatchdog.floorRange.contains(floor), LidWatchdog.isBeaconDir(dir, tempRoot: tempRoot) else {
                return nil
            }
            return Arguments(uid: uid, pid: pid, token: token, capSeconds: capSeconds, floor: floor, dir: dir)
        }

        /// `$2 … $7` of the script, in order.
        package var argv: [String] { [String(uid), String(pid), token, String(capSeconds), String(floor), dir] }
    }

    // MARK: - The script (B3.2)

    /// Every absolute tool path the script uses (tested against the script's text).
    package static let toolPaths = ["/bin/date", "/bin/kill", "/bin/sleep", "/usr/bin/awk", "/usr/bin/notifyutil",
                                    "/usr/bin/pmset", "/usr/bin/sed", "/usr/bin/stat", "/usr/sbin/ioreg"]
    /// The shell that runs the script, and `nohup` (the command's own tools, B3.2).
    package static let shellPath = "/bin/sh"
    package static let nohupPath = "/usr/bin/nohup"

    /// Tool path → the path to run instead (the shell test swaps in stubs); by default each path is itself.
    package static let defaultTools: [String: String] = Dictionary(uniqueKeysWithValues: toolPaths.map { ($0, $0) })
    package static let defaultCommandTools: [String: String] = [shellPath: shellPath, nohupPath: nohupPath]

    /// The root watchdog, exactly as PLAN 0.3.1 B3.2 states it (golden-tested). A raw literal, so `\(` and `\1` stay
    /// literal; LF is its only control byte (tested). Its only writes are `pmset -a disablesleep 0|1` and
    /// `pmset sleepnow`; it never writes, deletes, follows or reads user files: it enters `D` once and only `lstat`s
    /// names in it, from a child each lap, so a stalled lookup can't hold up its own limits (r1 S3).
    package static let defaultScript = #"""
unset IFS; PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
umask 077; trap '' HUP INT QUIT TSTP TTIN TTOU      # as started (& ignores INT, QUIT): no terminal ends or stops it
MODE=$1; U=$2; P=$3; T=$4; C=$5; F=$6; D=$7
case "$MODE" in check|run) ;; *) exit 64;; esac
num() { case "$1" in ''|*[!0-9]*) return 1;; esac; }
num "$U" && num "$P" && num "$C" && num "$F" || exit 64
case "$T" in *[!0-9a-f]*|'') exit 64;; esac; [ ${#T} -eq 32 ] || exit 64
case "$D" in /var/folders/*/snaptic-lid) ;; *) exit 64;; esac
case "$D" in *..*|*[!A-Za-z0-9_/+.-]*) exit 64;; esac
[ "$F" -ge 10 ] && [ "$F" -le 50 ] && [ "$C" -ge 3600 ] && [ "$C" -le 86400 ] || exit 64
C=$((C+60))
[ "$MODE" = run ] && A=$(/bin/date +%s)          # the 5 s start limit counts from here (r3 S3-1)
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
# A regular file owned by U; stat without -L reads the name itself (lstat), so no link is followed
owned() { [ "$(/usr/bin/stat -f '%HT %u' "$1" 2>/dev/null)" = "Regular File $U" ]; }
[ "$(sd)" = 0 ] && [ "$(ksd)" = 0 ] || exit 3      # someone else holds it, or unreadable: never take it
[ "$MODE" = check ] && exit 0
# D, entered once: U's own 0700 directory on the volume of /var/folders (no network or user mount). Every later
# lookup is one name inside it, so replacing D or a parent of it can't redirect one
V=$(/usr/bin/stat -f %d /var/folders) && cd -P "$D" &&
  [ "$(/usr/bin/stat -f '%HT %u %Lp %d' .)" = "Directory $U 700 $V" ] || exit 0
owned "stop-$T" && exit 0                            # stopped before we started (late password)
# Over 5 s to get here (a stalled lookup): Snaptic's 10 s verify has given up and may have dropped its journal
N=$(/bin/date +%s); num "$A" && num "$N" && [ $((N-A)) -le 5 ] || exit 0
WESET=0; HALT=0
cleanup() {
  trap '' TERM
  [ "$WESET" = 1 ] || return
  i=0; while [ $i -lt 3 ]; do [ "$(sd)" = 0 ] && break
    /usr/bin/pmset -a disablesleep 0; /bin/sleep 1; i=$((i+1)); done
  { [ "$HALT" = 1 ] || owned "halt-$T"; } && return  # shutting down (TERM, or Snaptic saw it first): never sleepnow
  i=0; while [ $i -lt 5 ] && [ "$(ksd)" != 0 ]; do /bin/sleep 1; i=$((i+1)); done   # powerd → kernel
  j=0; while [ $j -lt 3 ]; do
    [ "$(key AppleClamshellState)" = Yes ] || return
    [ "$(key AppleClamshellCausesSleep)" = Yes ] && { /usr/bin/pmset sleepnow; return; }
    /bin/sleep 1; j=$((j+1)); done
}
trap 'cleanup' EXIT; trap 'HALT=1; exit 0' TERM
WESET=1; /usr/bin/pmset -a disablesleep 1          # WESET first: a TERM during the set still restores
i=0; until [ "$(sd)" = 1 ] && [ "$(ksd)" = 1 ]; do       # post-set check, up to 3 s
  i=$((i+1)); [ $i -ge 6 ] && exit 0; /bin/sleep 0.5; done
# The beacon, read in a child each lap: a lookup that stalls holds the child, never the cap, battery or heat checks
beacon() { owned "stop-$T" && return 1                  # asked to stop
  owned "beat-$T" || return 1                           # beacon gone
  M=$(/usr/bin/stat -f %m "beat-$T" 2>/dev/null); num "$M" || return 1
  [ $((N-M)) -le 20 ]; }                                # Snaptic hung: the beacon is the real bound
START=$(/bin/date +%s); Z=0; Q=0; LB=0; H=0
while :; do
  /bin/sleep 5 & wait $!                               # traps run without waiting out the sleep
  N=$(/bin/date +%s); num "$N" || exit 0
  [ $((N-START)) -ge "$C" ] && exit 0                  # hard cap
  /bin/kill -0 "$P" 2>/dev/null || exit 0              # liveness hint only (any pid answers root)
  beacon & W=$!
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
  if num "$TP"; then H=0; [ "$TP" -ge 2 ] && exit 0    # heavy or worse (= ProcessInfo .serious)
  else H=$((H+1)); [ $H -ge 2 ] && exit 0; fi          # unreadable twice: restore
  # Still reading 5 s later (a stalled lookup): as if gone. The shell's own kill, for its own child; foreground
  # sleeps keep it $!, so the shell keeps its status, and wait runs only once it has exited, so it returns at once
  i=0; while kill -0 "$W" 2>/dev/null; do i=$((i+1)); [ $i -ge 10 ] && exit 0; /bin/sleep 0.5; done
  wait "$W" || exit 0                                  # asked to stop, beacon gone or stale
done
"""#

    /// The pieces `script(tools:period:stale:)` may change; each occurs exactly once in `defaultScript` (tested).
    static let periodAnchor = "/bin/sleep 5 & wait $!"
    static let staleAnchor = "[ $((N-M)) -le 20 ]"
    static let rootAnchor = #"case "$D" in /var/folders/*/snaptic-lid)"#

    /// The script with its tools, loop period (s) and beacon staleness limit (s) replaced: the shell test runs it
    /// with stubs and a 0.2 s period. The defaults give `defaultScript` itself. A tool path that isn't absolute and
    /// plain (`[A-Za-z0-9_./+-]`, no `..`) is ignored, as are a period outside 0.1–60 s and a limit outside 1–3 600 s.
    package static func script(tools: [String: String] = defaultTools, period: Double = 5, stale: Int = 20) -> String {
        script(tools: tools, period: period, stale: stale, tempRoot: defaultTempRoot)
    }

    /// The shell test's variant: the beacon directory under `tempRoot` instead of /var/folders.
    static func script(tools: [String: String], period: Double, stale: Int, tempRoot: String) -> String {
        var s = defaultScript
        let limit = (1...3_600).contains(stale) ? stale : 20
        let root = isSafePath(tempRoot) && !tempRoot.hasSuffix("/") ? tempRoot : defaultTempRoot
        s = s.replacingOccurrences(of: periodAnchor, with: "/bin/sleep " + periodText(period) + " & wait $!")
        s = s.replacingOccurrences(of: staleAnchor, with: "[ $((N-M)) -le " + String(limit) + " ]")
        s = s.replacingOccurrences(of: rootAnchor, with: #"case "$D" in "# + root + "/*/snaptic-lid)")
        return replacingPaths(tools, in: s)
    }

    /// "5", "0.2": tenths of a second, 0.1–60; anything else is the default 5.
    static func periodText(_ period: Double) -> String {
        guard period.isFinite, period >= 0.1, period <= 60 else { return "5" }
        let tenths = Int((period * 10).rounded())
        return tenths % 10 == 0 ? String(tenths / 10) : String(tenths / 10) + "." + String(tenths % 10)
    }

    /// Each tool path, where it stands as a whole word (not inside a longer path), becomes its replacement. Two
    /// passes through placeholders (U+0001 can't occur in the script), so a replacement is never replaced again.
    private static func replacingPaths(_ tools: [String: String], in text: String) -> String {
        var s = text
        var placed: [(placeholder: String, path: String)] = []
        for (i, old) in toolPaths.enumerated() {
            guard let new = tools[old], new != old, isSafePath(new) else { continue }
            let placeholder = "\u{1}" + String(i) + "\u{1}"
            s = replacingWord(old, with: placeholder, in: s)
            placed.append((placeholder, new))
        }
        for p in placed { s = s.replacingOccurrences(of: p.placeholder, with: p.path) }
        return s
    }

    private static func replacingWord(_ word: String, with new: String, in text: String) -> String {
        var out = ""
        var i = text.startIndex
        while let r = text.range(of: word, range: i..<text.endIndex) {
            let startsWord = r.lowerBound == text.startIndex || !isPathCharacter(text[text.index(before: r.lowerBound)])
            let endsWord = r.upperBound == text.endIndex || !isPathCharacter(text[r.upperBound])
            out += text[i..<r.lowerBound]
            out += startsWord && endsWord ? new : String(text[r])
            i = r.upperBound
        }
        out += text[i...]
        return out
    }

    private static func isPathCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || "_./+-".contains(c))
    }

    // MARK: - Validation (the script's rules, B3.2)

    /// 32 lowercase hex characters (128 random bits).
    package static func isToken(_ s: String) -> Bool {
        s.utf8.count == 32 && s.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// A fresh token from 16 random bytes; nil for any other count.
    package static func token(randomBytes: [UInt8]) -> String? {
        guard randomBytes.count == 16 else { return nil }
        let digits = Array("0123456789abcdef")
        return String(randomBytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] })
    }

    /// `D` (B3.1 step 3): `confstr(_CS_DARWIN_USER_TEMP_DIR)` with its trailing `/` trimmed, plus `/snaptic-lid`.
    /// Both sides use exactly this string, never a realpath; nil when the script would refuse it.
    package static func beaconDir(userTempDir: String) -> String? {
        var t = userTempDir
        while t.hasSuffix("/") { t.removeLast() }
        let d = t + "/" + beaconDirName
        return isBeaconDir(d, tempRoot: defaultTempRoot) ? d : nil
    }

    /// The stop file and the beacon in `D` (B3.1, B3.3); nil for an invalid token.
    package static func stopFileName(token: String) -> String? { isToken(token) ? "stop-" + token : nil }
    package static func beatFileName(token: String) -> String? { isToken(token) ? "beat-" + token : nil }
    /// Written at a quit that follows a restart, shut down or log out: the watchdog restores without `sleepnow`, as
    /// for launchd's TERM, even when the quit reaches it first (r2 A2-5).
    package static func haltFileName(token: String) -> String? { isToken(token) ? "halt-" + token : nil }

    /// The script's two `case "$D"` tests: `<root>/*/snaptic-lid`, no `..`, only `[A-Za-z0-9_/+.-]`; plus a length
    /// bound.
    static func isBeaconDir(_ d: String, tempRoot: String) -> Bool {
        let prefix = tempRoot + "/", suffix = "/" + beaconDirName
        guard d.utf8.count <= 1_024, d.utf8.allSatisfy(isPlainByte), !d.contains("..") else { return false }
        return d.utf8.count >= prefix.utf8.count + suffix.utf8.count && d.hasPrefix(prefix) && d.hasSuffix(suffix)
    }

    /// Absolute, plain bytes only, no `..`, at most 255 bytes: safe unquoted anywhere in the script.
    static func isSafePath(_ p: String) -> Bool {
        p.hasPrefix("/") && p.utf8.count <= 255 && p.utf8.allSatisfy(isPlainByte) && !p.contains("..")
    }

    /// `[A-Za-z0-9_/+.-]`, ASCII only (the script's own class, read without locale ranges).
    private static func isPlainByte(_ b: UInt8) -> Bool {
        switch b {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2B, 0x2D, 0x2E, 0x2F, 0x5F: return true
        default: return false
        }
    }

    // MARK: - The command and the AppleScript (B3.2)

    /// POSIX single quotes: `'…'`, each `'` written as `'\''`.
    package static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Three lines joined with LF: the foreground `check` (its exit code becomes the `do shell script` error
    /// number), the backgrounded `run` (`$!` is nohup's pid, and nohup execs the shell, so it is the watchdog's), then
    /// `echo $!`. Every stream is redirected, so `do shell script` returns at once.
    package static func command(_ args: Arguments) -> String {
        command(argv: args.argv, script: defaultScript, tools: defaultCommandTools)
    }

    /// The shell test's variant: any argv (to reach the script's own refusals), script and command tools.
    static func command(argv: [String], script: String, tools: [String: String]) -> String {
        let sh = tools[shellPath].flatMap { isSafePath($0) ? $0 : nil } ?? shellPath
        let nohup = tools[nohupPath].flatMap { isSafePath($0) ? $0 : nil } ?? nohupPath
        let body = sh + " -c " + quoted(script) + " snaptic-lid"
        let args = argv.map(quoted).joined(separator: " ")
        return [
            body + " check " + args + " </dev/null >/dev/null 2>&1 || exit $?",
            nohup + " " + body + " run " + args + " </dev/null >/dev/null 2>&1 &",
            "echo $!",
        ].joined(separator: "\n")
    }

    /// `try … do shell script … with prompt … with administrator privileges … on error number n`. Prints
    /// `ok <stdout>` or `err <n>`. nil when `command` or `prompt` holds a control character other than LF (or a
    /// format, line or paragraph separator, private-use or unassigned scalar).
    package static func appleScript(command: String, prompt: String) -> String? {
        appleScript(command: command, prompt: prompt, success: #""ok " & r"#)
    }

    private static func appleScript(command: String, prompt: String, success: String) -> String? {
        guard let c = appleScriptString(command), let p = appleScriptString(prompt), !prompt.isEmpty else { return nil }
        return [
            "try",
            "set r to do shell script \"" + c + "\" with prompt \"" + p + "\" with administrator privileges",
            "return " + success,
            "on error number n",
            "return \"err \" & n",
            "end try",
        ].joined(separator: "\n")
    }

    /// The text of an AppleScript string literal: `\` → `\\`, `"` → `\"`, LF → `\n`; nil for anything refused.
    static func appleScriptString(_ s: String) -> String? {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            switch u {
            case "\\": out.append(contentsOf: #"\\"#.unicodeScalars)
            case "\"": out.append(contentsOf: #"\""#.unicodeScalars)
            case "\n": out.append(contentsOf: #"\n"#.unicodeScalars)
            default:
                switch u.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                    return nil
                default:
                    out.append(u)
                }
            }
        }
        return String(out)
    }

    /// The script that starts the watchdog (B3.1 step 4); nil only if `prompt` is refused.
    package static func startScript(_ args: Arguments, prompt: String) -> AdminScript? {
        appleScript(command: command(args), prompt: prompt).map { AdminScript(source: $0) }
    }

    /// Turn Sleep Back On… (B3.4): fixed, no arguments, only turns sleep back on.
    package static let restoreCommand = "/usr/bin/pmset -a disablesleep 0 </dev/null >/dev/null 2>&1"

    /// Turn Sleep Back On…'s script: prints `ok` or `err <n>`; nil only if `prompt` is refused.
    package static func restoreScript(prompt: String) -> AdminScript? {
        appleScript(command: restoreCommand, prompt: prompt, success: #""ok""#).map { AdminScript(source: $0) }
    }

    // MARK: - Results (B3.1 step 5)

    /// osascript's stdout → outcome. Only `^ok [0-9]+$` with 1 < pid < 100 000 is a launch, and only
    /// `^err -?[0-9]+$` an error (−128 = Cancel); everything else, an out-of-range pid included, is `.failed(-1)`.
    /// One trailing LF (osascript's) is allowed.
    package static func parseResult(_ stdout: String) -> Outcome {
        guard let line = resultLine(stdout) else { return .failed(-1) }
        if let rest = line.dropping(prefix: "ok ") {
            guard let n = digits(rest), n > 1, n < 100_000 else { return .failed(-1) }
            return .launched(pid: Int32(n))
        }
        switch errorNumber(line) {
        case nil: return .failed(-1)
        case .some(-128): return .canceled
        case let n?: return .failed(n)
        }
    }

    /// Turn Sleep Back On…'s stdout: exactly `ok`, or `err <n>` as above.
    package static func parseRestoreResult(_ stdout: String) -> RestoreOutcome {
        guard let line = resultLine(stdout) else { return .failed(-1) }
        if line == Array("ok".utf8) { return .restored }
        switch errorNumber(line) {
        case nil: return .failed(-1)
        case .some(-128): return .canceled
        case let n?: return .failed(n)
        }
    }

    /// The bytes of a one-line result (at most 32 bytes, no control byte but one trailing LF).
    private static func resultLine(_ s: String) -> [UInt8]? {
        var bytes = Array(s.utf8)
        if bytes.last == 0x0A { bytes.removeLast() }
        guard bytes.count <= 32, !bytes.contains(where: { $0 < 0x20 || $0 >= 0x7F }) else { return nil }
        return bytes
    }

    /// `err -?[0-9]+` → the number, if it fits an Int32.
    private static func errorNumber(_ line: [UInt8]) -> Int32? {
        guard var rest = line.dropping(prefix: "err ") else { return nil }
        let negative = rest.first == 0x2D
        if negative { rest.removeFirst() }
        guard let n = digits(rest) else { return nil }
        let v = negative ? -n : n
        return v >= Int(Int32.min) && v <= Int(Int32.max) ? Int32(v) : nil
    }

    /// 1–10 ASCII digits.
    private static func digits(_ bytes: [UInt8]) -> Int? {
        guard (1...10).contains(bytes.count), bytes.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return bytes.reduce(0) { $0 * 10 + Int($1 - 0x30) }
    }

    // MARK: - Prompts (B1, B3.4)

    /// The password dialog's text for lid-closed mode (B1): the fixed 24-hour limit and the battery `floor`
    /// (clamped to 10–50).
    package static func promptText(floor: Int) -> String {
        let f = AwakeMath.clamp(floor, floorRange)
        let hours = AwakeCountdown.unit(capSeconds / 3_600, L("hour"), L("hours"))
        return L("Snaptic wants to keep your Mac awake with the lid closed for up to ") + hours
            + L(". Sleep turns back on when the session ends, when Snaptic quits, at \(f)% battery, or if your Mac gets hot. Enter an administrator password to allow this.")
    }

    /// The password dialog's text for Turn Sleep Back On… (B3.4).
    package static var restorePromptText: String {
        L("Snaptic wants to turn sleep back on. It may have been left off by an earlier lid-closed session. Enter an administrator password to allow this.")
    }
}

private extension Array where Element == UInt8 {
    /// The bytes after `prefix`, or nil when they don't start with it.
    func dropping(prefix: String) -> [UInt8]? {
        let p = Array(prefix.utf8)
        guard count >= p.count, Array(self[0..<p.count]) == p else { return nil }
        return Array(self[p.count...])
    }
}

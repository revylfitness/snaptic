import Foundation

// Lid-closed mode's root side and its prompts (owner: T-lid-kit; PLAN 0.3.1 B3.2, B5). The only file in Sources/ that
// may spell the root command's words, and the only one that can make an `AdminScript` or a `ToolCommand` (lint L18).
//
// Step 0 stub: every builder returns nil or empty, so nothing can run as root until T-lid-kit lands. The fixed paths
// and requirements are real; the shapes below are the contract T-lid-app codes against.

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

    /// What osascript printed (B3.1 step 5).
    package enum Outcome: Equatable, Sendable {
        /// `ok <pid>`: the watchdog's pid (1 < pid < 100 000).
        case launched(pid: Int32)
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

        /// nil when any value breaks the script's rules. Stub: always nil.
        package static func validated(uid: UInt32, pid: Int32, token: String, capSeconds: Int, floor: Int,
                                      dir: String) -> Arguments? {
            nil
        }
    }

    /// Every absolute tool path the script uses, by name (the shell test swaps them for stubs). Stub: empty.
    package static let defaultTools: [String: String] = [:]

    /// The fixed `/bin/sh` script (a raw literal; LF is its only control byte). Stub: empty.
    package static func script(tools: [String: String] = defaultTools, period: Int = 5, stale: Int = 20) -> String {
        ""
    }

    /// The three-line root command (`check`, then the backgrounded `run`, then `echo $!`). Stub: empty.
    package static func command(_ args: Arguments) -> String { "" }

    /// `try … do shell script … with administrator privileges … on error number n`; nil when `command` or `prompt`
    /// holds a control character other than LF. Stub: nil.
    package static func appleScript(command: String, prompt: String) -> String? { nil }

    /// The script that starts the watchdog. Stub: nil.
    package static func startScript(_ args: Arguments, prompt: String) -> AdminScript? { nil }

    /// Turn Sleep Back On… (B3.4): fixed, no arguments, only turns sleep back on. Stub: nil.
    package static func restoreScript(prompt: String) -> AdminScript? { nil }

    /// osascript's stdout → outcome. Stub: `.failed(-1)`.
    package static func parseResult(_ stdout: String) -> Outcome { .failed(-1) }

    /// The password dialog's text for lid-closed mode (B1). Stub: empty.
    package static func promptText(floor: Int) -> String { "" }

    /// The password dialog's text for Turn Sleep Back On… (B3.4). Stub: empty.
    package static var restorePromptText: String { "" }
}

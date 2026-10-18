# Keep-awake parity research: Amphetamine and Insomnia

Research date: 2026-10-17. Purpose: catalog what Amphetamine (closed source, Mac App Store) and Insomnia (MIT, GitHub) do, so Snaptic can ship a free OSS keep-awake feature. Facts carry inline source URLs. Items marked **[unverified]** come from a single third-party page or from inference and should be checked on hardware before relying on them.

Source key:
- AS = Mac App Store listing, https://apps.apple.com/us/app/amphetamine/id937984704?mt=12
- SP = Softpedia changelog mirror (full version history), https://mac.softpedia.com/progChangelog/Amphetamine-Changelog-140109.html
- AE = Amphetamine Enhancer repo, https://github.com/x74353/Amphetamine-Enhancer
- PP = Amphetamine Power Protect repo, https://github.com/x74353/Amphetamine-Power-Protect
- TX = Timex blog, https://gettimex.app/blog/amphetamine-for-mac
- CM = Classmethod walkthrough, https://dev.classmethod.jp/en/articles/amphetamine-keep-mac-awake-for-claude/
- JB = Jon Brown review, https://jonbrown.org/blog/amphetamine-review-and-walkthrough/ (shallow; adds little beyond launch-at-login and stats)
- IR = Insomnia README, https://github.com/krishhgg/Insomnia
- IS = Insomnia `docs/spec.md` in that repo (read from a clone at the default branch)
- IW = Insomnia site, https://getinsomnia.app/
- RA = https://roaringapps.com/app/amphetamine. Its compatibility table did not render (template placeholders only) and had no status reports, so it adds nothing.

---

## 1. Amphetamine (William Gustafson)

### 1.1 Status and platform
- Free, with no ads, in-app purchases or tracking. Version 5.3.2 shipped 2023-11-10, about 6.7 MB, with 10 localizations. The Information section says it needs macOS 10.13+, though the description text still says 10.11 (AS).
- It has had no release since 5.3.2, so newer macOS versions have received no fixes (TX). clamshell.dev also reported 5.3.2 as the latest as of 2026-10-05 (https://clamshell.dev/guides/amphetamine-alternative-lid-closed).
- It is sandboxed because it ships through the App Store. That is why it needs out-of-sandbox add-ons for full process listing and for closed-lid mode on Apple Silicon (AE).
- Universal build since 5.1.1 (Big Sur). 5.3.1 added a warning when it runs under Rosetta and fixed Apple Silicon Macs being detected as Intel (SP; https://softantenna.com/blog/amphetamine-5-3-1/).

### 1.2 Manual session types
- **Indefinite**: runs until ended (AS).
- **Duration**: a preset or custom length. Custom input takes hours, minutes and seconds (1.5), and the "Other Time" window remembers the last values (4.1) (SP).
- **Until a clock time**: added in 4.1 (SP, AS).
- **While a file is downloading**: has a custom timeout and shows percent complete when Safari reports it (AS). Custom download timeouts arrived in 5.0 (SP).
- **While an app is running**: added in 2.3.1. It sees only processes the sandbox exposes unless Process Discovery or Enhancer is installed (SP, AE, TX).
- **Extend a running timed session**: added in 5.2/5.2.1 (SP, AS).
- **Default-duration quick start**: a configurable default duration (1.2), started by a hotkey or by ⌘-clicking the menu bar icon (1.5.1). That hotkey can also end a running session (2.0.1) (SP).

### 1.3 Session options (per session and per Trigger)
Each can be allowed or prevented (AS, TX):
- Display sleep. It can also be toggled mid-session by hotkey (4.2) and read through AppleScript `display sleep allowed` (4.0.4) (SP).
- Screen saver activation, with a "customizable period of inactivity" and a screen-saver exceptions list (AS). Each Trigger has its own screen-saver delay (4.1.4) (SP).
- System sleep when the built-in display is closed, i.e. Closed-Display Mode (see 1.7).
- Automated mouse cursor movement at an adjustable interval (5.0; interval fixes in 5.2.x) (AS, SP).
- Locking the screen after a period of inactivity (5.0) (AS).

### 1.4 Automatic session ending
- When the battery is low. 1.3 offered thresholds of 50/25/10/5%. Since 4.1, battery warnings take inactivity into account before auto-dismissing (SP, AS).
- When the power adapter is disconnected (2.1) (SP).
- When the Mac is put to sleep manually. This applies to non-Trigger sessions (5.0) (SP).
- On Fast User Switching, as an option (4.1) (SP).
- Closed-Display sessions end automatically under certain conditions (5.2). A failure dialog can turn that termination off (5.2.1) (SP).
- A Trigger session the user ends by hand can re-activate after a set time (4.1) (SP).

### 1.5 Triggers (automatic sessions)
A Trigger starts a session while its criteria hold. You can create any number of Triggers (3.0), reorder them to set priority (4.1), give each a unique name (5.0), and combine criteria with AND/OR (5.0) (SP, AS). Triggers only run while the app is running, which is why "Launch at Login" matters (CM).

Criteria (AS, SP, TX):
- **Displays**: an external display is connected, with an option to ignore the built-in display (4.2), or display mirroring is on (4.1.5).
- **USB device** or **Bluetooth device** connected (4.0).
- **Application** running, optionally only when frontmost (4.0).
- **Battery & Power Adapter**: charging, battery above a threshold, adapter connected or not connected (5.0).
- **Network**: IP address (IPv6 since 5.0), Wi-Fi SSID (multiple networks since 2.1), DNS server in use (fires if any listed server is active), or VPN (Cisco AnyConnect, 4.1). Since 5.3.1, reading the SSID needs Location Services on Sonoma (SP).
- **Audio output / headphones** in use (4.0).
- **Mounted drive or volume** (4.0).
- **CPU utilization** above a threshold (4.1.4).
- **Idle time** above a threshold (4.1.5).
- **Schedule**, e.g. 9am to 5pm (1.5; expanded in 3.0).

Notable fixes: Triggers did not fire on some desktop Macs, and IP-based Trigger sessions did not end on time (both fixed in 5.3.1) (SP).

### 1.6 Drive Alive
- Keeps external drives from spinning down, with a per-drive picker (2.0) and a custom interval (4.0) (SP, AS).
- 4.1.6 fixed a feature stall and a memory leak when adding drives (SP).
- The mechanism is not documented. **[unverified]** It is most likely a periodic small write or read on the volume.

### 1.7 Closed-Display Mode (closed-lid), how it works and its risks
- Added in 5.0. It keeps a MacBook awake with the lid shut, and since 5.3 it forces the built-in display to sleep to avoid burn-in (AS, SP).
- **Intel**: worked from inside the sandbox with no script. The public sources do not document the mechanism. clamshell.dev describes an "unprivileged IOKit clamshell sleep-state control" on `IOPMrootDomain` that a competing product uses (https://clamshell.dev/guides/amphetamine-alternative-lid-closed). **[unverified]** that this is what Amphetamine used on Intel.
- **Apple Silicon (5.3+)**: CDM "may not work as expected after connecting or disconnecting… a power adapter or display with power delivery" (PP). 5.3 added a script that runs at session start and end and needs admin authentication (Touch ID or password) each time. Without the script, CDM still works but can fail on power changes (SP).
- **Power Protect (5.3.1)**: a separate, Touch-ID-authenticated installer from GitHub. It writes `~/Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt` and `/private/etc/sudoers.d/amphetamine_powerProtect` (PP). The sudoers rule lets admin accounts run `pmset -a disablesleep 1` and `pmset -a disablesleep 0` without a password (TX). Amphetamine reaches the script through the sandbox's Application Scripts folder (the NSUserScriptTask mechanism). The developer says Apple rejected the approach several times before approving it (https://softantenna.com/blog/amphetamine-5-3-1/). Uninstall is under Feedback & Support → Uninstall Scripts… (TX).
- **`pmset disablesleep` risks**: it is undocumented in the pmset man page and shows up as `SleepDisabled` in `pmset -g` (TX). It is system-wide and persistent until undone, has no timer or indicator, and needs sudo both to set and to undo (https://clamshell.dev/guides/amphetamine-alternative-lid-closed). If the app crashes, sleep stays disabled. Any process running as the user can use a passwordless sudoers rule (IR says this about its own identical rule). A closed lid also cuts airflow, so heavy jobs run hot; never use it in a bag (TX, IW).
- **Amphetamine Enhancer** (MIT, notarized, last updated July 2020; TX, AE) adds two features.
  - *CDM fail-safe*: a LaunchAgent runs `amphetamine-enhancer-cdmManager.sh` every 10 s and also on changes to the container's `ClosedDisplaySleep/` folder (WatchPaths). If `defaults read com.if.Amphetamine cdmEnabled` is 1 and either Amphetamine is not running or `pmset -g assertions` shows no Amphetamine assertion, it opens a bundled `CDMManager.app` that re-enables closed-display sleep, then writes `cdmEnabled=false` (AE source: `Scripts/amphetamine-enhancer-cdmManager.sh` and `Launch Agents/*.plist`). This is a dead-man switch for a crashed app.
  - *All-processes access*: a LaunchAgent runs `ps ax -c` every 10 s, writes the output to `~/Library/Containers/com.if.Amphetamine/Data/Library/Application Support/Amphetamine/Processes/ProcessList.txt`, and toggles a sentinel file so the sandboxed app notices the change (AE source: `amphetamine-enhancer-allProcesses.sh`). Since 5.3 this is replaced on Apple Silicon by a built-in **Process Discovery** script, installed from the (?) button in the While App Is Running menu (SP, TX).

### 1.8 Menu bar UI
- Icon choices: pill, molecule, coffee carafe, caffeine, coffee cup, kettle, owl, eye, sun/moon, emoji, "Zzz!!!" (CM). Custom images can be set separately for active and inactive states (2.3; non-square since 4.0.3). There is an empty/full style (1.2), reduced opacity when inactive (1.5.3), manual image padding (5.0), and a dark theme option (2.3.1) (SP, CM).
- Time remaining can show in the menu bar (1.3) as hh:mm or hh:mm:ss (2.2), in 12- or 24-hour form (AS). The menu shows seconds (4.0.4) and why a session is active (2.3.1) (SP).
- Click and modifier behavior: ⌘-click starts a default session (1.5.1), and a "Run in Menu Mode" option exists (1.5.2) (SP). The Quick Preferences submenu has green/red or non-color status indicators (4.1, 4.1.2) (SP).
- Other: Launch at Login (reworked for macOS 13+ in 5.3) (SP, JB, CM). Focus returns to the previously frontmost app after interaction (1.2) (SP).

### 1.9 Notifications and sounds
- Notification Center support with a reminder feature (1.1). Options cover deactivation notices and sounds (1.3), notices on manual start and stop (3.0.1), and a sound on every state change (4.1). Custom sounds play through the Sound Effects output device (5.2). Since 5.3.1 all alerts are floating windows (SP, AS).

### 1.10 Hotkeys, automation, statistics, debugging
- Global hotkeys can start or end a session, start the default-duration session or Quick Activation, toggle display sleep, and toggle the screen saver (1.1, 1.4.1, 2.0, 4.2) (SP, AS).
- AppleScript arrived in 2.0 and was expanded in 5.0 (SP). Commands reported by a third-party skill page (https://skillsmp.com/creators/servitola/dotfiles/claude-code-skills-amphetamine-control): `start new session`, `start new session with options {duration:N, interval:minutes|hours, displaySleepAllowed:bool}`, `session is active`, `end session`. A 0 interval means indefinite (5.1 fix, SP). The same page claims an `amphetamine://start-new-session?…` and `amphetamine://end-session` URL scheme **[unverified]**. Neither AS nor SP mentions a URL scheme, and no Shortcuts or App Intents support is documented.
- The Statistics pane (4.1) shows session data, updates live (4.1.4), and can be reset or turned off (SP, AS, JB).
- Debug Mode arrived in 5.3.2 (AS).

### 1.11 Known limitations and complaints
- Process visibility is limited by the sandbox without add-ons (AE, TX).
- CDM on Apple Silicon is fragile across power changes without Power Protect, and it is "most reliable on power" (PP; https://www.getmasset.com/resources/blog/keep-your-mac-awake-for-ai-agents).
- 5.3.1 had to add logic around power assertions for cases where the Mac still slept, dropped external displays or Wi-Fi, or flashed displays (https://softantenna.com/blog/amphetamine-5-3-1/).
- Users suspected Amphetamine in Ventura freezes, but the thread concluded it was "most likely not the root cause". One user found it stopped external SSDs from disconnecting (https://talk.macpowerusers.com/t/amphetamine-versus-ventura/32857).
- "Session Defaults": no public source describes a pane with this name. Per-session defaults live in the default-duration setting and in each Trigger's options (SP, CM). Treat the name as informal.

---

## 2. Insomnia (krishhgg/Insomnia, MIT)

### 2.1 Positioning and platform
- Tagline: "Caffeinate for the agentic era." Its goal is to keep coding agents, Docker and browsers running with the lid closed (IW).
- Requires macOS 26+ on Apple Silicon. Built with Swift 6.2 as a Swift Package with no Xcode project. The app is ad-hoc signed and installed by script to `~/Applications`. It is not notarized and not a privileged helper (IR, IS "Non-goals"/"Platform").
- The project calls itself experimental: "Recovery can fail, and a timer is not a safety guarantee" (IR, IW).
- About 15.7k lines of Swift in `Sources/Insomnia/{Core,System,UI,Model,Store}`, plus extensive tests that use fakes (from the clone).

### 2.2 Session model
- **Timed only, never a toggle, and no indefinite mode.** The maximum is 30 days including extensions. Preset chips are 30m, 1h, 2h, 4h, 8h, 12h, 24h and 3d, and the default preset is 4h (`Model/Config.swift`; IS §1).
- Quitting always ends the session; there is no "keep awake after quit." Opening the lid does not end a session (IS §1, IR).
- There are no Triggers, app or file conditions, schedules, Drive Alive, hotkeys or AppleScript. The site's keyboard shortcuts are website navigation only (IW).

### 2.3 Mechanism
- Sleep prevention is **only** `sudo -n /usr/bin/pmset -a disablesleep 1/0`. A sudoers file `/etc/sudoers.d/insomnia` written by `install.sh` allows exactly four commands: `disablesleep 1`, `disablesleep 0`, `-b lowpowermode 1` and `-b lowpowermode 0`. "Nothing else runs as root" (IS §2, `Core/SleepGuard.swift`). It does not use IOPMAssertion for sleep prevention. Its one assertion call is `IOPMAssertionDeclareUserActivity`, used to wake the display on lid open (`System/DisplayPower.swift`).
- **Read-back check**: 5 s after `disablesleep 1`, it re-reads `pmset -g` and fails the start if `SleepDisabled` reverted. The authors saw another keep-awake tool's root LaunchDaemon reset the flag every 2 s (`SleepGuard.swift`). This is a real interoperability hazard of the pmset approach.
- **Lid observer**: an IOKit interest notification on `IOPMrootDomain` for `AppleClamshellState`, debounced by 2 s, with zero cost between events (IS §3, `System/LidObserver.swift`).
- **Recovery**: every change is journaled to `~/Library/Application Support/Insomnia/` (owner-only permissions) *before* it is made. A launchd agent (`backstop.sh`) runs every minute and undoes changes after the end time if the app died. It cannot restore audio or monitor battery or heat. A session never starts unless the backstop is armed (IR, IS §1, §8). Failed undos stay on disk and the menu warns the user (IW).

### 2.4 Lid-close actions (during a session; all reversed on open)
(IR, IS §4, docs/lid-close.md)
- The display and keyboard backlight go to 0 after saving their levels. This uses **private** DisplayServices and CoreBrightness `KeyboardBrightnessClient`, gated to measured macOS majors 26 and 27 and checked against ObjC type encodings.
- Apps on a freeze list (Slack, WhatsApp, Discord by default) are frozen with SIGSTOP and resumed with SIGCONT, but only for PIDs whose identity it can prove. "Freeze all other Dock apps" is an opt-in, with a large protected set of editors, terminals, browsers, meeting and dictation apps, password managers and `com.apple.*`.
- Audio output is muted per device and restored. Low Power Mode is switched on. Docker Desktop is frozen only if `docker ps -q` is empty twice (opt-in).
- On Apple Silicon and T2 Macs the built-in mic is disconnected in hardware whenever the lid is closed. This is a platform fact, not an Insomnia action.

### 2.5 Battery and thermal floors
(IS §6, IR)
- Battery below 40%: Low Power Mode on. Below 10%: end the session (0 disables this). Battery unreadable on two consecutive reads while on battery: end the session.
- `ProcessInfo.thermalState` `.serious`: Low Power Mode on. `.critical`: end the session.
- Events come from `IOPSNotificationCreateRunLoopSource` and `thermalStateDidChangeNotification`. These rules only run while the app is alive.

### 2.6 UI and notifications
- An eye icon with no Dock icon (`LSUIElement`). Clicking it expands inline Days / Hours / Minutes pill fields in the menu bar. Enter starts the session (an empty Enter uses the default preset), Tab moves between fields, Esc collapses (IS §11, IR).
- While running, a 1 Hz countdown sits next to the icon and pauses while the lid is closed. Click the countdown to extend. **Hold** the × for 0.6 s to end, which prevents accidental stops (IW).
- Right-click shows status lines (lid state, battery watts from `AppleSmartBattery` InstantAmperage × Voltage read on demand, Wi-Fi, frozen apps, Docker), browser actions, Settings and Quit. Quit refuses while an undo is pending (IR, IS §11).
- Animation is spring-based, with Reduce Motion crossfades (IS §11).
- Notifications (UNUserNotificationCenter): session ended (with reason), a 5-minute "extend" reminder, battery floor reached, battery unreadable, thermal action, network recovered, sleep restored by the backstop, and sleep disabled by another process (IS §9, `UI/ReminderScheduler.swift`).
- Launch at login uses SMAppService (`UI/LoginItem.swift`).

### 2.7 Insomnia-only extras (Amphetamine has none of these)
- **Hotspot failover**: when Wi-Fi drops it joins an iPhone hotspot via CoreWLAN, with the password in the login Keychain. Location Services is needed for SSIDs (IR, IS §7).
- **tmux nudge**: after 90 s offline it types `continue` into tmux panes tagged `@insomnia-nudge`, without pressing Enter by default (IR).
- **Browser throttling**: offers to relaunch Chrome, Chromium, Arc or Comet with background-throttling flags (IR).
- **App Nap off for agents** (opt-in): writes `NSAppSleepDisabled=YES` into other apps' preferences and restores the old value at the end (IS §5).
- Detection that another process disabled sleep, the journal-before-act invariant, battery watts in the menu, and hold-to-end.

---

## 3. Parity target for Snaptic (free, MIT, menu bar)

Snaptic's constraints are no network, no running attacker-chosen code under Snaptic's TCC grants, and no privileged helpers.

**Core design choice: use public IOKit power assertions only.** Use `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleSystemSleep` when the display may sleep, and `kIOPMAssertionTypePreventUserIdleDisplaySleep` to keep it on. This is the same mechanism as `caffeinate -i/-d`. The kernel releases assertions automatically when the process exits. That removes the whole recovery and backstop problem Insomnia spends thousands of lines on, and avoids the "app crashed, sleep still disabled" failure of `pmset disablesleep` (TX; IS §8). It also doesn't conflict with other tools the way the `SleepDisabled` flag does (`SleepGuard.swift`). The trade-off: assertions do **not** keep a MacBook awake with the lid closed on battery.

### 3.1 v1 must-have
1. **Session types**: indefinite, preset durations, custom duration (h/m), until a clock time, extend a running session. Optionally cap indefinite sessions with a soft reminder.
2. **While an app is running**: pick from running apps by bundle ID via `NSWorkspace` notifications. This needs no TCC and no helper. It covers the "keep awake while Claude/Terminal runs" use case (CM).
3. **Per-session option**: allow display sleep (system stays awake) versus keep the display on.
4. **Safety ends**: end on battery below N% (default 10–20%) via `IOPSNotificationCreateRunLoopSource`; end on `ProcessInfo.thermalState == .critical` (Insomnia's rule, IS §6); optionally end on power adapter disconnect (Amphetamine 2.1, SP); end when the user manually sleeps the Mac (Amphetamine 5.0) via `NSWorkspace.willSleepNotification`.
5. **Menu bar**: active and inactive icon states (a template SF Symbol plus reduced opacity when inactive), optional countdown text in the bar (hh:mm, seconds optional), and why the session is active ("Until 5:00 PM", "While Xcode runs"). One click opens the menu; Option or ⌘-click starts the default preset (Amphetamine 1.5.1). Copy Insomnia's hold-to-end or a confirm step so a stray click doesn't stop the session.
6. **Defaults**: a configurable default duration and preset list; launch at login (SMAppService); remember the last custom value.
7. **Notifications**: a local `UNUserNotificationCenter` notice for session ended (with reason) and an "N minutes left, extend?" reminder (Insomnia's 5-minute reminder). Sounds are optional.
8. **Global hotkey**: toggle a default session, plus a toggle for display sleep (Amphetamine 4.2). Reuse Snaptic's existing hotkey infrastructure.
9. **Status honesty**: show in the menu when the battery or thermal rule ended a session, and optionally show other apps' assertions (`IOPMCopyAssertionsByProcess`) so users can see why their Mac isn't sleeping.

### 3.2 Defer (v2+), feasible without violating the principles
- **Triggers engine** with AND/OR criteria, priorities and per-Trigger options. Criteria that need no TCC can come first: app running or frontmost, external display connected (CGDisplay reconfiguration callback), power adapter or charging or battery above N%, schedule, CPU above a threshold (`host_processor_info`), idle time (`CGEventSourceSecondsSinceLastEventType`), volume mounted (NSWorkspace), and audio output active (CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`, which needs no mic permission). Later: USB devices (IOKit matching notifications), Bluetooth (may need Bluetooth TCC), and Wi-Fi SSID (needs Location Services on Sonoma+ (SP), so it is opt-in at best). IP, DNS and VPN only by reading local SCDynamicStore state, never by connecting.
- **While a file is downloading**: watch for a `.download`/`.crdownload` file in ~/Downloads to vanish, with a timeout. This needs Downloads-folder TCC under Snaptic's identity, so it should be opt-in.
- **Screen-saver control and the "allow screen saver after N min" option**. **[unverified]** It may need periodic `IOPMAssertionDeclareUserActivity` or a separate approach. Test what PreventUserIdleDisplaySleep does to the screen saver.
- **"Jiggle" / stay "Active" for chat-presence apps**: implement as periodic `IOPMAssertionDeclareUserActivity`, not by moving the cursor. Synthetic CGEvent cursor movement needs Accessibility or event-posting TCC and moves the user's pointer.
- **Lock screen after inactivity**: the only routes are private (`SACLockScreenImmediate`) or indirect (start the screen saver with require-password). Defer until a public path is confirmed.
- **Drive Alive**: periodic tiny write or `fsync` to a chosen external volume. This needs the Removable Volumes TCC grant; make it opt-in per volume.
- **Statistics**: local-only session history and totals, resettable (Amphetamine 4.1).
- **Automation**: App Intents / Shortcuts actions (Start session [duration, allow display sleep], End, Is Active) and an AppleScript `sdef` mirroring Amphetamine's four commands. These only set Snaptic's own assertion state and run no code. **Do not** ship an unauthenticated `snaptic://` URL scheme that any web page can fire. If one is added, limit it to start and stop with no free-form parameters.
- **Thermal and battery mitigations beyond ending**: Insomnia's 40% Low Power Mode step needs root (`pmset -b lowpowermode`), so the most Snaptic can do is suggest the user turn it on.

### 3.3 Exclude
- **Closed-lid on battery** via `pmset -a disablesleep`, Power Protect-style sudoers rules (`/etc/sudoers.d/*`), or authenticated scripts. These need root, are system-wide and persistent after a crash, and any same-user process can exploit a passwordless rule (IR, PP, TX). They also bring overheating risk in a closed lid or bag (TX, IW). Tell users the native route instead: macOS already supports clamshell mode with an external display and power (TX).
- **Unprivileged IOKit clamshell-sleep override** (`IOPMrootDomain` user-client clamshell state, as described by https://clamshell.dev/guides/amphetamine-alternative-lid-closed). It is undocumented SPI with a heat risk and reported fragility across power changes on Apple Silicon (PP). Revisit only for "on AC power only" with mandatory thermal-critical cutoff, if ever. The claim that `caffeinate -s` keeps a closed lid awake on AC (https://www.getmasset.com/resources/blog/keep-your-mac-awake-for-ai-agents) is **[unverified]**; test it before telling users.
- **Insomnia's lid-close actions**: SIGSTOP/SIGCONT on other apps, writes to other apps' preferences (App Nap), private DisplayServices or CoreBrightness brightness control, and muting via a journal. These are invasive, can leave other apps frozen if the undo fails, and rely on private ABI (IS §4–5).
- **Network features**: hotspot joining with stored passwords, network-reachability-driven actions, and update checks. These violate the no-network principle (IR).
- **Typing into terminals (tmux nudge), relaunching browsers with flags, running `docker ps`**. These execute or inject commands under Snaptic's TCC (IR).
- **Out-of-sandbox helper agents** like Amphetamine Enhancer's LaunchAgents that poll `ps` every 10 s (AE). Snaptic is not sandboxed, so `NSWorkspace` already covers app-running detection. Full process-name matching via `proc_listpids` is acceptable in-process later. No separate helper is needed.

### 3.4 Implementation notes
- Hold at most one assertion and swap its type when the display option changes. Name it "Snaptic: <reason>" so `pmset -g assertions` explains itself (Enhancer's fail-safe looked for exactly this, AE).
- The countdown timer should be wall-clock based (`endsAt` Date) so sleep and wake or clock changes don't drift. Stop redrawing when the menu bar isn't visible (Insomnia redraws at 1 Hz and stops while the lid is closed, IS §1).
- Validate the battery rule on desktops: no battery means no floor. Treat an unreadable battery on a laptop conservatively (IS §6).
- Amphetamine's own last-mile bugs are a test checklist: Triggers on desktops, IP Triggers not ending on time, menu-bar text overlapping the icon, sessions started at launch, and the Rosetta warning (SP).

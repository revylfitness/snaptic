# Snaptic 0.3 plan: Awake module, Settings redesign, Menu bar redesign

Status: **r1** (planning architect draft). Base: `feature/displays` == `main` @ 871c10b.
Normative like `docs/design/PLAN.md` (0.2): where this plan and 0.2 disagree, **this plan wins** for 0.3 scope; everything 0.2 says that this plan does not touch (safety framework, helpers, guard, transactions, R5 amendments) stays in force. Swift signatures in this document are the contract the lead writes as compiling stubs in step 0; once on the branch, the code wins over prose (R5 rule carried forward).

Inputs: `scratchpad/plan2/{awake-parity.md, power-apis.md, ui-audit.md, design-spec.md}` (cited as [AP], [PA], [UA], [DS] with section numbers).

## 0. Summary and decisions

Snaptic 0.3 does three things:

1. **Awake** (new module, `ModuleID.awake`): a free, MIT, public-API-only replacement for Amphetamine and Insomnia. Manual sessions (indefinite, duration, until a time, while an app runs), user-defined session types (presets), automatic sessions (triggers with 12 TCC-free criterion kinds, priorities, per-trigger options), battery/thermal/Low Power Mode guards, activity simulation, Drive Alive, its own menu bar indicator with optional countdown, hotkeys and `snaptic awake …` CLI. One named IOKit power assertion, swapped by type, with `TimeoutActionRelease` backstops. Displays' `sleepPrevention` moves here.
2. **Settings redesign**: one SwiftUI component library (`Sources/Snaptic/SettingsUI/`), a new information architecture (sidebar 31 rows → 8; default visible controls ~245 → ~70), every option explained, the 14 duplicates removed, expert options behind **Advanced…**, settings search, and the live-update root causes fixed in the architecture (observable per-display runtime, controller revisions, drag-local slider state, throttled commits, config fan-out by section).
3. **Menu bar redesign**: one menu item factory (`MenuKit`), one header style, inline slider rows with live values, no sliders in submenus, one level of submenus, "Settings…" last; an Awake status item; the Snaptic menu shows a compact Awake section only on request.

Priorities (0.2 order kept, Awake rows added): (1) never leave the user without a usable display, keyboard or way back; (2) nothing Snaptic does lets another process use Snaptic's permissions or see data obtained with them; (3) never damage a monitor **or drain a battery to shutdown** (Awake guards are always on); (4) parity; (5) polish.

### 0.1 Decisions taken here (normative)

| # | Decision | Why |
|---|---|---|
| N1 | CLI **may start** Awake sessions (closed grammar, guards apply, never pointer movement or Drive Alive) | §3.1: a same-user process can already hold the same assertion with `caffeinate`; no capability is gained |
| N2 | Duration sessions run on the **continuous clock** (counts sleep, immune to clock changes); "Until" sessions are absolute instants; a reboot ends every session | Predictable; matches Amphetamine; no recovery machinery needed |
| N3 | One **governing** source at a time: the manual session if any, else the highest-priority active trigger | Amphetamine's priority model; one assertion; one indicator reason |
| N4 | Every Settings slider gets a typed value field and a reset glyph (user request overrides [DS] §2 "field only where precision matters") | Explicit requirement |
| N5 | All modules always appear in the sidebar; each module page has a master switch (Wi-Fi pattern); a stopped module's page shows a short "what this does" block | [DS] §1.2; sidebar never reshapes |
| N6 | Displays' 16 sidebar pages become **one** sidebar row with sub-pages in a `NavigationStack` | [DS] §1.1, [UA] §2.1 |
| N7 | Everything about the menu bar (presence per module, icons, countdown, Displays menu customization) lives **only** on the Menu Bar page | Removes duplicates 4, 13 and the Awake split |
| N8 | Displays feature switches live where the feature is used (sub-page header switch or section switch); the 47-switch Features page is deleted | [UA] §2.5 #4 |

### 0.2 Decisions to confirm (lead)

| # | Proposal | Default if not confirmed |
|---|---|---|
| C1 | While the screen is locked, a `keepOn` session downgrades to system-only (display may sleep, Mac stays awake); Advanced option "Keep the display on while locked" | Adopt |
| C2 | Replace `MenuPlacementChoice` (shared / own / hidden) with `MenuPresence { ownItem, inSnapticMenu }` so a module can have both (Awake needs this) | Adopt (migration in §4.6) |
| C3 | Drop the right-click "quick menu" (right-click is not delivered on macOS 27 [PA] §8); its items move into **Display Tools ▸** | Adopt |
| C4 | Menu slider rows show a live value but no typed field or reset (NSMenu views don't reliably take keyboard focus; Settings, shortcuts and CLI cover precision) | Adopt |
| C5 | "Network activity above N KB/s" criterion (interface byte counters via `getifaddrs`, no connections, no TCC) replaces the TCC-gated Downloads-folder criterion | Adopt |
| C6 | Bluetooth criterion limited to Bluetooth **audio** devices (CoreAudio transport type) and Bluetooth **input** devices (IORegistry `IOHIDDevice` `Transport` property, never opened); Beta | Adopt |
| C7 | 0.2 → 0.3 upgraders get Awake **off** unless the sleep-prevention migration produced an enabled trigger; a one-time "New: Awake" card | Adopt |
| C8 | Menu item "Switch Windows ⌥⇥" opens the switcher in sticky mode (stays open until Return/Esc/click); new small Switcher capability (A) | Adopt; fallback: omit the item |
| C9 | Drive Alive runs only while an Awake session is active, unless the user turns on "Even without a session" | Adopt |
| C10 | Default session (header switch, hotkey) = **Until Turned Off**, battery guard on at 20% | Adopt (Amphetamine parity) |

Open questions (need hardware or product input) are marked **[OQ-n]** and collected in §6.8.

---

## 1. Scope

Legend: **Def** = A always on with the module, S standard (on), O opt-in, X experimental, B beta tag. Amphetamine references are [AP] §1.x, Insomnia [AP] §2.x.

### 1.1 Awake: In

`AwakeFeature` (Kit, persisted raw values) and what each covers.

| Feature id | Covers | Def | Requires | Parity |
|---|---|---|---|---|
| `sessions` | Manual sessions: indefinite; duration (presets + custom h/m); until a clock time; while an app runs (picked from running apps, by bundle id, ends when its last instance quits); extend (+15 min / +1 h / +2 h / custom); end; replace; display policy per session (keep on / may sleep / keep on while I'm active, then may sleep after N min idle); end on sleep (opt), end on user switch (opt); resume after Snaptic relaunch within the same boot; start a session at launch (opt); "why is my Mac awake" lid notice | A | — | Amph 1.2 (all but "while downloading"), 1.3 display sleep, 1.4 manual-sleep / FUS ends, 1.8 reason text; Insomnia 2.2 timed sessions, chips, 30-day cap |
| `presets` | Session types: up to 12 named presets (kind + options), shown in the Awake menu in order; default preset; last custom value remembered | A | sessions | Amph "default duration", "Other Time" memory (1.2); Insomnia preset chips |
| `batteryGuard` | End below N% on battery (5–50%, default 20%, can be off); end on adapter disconnect (opt); end on Low Power Mode (opt); two unreadable battery reads on battery → end; trigger restarts suppressed until cleared (+5% hysteresis or AC) | S | — | Amph 1.4; Insomnia 2.5 floor and unreadable rule |
| `thermalGuard` | `.critical` → end all sessions, pause automatic sessions 10 min; `.serious` → one-time toast, optional end | A | — | Insomnia 2.5 |
| `indicator` | Awake's own status item: icon only / icon + time remaining / hidden; curated glyph family; separate family for automatic sessions (Advanced); seconds (opt); end time instead of remaining (opt); VoiceOver label | S | — | Amph 1.8 (no custom images); Insomnia 2.6 countdown |
| `triggers` | Automatic sessions: ≤ 32 triggers, each ≤ 8 criteria, All/Any, negation, order = priority, per-trigger session options, start delay, end delay (hysteresis), re-activation after manual end, "Pause automatic sessions for 1 h / until tomorrow" | O | sessions | Amph 1.5 (all criteria except SSID, DNS server list, Cisco VPN brand) |
| `activity` | "Tell macOS I'm active": `IOPMAssertionDeclareUserActivity` at an interval while a session runs, the screen is unlocked, the session is on console, the user has been idle ≥ interval and the displays are awake | O | sessions | Amph 5.0 cursor movement (closest TCC-free equivalent) |
| `pointerNudge` | "Move the pointer slightly": a 1-pt mouse-moved event and back, posted with `CGEvent`, only with Accessibility, same conditions as `activity`, never keyboard or clicks | X | activity | Amph 5.0 "Move the mouse cursor periodically" |
| `driveAlive` | Per external volume opt-in; tiny periodic write + `F_FULLFSYNC` to `/<volume>/.snaptic-keepalive`; interval 30–600 s (default 120); `PreventDiskIdle` while active; only during sessions unless "Even without a session" | O | — | Amph 1.6 |
| `history` | Local history (≤ 500 entries, 90 days), today/7-day totals, "Start Again", clear; never exported | S | — | Amph 1.10 statistics |
| `shortcuts` | Global hotkeys: Start/End default session (toggle), Toggle "display may sleep", Start preset 1–4, Pause automatic sessions; all unbound by default | S | — | Amph 1.10 |
| `commandLine` | `snaptic awake status|start|stop|extend|preset|pause` (§2.10); needs the host CLI switch (General) | S | — | Amph AppleScript 4 commands (equivalent surface) |

Always present (not flags): "Other apps keeping your Mac awake" list (`IOPMCopyAssertionsByProcess`, read on demand in Advanced › Display Information-style sheet "Sleep Status…"); "Closing the lid will put your Mac to sleep" line in the Awake menu when a session is active on a laptop not in desktop mode (`AppleClamshellCausesSleep`).

**Criterion kinds** (`AwakeCriterionKind`; availability per kind, no feature flags):

| Kind | Source (J) | API | TCC | Parity |
|---|---|---|---|---|
| `app` (running / frontmost) | AppMonitor | `NSWorkspace` launch/terminate/activate notifications | none | Amph 4.0 |
| `display` (any external, ignore built-in; a specific display; mirroring on) | DisplayPresence | `CGDisplayRegisterReconfigurationCallback`, `CGGetOnlineDisplayList`, `CGDisplayIsBuiltin`, `CGDisplayIsInMirrorSet`; specific display by salted `FingerprintRecord` | none | Amph 4.2, 4.1.5; replaces Displays `sleepPrevention` |
| `power` (on adapter / on battery / charging / battery ≥ N%) | PowerMonitor | `IOPSCopyPowerSourcesInfo`, `notify_register_dispatch(kIOPSNotifyPowerSource / PercentChange)` | none | Amph 5.0 |
| `schedule` (weekdays × start–end, overnight allowed) | Ticker (G) | wall clock; minute-boundary timer only while used; wake, clock and time-zone notifications | none | Amph 1.5/3.0 |
| `cpu` (system CPU ≥ N%, 10 s average) | CPUSampler | `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas, cached `mach_host_self()`, 5 s period while used | none | Amph 4.1.4 |
| `audio` (output playing / microphone in use) | AudioMonitor | `kAudioDevicePropertyDeviceIsRunningSomewhere` on default output / input, property listeners | none (no mic access, property only) [HW-9] | Amph 4.0 audio output |
| `idle` (no input for ≥ N min) | IdleSampler | `CGEventSourceSecondsSinceLastEventType(.combinedSessionState, anyInput)`, 10 s period while used | none | Amph 4.1.5 |
| `volume` (a volume is mounted) | VolumeMonitor | `NSWorkspace.didMount/didUnmount`, `volumeUUIDStringKey` | none (listing only) | Amph 4.0 |
| `usb` (a USB device is connected) | USBWatcher | `IOServiceAddMatchingNotification(IOUSBHostDevice)` first-match + terminated, iterators drained | none | Amph 4.0 |
| `network` (IP in subnet; on a remembered router; VPN connected) | NetworkMonitor | `SCDynamicStore` `State:/Network/Global/IPv4`, `State:/Network/Interface/*/IPv4`; router MAC from the routing table (`sysctl NET_RT_FLAGS`), salted hash only [HW-11]; VPN = `utun*/ipsec*/ppp*` with an address and primary | none | Amph IP, IPv6, VPN (5.0, 4.1); **no SSID** |
| `networkActivity` (C5) | NetworkMonitor | `getifaddrs` `if_data` byte deltas, 5 s period while used | none | Replaces "while downloading" |
| `bluetooth` (C6, Beta) | BluetoothPresence | CoreAudio device list with transport Bluetooth/BLE; IORegistry `IOHIDDevice` with `Transport == "Bluetooth"` (properties only, never opened) | none [HW-10] | Amph 4.0 Bluetooth (partial) |

### 1.2 Awake: Deferred (feasible later without breaking the rules)

| Item | Reason |
|---|---|
| "While a file is downloading" via the Downloads folder | Downloads-folder TCC under Snaptic's identity; C5 covers the use case |
| General Bluetooth devices via IOBluetooth | Bluetooth TCC and possible kill without a usage string |
| Lock the screen after inactivity | Only private `SACLockScreenImmediate` or spawning `pmset` (both banned outside Displays' PrivateDisplayAPI / HelperSpawner) |
| Screen-saver exceptions, per-trigger screen-saver delay | Needs measured behavior of assertions vs screen saver [HW-4] first |
| Sounds on start/end | Low value; adds options |
| App Intents / Shortcuts, AppleScript `sdef` | SwiftPM build can't process App Intents metadata; `sdef` needs bundle resources (`resources:` is banned) |
| Control Center / menu bar `ControlWidget` | Needs an app extension (entitlements, 26 SDK) |
| `expandedInterfaceDelegate` custom panel on 27 | 27 SDK only |
| Process-name criterion for faceless processes (`proc_listallpids`) | Useful for CLI agents; add after 0.3 with a polling budget |

### 1.3 Awake: Excluded (by design)

| Item | Reason |
|---|---|
| Closed-lid on battery (`pmset disablesleep`, sudoers rules, Power Protect, unprivileged clamshell SPI) | Root or SPI, persists after a crash, same-user exploitable, heat risk ([AP] §1.7, §3.3; [PA] §2) |
| Privileged helper, root, admin prompts, LaunchAgents/Daemons | Constraint |
| Turning Low Power Mode on/off | Needs root (`pmset -b lowpowermode`) |
| Wi-Fi SSID criterion | Location TCC + hardened-runtime location entitlement ([PA] §4) |
| DNS-server, Cisco-AnyConnect-specific VPN criteria | Brand-specific; generic VPN + subnet cover it |
| macOS notifications (`UNUserNotificationCenter`) | Snaptic uses ToastPresenter + menu state (0.2 §3.3) |
| `snaptic://` URL scheme | Any web page could fire it |
| Custom menu bar images, emoji icons | Curated template SF Symbols only |
| Insomnia lid-close actions (SIGSTOP apps, mute, keyboard backlight, App Nap writes into other apps' prefs), hotspot failover, tmux nudge, browser relaunch, `docker ps` | Invasive, run or inject code, network ([AP] §3.3) |
| Spawning `/usr/bin/caffeinate` | In-process assertions die with the process; spawning is banned outside HelperSpawner |
| Synthetic key events of any kind | Could type into the focused app |

### 1.4 Parity map (Amphetamine → Snaptic Awake)

| Amphetamine | Snaptic |
|---|---|
| Indefinite / duration / until time / extend / default-duration quick start | `sessions` + `presets`; quick start = header switch, hotkey, `awake start` |
| While app running (sandbox-limited) | `sessions` (whileApp) and `app` criterion; not sandboxed, so all regular apps |
| While file downloading | C5 `networkActivity` criterion (Deferred: folder watching) |
| Allow display sleep; toggle mid-session by hotkey | `AwakeDisplayPolicy`; "Display May Sleep" menu toggle; hotkey |
| Screen saver / screen-saver delay | Deferred ([HW-4]) |
| Closed-Display Mode | Excluded; menu explains the native route (external display + power) |
| Move cursor periodically | `activity` (default, no TCC) + `pointerNudge` (X, Accessibility) |
| Lock screen after inactivity | Deferred |
| End on low battery / adapter disconnect / manual sleep / FUS | `batteryGuard`, `sessions` behavior options |
| Triggers: unlimited, priority, names, AND/OR | `triggers` (≤ 32, order = priority, All/Any + per-criterion negation) |
| Criteria: displays, USB, Bluetooth, app, battery/power, IP, SSID, DNS, VPN, audio, drive, CPU, idle, schedule | All except SSID and DNS; Bluetooth partial (C6) |
| Re-activate a manually ended trigger session after a time | `resumeAfterManualEndMinutes` |
| Drive Alive per drive + interval | `driveAlive` |
| Menu bar icon styles, active/inactive images, time remaining, 12/24 h, seconds | `indicator` (curated families, outline vs fill, countdown, seconds, end time in the system's clock format) |
| ⌘-click quick start | Hotkey + header switch (status item clicks always open the menu on 14–27) |
| Notifications, sounds, reminders | Toasts ("5 minutes left", "ended: battery low") + menu state; no sounds |
| AppleScript, statistics, debug mode | CLI; `history`; Awake diagnostics in the shared report |

Insomnia → Snaptic: timed sessions and chips (`presets`), 30-day cap (same), battery/thermal floors (`batteryGuard`, `thermalGuard`), countdown in the bar (`indicator`), "extend" reminder (toast at 5 min left with **Extend 1 Hour**), sleep-disabled-by-another-process detection → "Other apps keeping your Mac awake". Everything pmset/journal/backstop-based is unnecessary: assertions die with the process ([PA] §1.2).

### 1.5 Settings and menu redesign scope

| In | Deferred | Excluded |
|---|---|---|
| SettingsUI component library (§4.1) used by every page | String Catalog localization (strings keep going through `L()`) | Custom window chrome, fake glass, custom title bars |
| New IA for General, Menu Bar, Window Switcher, Displays (+ sub-pages), Awake, Permissions, About (§4.2–4.4) | Liquid Glass APIs, `preferredImageVisibility` (26 SDK) | Tabs inside pages, nested sheets |
| Search (`.searchable(placement: .sidebar)`, static index, scroll-to-anchor highlight; covers Advanced sheets) | Settings deep links from outside (no URL scheme) | Popover/panel menus for status items |
| Live-update fixes A1–A11, B1–B3, C1–C2, M1 ([UA] §1) | | |
| Config migration with no setting lost (§4.6) | | |
| Menu redesign for all modules (§5), MenuKit, MenuSliderRow | | |
| Onboarding update: modules step adds Awake; one primary button location | | |
| Floating Displays panel restyled with the same row components | | |

---

## 2. Awake architecture

### 2.1 Shape (mirrors Displays, smaller)

```
AwakeModule (lead)            SnapticModule; owns AwakeConfig store, AwakeRuntimeState, AwakeStateStore
 └─ AwakeContext (lead)       services + registries + host services; built per start; services hold it weakly
     Services (refcounted by need, AwakeServiceID; J unless noted)
       assertions  AssertionManager (G)   the ONLY IOPMAssertionCreate*/Release caller in Snaptic (lint)
       power       PowerMonitor           IOPS notify, LPM, thermal, battery facts
       system      SystemEventsMonitor    sleep/wake, screens sleep/wake, lock/unlock, screensaver, FUS, clock, TZ, day change, lid
       apps        AppMonitor             running/frontmost bundle ids, app list for pickers
       displays    DisplayPresence        online displays as FingerprintRecords, mirroring
       usb         USBWatcher             IOUSBHostDevice matching
       volumes     VolumeMonitor          mounted volumes (uuid, name, eligibility for Drive Alive)
       audio       AudioMonitor           output/input running-somewhere
       cpu         CPUSampler             10 s average
       idle        IdleSampler            HID idle seconds
       network     NetworkMonitor         IPv4/IPv6 addresses, router hash, VPN, throughput
       bluetooth   BluetoothPresence      BT audio + BT HID presence (Beta)
       activity    ActivitySimulator      DeclareUserActivity / pointer nudge
       driveAlive  DriveAliveService      keep-alive writes on a private serial queue
     Controllers (one per AwakeControllerID; G unless noted)
       sessions    SessionController      manual session lifecycle, presets, arbitration, assertion plan
       guards      GuardsController       battery/thermal/LPM/sleep/FUS policies
       triggers    TriggerController      criterion facts → TriggerEngine.step → governing trigger
       activity    ActivityController (J) drives ActivitySimulator from runtime state
       driveAlive  DriveAliveController (J)
       indicator   IndicatorController    own status item, countdown, glyphs, menu (AwakeMenuBuilder)
       history     HistoryController      records ends, totals
       automation  AwakeAutomation        hotkeys + CLI verbs
```

Everything is `@MainActor` except `DriveAliveService`'s I/O queue and the C callbacks (IOKit, CoreAudio, SCDynamicStore, CG reconfiguration), which use `CallbackTarget` and hop with `MainActor.assumeIsolated` from main-queue delivery (`IONotificationPortSetDispatchQueue(port, .main)`, `AudioObjectAddPropertyListenerBlock(…, .main, …)`, `SCDynamicStoreSetDispatchQueue(store, .main)`, `notify_register_dispatch(…, .main)`). Timers are added in `.common` mode with ≥ 10% tolerance. No `static let shared` in Awake. EventLog category `.awake` (lead adds).

**Apply order** (same as Displays §3.6): resolve effective features → required services = `AwakeFeatureGraph.requiredServices(effective:criteria:needsApps:)` (features ∪ criterion kinds used by enabled triggers ∪ `apps` while a whileApp session runs or a picker is open) → stop emptied controllers → deactivate unneeded services (reverse) → activate needed services (in order) → start new controllers → notify the rest. A criterion source that isn't needed costs nothing: no notification ports, timers or listeners.

### 2.2 Kit ids and feature graph (lead, `SnapticKit/AwakeFeatureGraph.swift`)

```swift
package enum AwakeFeature: String, Codable, CaseIterable, Sendable {
    case sessions, presets, batteryGuard, thermalGuard, indicator
    case triggers, activity, pointerNudge, driveAlive, history, shortcuts, commandLine
}
package enum AwakeControllerID: String, Codable, CaseIterable, Sendable {
    case sessions, guards, triggers, activity, driveAlive, indicator, history, automation
}
package enum AwakeServiceID: String, Codable, CaseIterable, Sendable {
    case assertions, power, system, apps, displays, usb, volumes, audio, cpu, idle, network, bluetooth, activity, driveAlive
}

package struct AwakeFeatureSpec: Sendable {
    package let defaultState: FeatureDefault           // reuses Displays' enum
    package let beta: Bool
    package let requiresAll: [AwakeFeature]
    package let uses: Set<AwakeServiceID>
    package let controller: AwakeControllerID
    package let permissions: Set<Permission>
    package init(_ d: FeatureDefault, beta: Bool = false, all: [AwakeFeature] = [], uses: Set<AwakeServiceID> = [],
                 controller: AwakeControllerID, permissions: Set<Permission> = [])
}

package enum AwakeFeatureGraph {
    package static let specs: [AwakeFeature: AwakeFeatureSpec]   // table below; total (tested)
    package static func spec(_ f: AwakeFeature) -> AwakeFeatureSpec
    package static func rawState(_ f: AwakeFeature, in raw: [AwakeFeature: Bool]) -> Bool
    /// Same rules as FeatureGraph.resolve: raw − kill switches − unavailable − Safe Mode removals, closed over requirements.
    package static func resolve(raw: [AwakeFeature: Bool], killSwitches: Set<AwakeFeature>, safeMode: Bool,
                                unavailable: Set<AwakeFeature>) -> Set<AwakeFeature>
    package static func enabling(_ f: AwakeFeature, raw: [AwakeFeature: Bool]) -> [AwakeFeature: Bool]
    package static let safeModeRemoves: Set<AwakeFeature> = [.triggers, .pointerNudge, .driveAlive, .activity]
    package static func services(of kind: AwakeCriterionKind) -> Set<AwakeServiceID>
    package static func requiredServices(effective: Set<AwakeFeature>, criteria: Set<AwakeCriterionKind>,
                                         needsApps: Bool) -> Set<AwakeServiceID>
    package static let activationOrder: [AwakeServiceID]  // assertions, power, system, then sources, activity, driveAlive
}
```

| Feature | Def | Requires | Uses | Controller | Permission |
|---|---|---|---|---|---|
| sessions | always | — | assertions, power, system | sessions | — |
| presets | always | sessions | — | sessions | — |
| batteryGuard | standard | — | power | guards | — |
| thermalGuard | always | — | power | guards | — |
| indicator | standard | — | — | indicator | — |
| triggers | optIn | sessions | (per criterion) | triggers | — |
| activity | optIn | sessions | activity, idle, system | activity | — |
| pointerNudge | experimental | activity | activity | activity | accessibility |
| driveAlive | optIn | — | volumes, driveAlive | driveAlive | — (Removable Volumes TCC prompt on first write; not a `Permission` case) |
| history | standard | sessions | — | history | — |
| shortcuts | standard | sessions | — | automation | — |
| commandLine | standard | sessions | — | automation | — |

Kill switches: persistent-domain Bool keys `Awake.disable.<feature>` read once per start (same rule as Displays R5.4). Safe Mode keeps manual sessions and guards (they are safe), removes triggers, activity, nudge, Drive Alive.

`KitModules.swift` (lead) additions: `ModuleID.awake` (start order: windowSwitcher, displays, awake), `EventCategory.awake`, `AwakeActionID: RawRepresentable` (open, like `DisplayActionID`), `AwakeCriterionKind` (here so the graph can reference it):

```swift
package enum AwakeCriterionKind: String, Codable, CaseIterable, Sendable {
    case app, display, power, schedule, cpu, audio, idle, volume, usb, network, networkActivity, bluetooth
}
```

### 2.3 Session model (G, `SnapticKit/AwakeSession.swift`)

```swift
package enum AwakeDisplayPolicy: String, Codable, CaseIterable, Sendable {
    case keepOn            // PreventUserIdleDisplaySleep
    case maySleep          // PreventUserIdleSystemSleep; display follows System Settings
    case keepOnWhileActive // keepOn until HID idle ≥ displayIdleMinutes, then maySleep; back on input
}
package enum AwakeActivityMode: String, Codable, CaseIterable, Sendable { case off, declare, nudge }

package struct AwakeSessionOptions: Codable, Equatable, Sendable {
    package var display: AwakeDisplayPolicy        // .keepOn
    package var displayIdleMinutes: Int            // 1...240, default 30
    package var activity: AwakeActivityMode        // .off; .nudge needs pointerNudge effective, else acts as .declare
    package init(display: AwakeDisplayPolicy = .keepOn, displayIdleMinutes: Int = 30, activity: AwakeActivityMode = .off)
    // lossy decode per field; sanitized() clamps minutes
}

package enum AwakeSessionKind: Equatable, Sendable {
    case indefinite
    case duration(seconds: Int)            // 60 ... AwakeClock.maxSessionSeconds
    case until(unixTime: Double)           // absolute instant
    case whileApp(bundleID: String)        // validated reverse-DNS, ≤ 255 bytes
}
// Codable as {"type":"duration","seconds":5400}; unknown type → decode fails → session dropped (lossy at the container).

package enum AwakeSessionSource: String, Codable, Sendable { case menu, hotkey, commandLine, settings, launch, restored }

package struct AwakeSession: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var kind: AwakeSessionKind
    package var options: AwakeSessionOptions
    package var presetID: StableID?
    package var source: AwakeSessionSource
    package var startedAt: Double                 // unix seconds
    package var endsAt: Double?                   // wall clock; nil = no limit (indefinite, whileApp)
    package var continuousDeadline: Double?       // seconds of continuous clock (duration kind only)
    package var bootSession: String               // kern.bootsessionuuid at start; mismatch = expired
    package init(...)
}

package enum AwakeEndReason: String, Codable, CaseIterable, Sendable {
    case user, timeUp, appQuit, replaced, triggerEnded, batteryLow, batteryUnreadable, adapterDisconnected,
         lowPowerMode, thermal, systemSleep, userSwitch, moduleStopped, safeMode, reboot, assertionFailed
}

/// What the indicator, menu, Settings status row and CLI show (no app names in `reasonKey`).
package enum AwakeGoverning: Equatable, Sendable {
    case none
    case manual(AwakeSession)
    case trigger(id: StableID, index: Int, options: AwakeSessionOptions, since: Double)
}
```

**Time** (G, `SnapticKit/AwakeClock.swift`):

```swift
package struct ClockNow: Equatable, Sendable {
    package var wall: Double; package var continuous: Double; package var bootSession: String
}
package enum AwakeClock {
    package static let maxSessionSeconds = 30 * 86_400          // Insomnia's cap; extensions included
    package static func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions, presetID: StableID?,
                              source: AwakeSessionSource, now: ClockNow, id: StableID) -> AwakeSession
    /// nil = no limit; ≤ 0 = expired. Duration sessions use the continuous deadline in the same boot.
    package static func remaining(_ s: AwakeSession, now: ClockNow) -> Double?
    package static func isExpired(_ s: AwakeSession, now: ClockNow) -> Bool   // also true when bootSession differs
    /// Indefinite stays indefinite; whileApp gains no limit; the result never exceeds maxSessionSeconds from start.
    package static func extended(_ s: AwakeSession, by seconds: Int, now: ClockNow) -> AwakeSession
    /// Next occurrence of hh:mm strictly after now (today or tomorrow), in `calendar`'s time zone.
    package static func untilTime(hour: Int, minute: Int, after now: Date, calendar: Calendar) -> Double
}
package enum AwakeCountdown {
    package enum Style: String, Codable, Sendable { case minutes, seconds }
    /// minutes: ≥1 h "1:42", 1–59 min "42m", <1 min "<1m" (rounded up). seconds: "1:42:05" / "42:05".
    package static func short(_ remaining: Double, style: Style) -> String
    /// "1 hour 42 minutes remaining" (VoiceOver, tooltip), "less than a minute remaining".
    package static func spoken(_ remaining: Double) -> String
    /// Seconds until `short` changes (minute boundary or 1 s), so the indicator never redraws needlessly.
    package static func nextChange(_ remaining: Double, style: Style) -> Double
}
package enum AwakeDurationGrammar {
    /// CLI and Custom… field: "90", "90m", "1h30m", "2h", "1.5h", "until 17:30", "until 5:30pm", "indefinite", "forever".
    package static func parse(_ words: [String], now: Date, calendar: Calendar) -> AwakeSessionKind?
}
```

Clock rules (normative):
- Duration: `continuousDeadline = continuous + seconds` (Swift side reads `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)`, which advances during sleep) and `endsAt = wall + seconds` for display. Wall-clock changes don't move a duration session; time asleep counts (N2).
- Until: an absolute instant chosen in the current zone; a time-zone change keeps the instant and re-renders "Until 5:00 PM" in the new zone; `NSSystemClockDidChange` re-evaluates expiry immediately.
- After a reboot (`kern.bootsessionuuid` differs) every persisted session is expired with reason `.reboot`; triggers re-evaluate from scratch.

### 2.4 Assertions and arbitration (G)

**Kit** (`SnapticKit/AwakeArbiter.swift`):

```swift
package enum AwakeAssertionType: String, Sendable { case none, system, display }
package struct AwakeAssertionPlan: Equatable, Sendable {
    package var type: AwakeAssertionType
    package var name: String                // fixed vocabulary: "Snaptic: keeping your Mac awake"
    package var details: String             // fixed vocabulary, no user strings: "manual, duration" / "automatic, trigger 2: display"
    package var timeoutSeconds: Int?        // remaining + timeoutGrace when every governing limit is timed
    package var preventDiskIdle: Bool       // Drive Alive writing
}
package struct AwakeArbiterInput: Equatable, Sendable {
    package var governing: AwakeGoverning
    package var remaining: Double?
    package var screenLocked: Bool
    package var consoleActive: Bool              // false while another user is on console (FUS)
    package var userIdleSeconds: Double?         // only sampled for keepOnWhileActive
    package var keepDisplayOnWhileLocked: Bool   // C1 Advanced option
    package var driveAliveWriting: Bool
    package var guardsHold: Bool                 // a guard ended the session and is blocking restarts
    package init(...)
}
package enum AwakeArbiter {
    package static let timeoutGraceSeconds = 15
    package static func plan(_ input: AwakeArbiterInput) -> AwakeAssertionPlan
    /// manual > highest-priority active trigger > none (N3).
    package static func governing(manual: AwakeSession?, top: (id: StableID, index: Int, options: AwakeSessionOptions, since: Double)?) -> AwakeGoverning
}
```

Plan rules (tested): none → `.none`; `.keepOn` → `.display`, downgraded to `.system` when `screenLocked && !keepDisplayOnWhileLocked` (C1) or `!consoleActive`; `.maySleep` → `.system`; `.keepOnWhileActive` → `.display` while `userIdleSeconds < displayIdleMinutes·60`, else `.system`; timeout = `ceil(remaining) + 15` for manual duration/until, nil otherwise; `preventDiskIdle` = `driveAliveWriting`.

**AssertionManager** (G, `Awake/Core/AssertionManager.swift`) holds at most one sleep assertion and one `PreventDiskIdle` assertion:

```swift
@MainActor final class AssertionManager: AwakeServiceLifecycle {
    private(set) var current: AwakeAssertionPlan = .none     // static let none on the Kit type
    private(set) var lastError: Int32?
    /// Idempotent. Type change → create the new one first, then release the old one (no gap).
    /// Same type → IOPMAssertionSetProperty for Details / TimeoutSeconds (re-arm on extend) [HW-2].
    @discardableResult func apply(_ plan: AwakeAssertionPlan) -> Bool
    func releaseAll()
    /// Our assertion vanished (timeout fired, powerd restarted): IOPMCopyAssertionsByProcess check
    /// on wake, on `com.apple.system.powermanagement.assertions.timeout`, and every 5 min while active.
    func verify() -> Bool
}
```
Creation uses `IOPMAssertionCreateWithProperties` with `AssertType`, `AssertName`, `Details`, `AssertLevel = 255`, and when timed `TimeoutSeconds` + `TimeoutAction = "TimeoutActionRelease"` ([PA] §1.2, §1.5). String literals, no CFSTR macros. A failed create → session ends with `.assertionFailed` and toast "Snaptic couldn't keep your Mac awake. Try again, or restart Snaptic." The timeout is a **backstop** only: the app ends sessions itself at `remaining == 0`, 15 s before powerd would.

### 2.5 Session lifecycle (G, `SessionController`)

```swift
@MainActor final class SessionController: AwakeFeatureController {
    func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions?, presetID: StableID?, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    func startPreset(_ id: StableID, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    func startDefault(source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    func extend(by seconds: Int) -> Result<AwakeSession, AwakeRefusal>
    func setDisplayPolicy(_ p: AwakeDisplayPolicy)          // current governing session; trigger sessions: until it ends
    func end(_ reason: AwakeEndReason)                       // manual session; trigger session → TriggerController.manualEnd
    func toggleDefault(source: AwakeSessionSource)           // header switch, hotkey
}
package enum AwakeRefusal: Error, Equatable, Sendable {
    case guardActive(AwakeEndReason)  // "Battery is below 20%." — offers "Start Anyway" (UI only, once per session)
    case unavailable(String)          // feature off, Safe Mode
    case invalid                      // bad duration / app not running
    case notAllowedFromCLI            // nudge presets
}
```

Rules:
- At most one manual session. Starting a new one replaces the old (history entry `.replaced`). Starting while a trigger governs makes the manual session govern; when it ends, the trigger (if still active) governs again — no gap: the plan is recomputed in the same turn.
- A tick (`Timer`, `.common`, fires at `AwakeCountdown.nextChange` or at expiry, whichever is earlier, tolerance 10%) recomputes `remaining`; at ≤ 0 the session ends `.timeUp`. Ticks never drive correctness alone: expiry is also checked on wake, clock change, unlock, menu open and every arbitration.
- **5-minute reminder**: when a manual timed session that ran ≥ 15 min reaches 5 min left, toast "Awake ends in 5 minutes." with action **Extend 1 Hour** (toast bound to the session's lifetime).
- **End toast** for every non-user end: "Awake ended: battery is below 20%." / "…: Xcode quit." (app names appear only in local UI, never in logs or CLI).
- whileApp: ends `.appQuit` when no running application has the bundle id (checked on terminate notifications and on every arbitration); refuses to start if the app isn't running.
- **Persistence**: the manual session (if any), trigger suppressions and the pause-until are written to `SnapticAwakeStateV1` (ConfigStore of `AwakeRuntimeSnapshot`, Kit) on change only. On start (launch, relaunch, update, re-enable), `resumeAfterRestart` (default on) restores a manual session that is not expired in the same boot; source becomes `.restored`. A crash therefore loses nothing but the time Snaptic was down (assertions die with the process; [PA] §1.2).
- **Start at launch** (Advanced, default none): a preset id started once per app launch, not per module re-enable.
- **Module stop / quit**: `stop()` releases all assertions synchronously, ends the session in history as `.moduleStopped` (but keeps the persisted snapshot when the app is quitting, so a relaunch resumes it; disabling the module clears it).

### 2.6 Guards (G, Kit `SnapticKit/AwakeGuards.swift`, `GuardsController`)

```swift
package enum ThermalLevel: Int, Codable, Sendable, Comparable { case nominal, fair, serious, critical }
package struct PowerFacts: Equatable, Sendable {
    package var hasBattery: Bool
    package var onAC: Bool
    package var percent: Int?            // nil = unreadable
    package var charging: Bool
    package var lowPowerMode: Bool
    package var thermal: ThermalLevel
    package init(...)
}
package struct AwakeGuardsConfig: ConfigModel {
    package var batteryFloorEnabled: Bool        // true
    package var batteryFloor: Int                // 20; 5...50, step 5
    package var endOnAdapterDisconnect: Bool     // false
    package var endOnLowPowerMode: Bool          // false
    package var endOnSeriousHeat: Bool           // false
}
package struct GuardMemory: Equatable, Sendable {      // carried between evaluations
    package var unreadableReads: Int
    package var holding: AwakeEndReason?               // blocks trigger starts until cleared
    package var heldSince: Double?
    package var warnedSerious: Bool
}
package enum AwakeGuardVerdict: Equatable, Sendable { case allow, end(AwakeEndReason), warn(AwakeEndReason) }
package enum AwakeGuards {
    package static let hysteresisPercent = 5
    package static let thermalCooldownSeconds: Double = 600
    package static func evaluate(_ now: PowerFacts, previous: PowerFacts?, config: AwakeGuardsConfig,
                                 memory: GuardMemory, time: Double, active: Bool) -> (AwakeGuardVerdict, GuardMemory)
}
```
Rules: desktops (`!hasBattery`) skip battery rules; on AC battery rules don't apply; `percent < floor` on battery → end `.batteryLow`; two consecutive unreadable reads on battery → `.batteryUnreadable`; AC → battery transition with `endOnAdapterDisconnect` → `.adapterDisconnected`; LPM on with `endOnLowPowerMode` → `.lowPowerMode`; `.critical` → end `.thermal` regardless of settings (thermalGuard is always on) and hold for 10 min; `.serious` → warn once per episode, end if `endOnSeriousHeat`. Holding clears when battery ≥ floor + 5 or AC, LPM off, thermal ≤ fair for 10 min. **Guards apply to every source** (manual, trigger, CLI, restored). The UI's one-shot **Start Anyway** (after a `.guardActive` refusal, user-initiated only, never CLI/trigger) suspends the battery/LPM guard for that session; thermal critical is never overridable.

System behavior options (Kit `AwakeBehavior`, part of `AwakeSessionsConfig`): `endOnSystemSleep` (false; any sleep while our assertion holds is lid/Apple-menu/low-battery/thermal, so this is Amphetamine's "end when the Mac is put to sleep manually"), `endOnUserSwitch` (false), `keepDisplayOnWhileLocked` (false, C1), `resumeAfterRestart` (true), `startAtLaunch: StableID?` (nil).

### 2.7 Triggers (G engine + Kit; J sources)

**Kit model** (`SnapticKit/AwakeTriggers.swift`):

```swift
package enum TriggerMatch: String, Codable, CaseIterable, Sendable { case all, any }
package struct WeekdaySet: OptionSet, Codable, Hashable, Sendable { package let rawValue: UInt8 }   // bit 0 = Sunday
package enum DisplayMatch: Equatable, Sendable {
    case anyExternal                                  // ≥ 1 online non-built-in display
    case specific(record: FingerprintRecord, name: String)  // salted tiers only; name sanitized ≤ 64
    case mirroring
}
package enum PowerCondition: Equatable, Sendable { case onAdapter, onBattery, charging, batteryAtLeast(Int) }
package enum AudioCondition: String, Codable, Sendable { case outputActive, microphoneActive }
package enum NetworkCondition: Equatable, Sendable {
    case subnet(cidr: String)                          // IPv4 or IPv6, validated
    case router(hash: String, label: String)           // salted SHA-256 of the router MAC
    case vpnConnected
}
package enum BluetoothMatch: Equatable, Sendable { case audio(uidHash: String, name: String), input(hash: String, name: String), anyAudio }
package enum AwakeCriterion: Equatable, Sendable {
    case app(bundleID: String, name: String, frontmost: Bool)
    case display(DisplayMatch)
    case power(PowerCondition)
    case schedule(days: WeekdaySet, startMinute: Int, endMinute: Int)   // minutes since midnight; end ≤ start = overnight
    case cpuAbove(percent: Int)                                          // 5...100
    case audio(AudioCondition)
    case idle(atLeastMinutes: Int)                                       // 1...480
    case volumeMounted(uuid: String, name: String)
    case usbDevice(vendor: Int, product: Int, serialHash: String?, name: String)
    case network(NetworkCondition)
    case networkActivity(atLeastKBps: Int)                               // 10...1_000_000
    case bluetooth(BluetoothMatch)
    package var kind: AwakeCriterionKind
}
package struct AwakeCriterionEntry: Codable, Equatable, Sendable {
    package var criterion: AwakeCriterion; package var negated: Bool
}   // JSON {"kind":"app","negated":false,"bundleID":…}; unknown kind or bad payload → entry dropped (lossy array)

package struct AwakeTrigger: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var name: String                     // ≤ 64 scalars, TextSanitizer; empty → generated summary
    package var enabled: Bool
    package var match: TriggerMatch
    package var criteria: [AwakeCriterionEntry]  // 1...8; a trigger with 0 valid criteria is disabled by sanitized()
    package var options: AwakeSessionOptions
    package var startDelaySeconds: Int           // 0...3600; cpu/networkActivity default 60
    package var endDelaySeconds: Int             // 0...3600; default 30 (hysteresis)
    package var resumeAfterManualEndMinutes: Int?   // nil = when the condition next becomes true
    package static let maxTriggers = 32, maxCriteria = 8
}
package struct AwakeTriggersConfig: ConfigModel {
    package var triggers: [AwakeTrigger]         // order = priority
    package var pausedUntil: Double?             // "Pause automatic sessions"
}
```

**Facts and evaluation** (`SnapticKit/AwakeTriggerEngine.swift`):

```swift
package struct DisplayFact: Equatable, Sendable { package var record: FingerprintRecord; package var isBuiltin: Bool }
package struct USBFact: Equatable, Sendable { package var vendor: Int; package var product: Int; package var serialHash: String? }
package struct NetworkFacts: Equatable, Sendable { package var addresses: [String]; package var routerHashes: Set<String>; package var vpn: Bool }
package struct BluetoothFact: Equatable, Sendable { package var audioUIDHashes: Set<String>; package var inputHashes: Set<String> }
/// nil = the source isn't running or hasn't produced a value yet ("unknown").
package struct CriterionFacts: Equatable, Sendable {
    package var runningApps: Set<String>?; package var frontmostApp: String??
    package var displays: [DisplayFact]?; package var mirroring: Bool?
    package var power: PowerFacts?
    package var minuteOfWeek: Int?               // 0..<10080, local time
    package var cpuPercent: Double?; package var audioOutput: Bool?; package var microphone: Bool?
    package var idleSeconds: Double?; package var volumes: Set<String>?; package var usb: [USBFact]?
    package var network: NetworkFacts?; package var throughputKBps: Double?; package var bluetooth: BluetoothFact?
    package init()
}
package struct TriggerRuntime: Codable, Equatable, Sendable {
    package var trueSince: Double?; package var falseSince: Double?; package var active: Bool
    package var suppressedUntil: Double?; package var suppressedUntilFalse: Bool
}
package enum TriggerEngine {
    /// true / false / nil (unknown). Negation of unknown stays unknown.
    package static func holds(_ entry: AwakeCriterionEntry, facts: CriterionFacts) -> Bool?
    /// all: every entry true (unknown → false). any: some entry true (unknowns ignored).
    package static func condition(_ t: AwakeTrigger, facts: CriterionFacts) -> Bool
    /// Advances hysteresis for every trigger and returns the governing candidate (first active in order).
    package static func step(_ triggers: [AwakeTrigger], facts: CriterionFacts, now: Double,
                             state: [StableID: TriggerRuntime], paused: Bool, guardsHold: Bool)
        -> (state: [StableID: TriggerRuntime], top: (id: StableID, index: Int)?)
    /// The user ended a trigger session: suppress per resumeAfterManualEndMinutes.
    package static func manualEnd(_ t: AwakeTrigger, runtime: TriggerRuntime, now: Double) -> TriggerRuntime
    package static func requiredKinds(_ triggers: [AwakeTrigger]) -> Set<AwakeCriterionKind>
    /// Seconds until a schedule criterion can change (for the Ticker), nil if none.
    package static func nextScheduleChange(_ triggers: [AwakeTrigger], minuteOfWeek: Int, secondsIntoMinute: Double) -> Double?
    /// Sentence for list rows: "When Xcode is open and the power adapter is connected".
    package static func summary(_ t: AwakeTrigger) -> String
}
```

Engine rules (tested, normative): a trigger becomes active when its condition has held for `startDelaySeconds` and inactive when false for `endDelaySeconds`; disabled, suppressed, paused or guard-held triggers are never active (their hysteresis still advances so they resume correctly); the governing trigger is the first active one in list order (priority); a priority change takes effect at the next step without ending the session if the top stays active; facts are recomputed and `step` runs on every source change (coalesced to one run per main-queue turn) plus the Ticker (schedule boundaries, hysteresis deadlines — the engine returns the next deadline); a wake runs `step` only after a 5 s settle so displays, power and network sources reread.

**Specific display matching** (replaces Displays' per-display `preventSleep`): `DisplayPresence` builds a `FingerprintRecord` per online display via B's `DisplayIdentity.record(for:salt:)` from CG facts (vendor, model, serial, UUID via `CGDisplayCreateUUIDFromDisplayID`, built-in) — tiers t2, t3, t5 — and matches stored records with `Fingerprint.match` (higher stored tiers that we can't compute don't conflict). Awake therefore works with the Displays module off. The display picker in the trigger editor shows `NSScreen.localizedName` (or the Displays custom name when Displays runs, read from `DisplaysConfig.perDisplay[key].identity.customName`, read-only).

**Router and USB hashes**: SHA-256(`SnapticAwakeSalt` ‖ normalized value), salt = 32 random bytes in its own persistent-domain key, created on first use, never exported (same rules as `SnapticDisplaySalt`, R5.7). Labels ("Home", "Desk dock") are user-typed.

### 2.8 Criterion sources (J)

Each source conforms to:

```swift
@MainActor protocol CriterionSource: AwakeServiceLifecycle {
    static var kinds: Set<AwakeCriterionKind> { get }
    /// Writes this source's fields into the facts (nil while not ready).
    func contribute(to facts: inout CriterionFacts)
    var onChange: (@MainActor () -> Void)? { get set }      // TriggerController coalesces
}
@MainActor protocol AwakeServiceLifecycle: AnyObject {
    func activate(_ context: AwakeContext, lifetime: Lifetime)   // idempotent
    func deactivate()                                            // idempotent; releases ports, listeners, timers
}
```

| Source | Period / events | Budget | Notes |
|---|---|---|---|
| PowerMonitor | `kIOPSNotifyPowerSource`, `kIOPSNotifyPercentChange`, `NSProcessInfoPowerStateDidChange`, `thermalStateDidChangeNotification` | events only | Always active with `sessions` (guards need it). Exposes `@Published var facts: PowerFacts` |
| SystemEventsMonitor | `NSWorkspace` will/didSleep, screensDidSleep/Wake, sessionDidResign/BecomeActive; distributed `com.apple.screenIsLocked/Unlocked`, `com.apple.screensaver.didstart/didstop`; `NSSystemClockDidChange`, `NSSystemTimeZoneDidChange`, `NSCalendarDayChanged`; lid via `IOPMrootDomain` interest (`AppleClamshellState`, `AppleClamshellCausesSleep`, [PA] §2) | events only | Initial lock state from `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` |
| AppMonitor | launch/terminate/activate notifications | events only | Regular + accessory apps; bundle ids only; picker list sorted by name, Snaptic excluded |
| DisplayPresence | `CGDisplayRegisterReconfigurationCallback` (CallbackTarget), debounced 1 s | events only | Removes callback in `deactivate` |
| USBWatcher | first-match + terminated notifications on `IOUSBHostDevice` | events only | Iterators drained at arm; serial hashed immediately, raw never stored |
| VolumeMonitor | didMount / didUnmount / willUnmount | events only | Also used by Drive Alive (eligibility, §2.9) |
| AudioMonitor | property listeners on default output/input `DeviceIsRunningSomewhere` + default-device change | events only | No input stream is ever opened |
| CPUSampler | 5 s timer; 10 s window average | ~10 µs/sample | `host_statistics` tick deltas; cached host port |
| IdleSampler | 10 s timer (5 s while `keepOnWhileActive` or activity runs) | trivial | Also feeds the arbiter |
| NetworkMonitor | `SCDynamicStore` notifications for IPv4/IPv6 global + interface keys; router hash re-read on change; throughput 5 s timer only when `networkActivity` used | events + 5 s | Read-only; no sockets; ARP/route read via `sysctl` [HW-11] |
| BluetoothPresence (Beta) | CoreAudio device-list listener; `IOServiceAddMatchingNotification(IOHIDDevice)` filtered by `Transport` | events only | Never opens a HID device (Input Monitoring) [HW-10] |

### 2.9 Activity simulation and Drive Alive (J)

**ActivitySimulator** (`Awake/Sources/ActivitySimulator.swift`): the only file allowed to call `IOPMAssertionDeclareUserActivity` and `CGEvent(...).post` (lint).

```swift
@MainActor final class ActivitySimulator: AwakeServiceLifecycle {
    enum Mode: Equatable { case off, declare(interval: TimeInterval), nudge(interval: TimeInterval) }
    func setMode(_ mode: Mode)                 // ActivityController computes from runtime + policy
    private(set) var lastNudge: Date?
}
package enum ActivityPolicy {   // Kit, J, tested
    /// Nudge or declare only if: session governs with activity ≠ off, screen unlocked, no screensaver,
    /// console active, displays awake, userIdle ≥ interval, switcher not visible, and (nudge) Accessibility granted.
    package static func shouldAct(_ s: ActivityInputs) -> Bool
    package static let intervalRange: ClosedRange<Int> = 30...600   // default 60 s
}
```
`declare` calls `IOPMAssertionDeclareUserActivity("Snaptic: activity", kIOPMUserActiveLocal, &id)` reusing `id`. It turns the display on ([PA] §1.4), so it never runs while the displays are asleep. `nudge` posts one `mouseMoved` of +1 pt then −1 pt at the current location via `.cghidEventTap`, with `eventSourceUserData = 0x534E5054` ('SNPT') so Snaptic's own taps (switcher hover-select) ignore it; checked with `CGPreflightPostEventAccess()` before every post; never posts key, click or scroll events (lint bans `keyboardEventSource`, `mouseEventSource:` with button-down types in Awake). Copy (Settings): "Tells macOS you're active, so the screen saver and idle lock don't start. Chat apps may still show you as away." / nudge: "Moves the pointer by one point and back. Needs Accessibility. Your organization's policies may not allow this."

**DriveAliveService** (`Awake/Sources/DriveAliveService.swift`):

```swift
@MainActor final class DriveAliveService: AwakeServiceLifecycle {
    struct VolumeState: Equatable { let uuid: String; let name: String; var lastWrite: Date?; var lastError: String? }
    @Published private(set) var volumes: [VolumeState]
    func setTargets(_ uuids: Set<String>, interval: TimeInterval)   // writes start/stop per volume
    func removeKeepAliveFile(uuid: String)                          // when the user turns a volume off
}
package enum DriveAlivePolicy {   // Kit, J, tested
    package struct VolumeFacts: Equatable, Sendable {
        package var isInternal, isRootFileSystem, isReadOnly, isLocal, isDiskImage, isTimeMachine, isBrowsable: Bool
        package var fileSystem: String
    }
    package static func isEligible(_ v: VolumeFacts) -> Bool   // external, local, writable, browsable, not system/DMG/TM
    package static let fileName = ".snaptic-keepalive"
    package static let intervalRange: ClosedRange<Int> = 30...600
}
```
Write procedure on a private serial `DispatchQueue(label: "snaptic.drivealive", qos: .utility)`: resolve the volume URL from the current mount list (never from config), `open(root/.snaptic-keepalive, O_WRONLY|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK, 0600)`, `fstat` → regular file, owner = `getuid()`, `st_nlink == 1`, size ≤ 64; write 8 bytes (UInt64 timestamp) at offset 0, `ftruncate(8)`, `fcntl(F_FULLFSYNC)`, close; result hops to main. Any check failure → that volume is skipped and the row shows "Can't keep this drive awake" with the reason; no retry until remount. Stop on `willUnmount` (before eject). The first write triggers the Removable Volumes prompt; Info.plist gets `NSRemovableVolumesUsageDescription` = "Snaptic writes a tiny hidden file to the drives you choose so they don't spin down." (lead). Network volumes are never eligible.

### 2.10 Automation (G, `AwakeAutomation`)

Hotkeys (`AwakeActionID`, owner "Awake", via `GlobalHotkeys`, all unbound by default): `awake.toggle`, `awake.displayMaySleep`, `awake.preset1…4`, `awake.pauseAutomatic`.

CLI verbs (registered only while `commandLine` is effective and the host CLI is on):

| Verb | Policy | offOnly | Behavior |
|---|---|---|---|
| `awake status` | read | — | `inactive` or `active\tmanual|automatic\t<kind>\t<display policy>\t<ISO end or ->\t<remaining s>`; `--json` object; no app names, trigger *numbers* only |
| `awake start [<duration grammar>] [display-may-sleep]` | low | false | `AwakeDurationGrammar`; no argument = default preset; refused (exit 4) if the default preset uses `nudge`; guards apply (exit 4 with reason) |
| `awake preset <n|name>` | low | false | Refused if the preset uses `nudge` |
| `awake extend <duration>` | low | false | Manual sessions only |
| `awake stop` | low | true | Ends the manual session; a trigger session is suppressed as a manual end |
| `awake pause [<duration>]` | low | true | Pauses automatic sessions (default 1 h, ≤ 24 h) |

Never via CLI: editing triggers, presets, guards, Drive Alive volumes, activity mode, resuming automatic sessions, turning features on. The existing protected list in `ControlCommandRegistry` replaces "sleep prevention" with "Awake settings".

### 2.11 Runtime state, contracts, module (lead)

```swift
// Awake/AwakeRuntimeState.swift (lead)
@MainActor final class AwakeRuntimeState: ObservableObject {
    @Published var moduleState: ModuleState = .stopped
    @Published var effectiveFeatures: Set<AwakeFeature> = []
    @Published var availability: [AwakeFeature: FeatureAvailability] = [:]
    @Published var governing: AwakeGoverning = .none
    @Published var remaining: Double?            // updated on countdown changes only
    @Published var assertion: AwakeAssertionType = .none
    @Published var power: PowerFacts?
    @Published var guardHold: AwakeEndReason?
    @Published var lastEnd: (reason: AwakeEndReason, at: Date)?   // menu/Settings status line
    @Published var triggers: [StableID: TriggerRuntime] = [:]
    @Published var activityActive = false
    @Published var drives: [DriveAliveService.VolumeState] = []
    @Published var lidWillSleep: Bool?          // nil = no lid
    func isEffective(_ f: AwakeFeature) -> Bool
    func reset()
}

// Awake/AwakeContracts.swift (lead): protocols only
@MainActor protocol AwakeFeatureController: AnyObject {
    static var id: AwakeControllerID { get }
    init()
    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability
    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>)
    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>)
    func configDidChange(from old: AwakeConfig, to new: AwakeConfig)
    func stop()
}
protocol AwakeServiceLifecycle   // §2.8
protocol CriterionSource         // §2.8

// Awake/AwakeContext.swift (lead): services (one per AwakeServiceID) + controllers' shared registries
@MainActor final class AwakeContext {
    let assertions: AssertionManager, power: PowerMonitor, system: SystemEventsMonitor, apps: AppMonitor
    let displays: DisplayPresence, usb: USBWatcher, volumes: VolumeMonitor, audio: AudioMonitor
    let cpu: CPUSampler, idle: IdleSampler, network: NetworkMonitor, bluetooth: BluetoothPresence
    let activity: ActivitySimulator, driveAlive: DriveAliveService
    let config: ConfigStore<AwakeConfig>, state: ConfigStore<AwakeRuntimeSnapshot>, history: ConfigStore<AwakeHistory>
    let runtime: AwakeRuntimeState
    let sessions: SessionController, triggers: TriggerController   // controllers other controllers call
    // host: safeMode, hotkeys, commands, toasts, permissions, lifetime, requestMenuRebuild, openSettings, statusItems
    func service(_ id: AwakeServiceID) -> any AwakeServiceLifecycle
    func source(for kind: AwakeCriterionKind) -> any CriterionSource
}
```
`AwakeModule` (lead) follows `DisplaysModule` line by line (resolve, apply order, kill switches, config sink with one main-queue hop, `stop()` sync and idempotent: controllers reverse, services reverse, `assertions.releaseAll()` last-resort, flush stores). It also implements `ConfigStore.onExternalChange` protection (§3.5).

### 2.12 Behavior across system events (normative)

| Event | Behavior |
|---|---|
| Snaptic crash / force quit | powerd releases the assertion on process exit ([PA] §1.2). Nothing else to undo (Drive Alive leaves an 8-byte hidden file). Relaunch in the same boot resumes the manual session. |
| System sleep (lid, Apple menu, low battery, thermal) | Assertions don't prevent it. `willSleep`: if `endOnSystemSleep`, end `.systemSleep`; stop activity and Drive Alive writes. `didWake`: recompute remaining (continuous clock), end expired sessions, re-apply the plan, verify the assertion, triggers step after 5 s settle. |
| Lid closed on battery, not desktop mode | Mac sleeps. When a session is active the Awake menu shows "Closing the lid will put your Mac to sleep. To keep it awake with the lid closed, connect power and an external display." |
| Clock change | Until-sessions re-evaluated now; duration sessions unaffected; schedules re-evaluated. |
| Time-zone change | Until instants kept, labels re-rendered; schedules use the new zone at the next step. |
| Screen lock / screensaver | Session continues; plan downgrades display→system (C1 default); activity paused; Drive Alive continues. |
| Fast user switching (our session resigns console) | Plan downgrades to system; activity paused; `endOnUserSwitch` ends `.userSwitch`. Becoming active again re-applies. |
| Low Power Mode on | Toast once "Low Power Mode is on. Awake keeps running." unless `endOnLowPowerMode`. |
| Thermal serious / critical | §2.6. |
| Safe Mode | Manual sessions, guards, indicator, history, shortcuts, CLI work; triggers, activity, nudge, Drive Alive are removed. |
| Displays panic ("Restore All Displays") | Not an Awake participant: keep-awake is not a display hazard. (0.2's "sleep prevention released" row is deleted with the feature.) |
| Module turned off | `stop()`: assertion released, session ended and the snapshot cleared, status item removed. |

### 2.13 Interaction with Displays and the Switcher

- **Displays**: `sleepPrevention` and its code are removed (§4.6 migrates the settings): `DisplayFeature.sleepPrevention`, `PerDisplayManagement.preventSleep` (kept decodable for one release, ignored), PowerController's assertion code, `ManagementIDs.dSleepPrevention*`, `DisplaysRuntimeState.sleepPreventionActive`, the Arrangement-page section, the menu badge, the CLI `prevent-sleep` verb, KitBackup/KitControl/DisplaysUIModel/Diagnostics rows. The lint rule "only AssertionManager creates power assertions" enforces it. Awake never calls Displays code except B's pure `DisplayIdentity` hashing helpers and a read-only look at `DisplaysConfig` custom names.
- **Switcher**: no functional coupling. Pointer nudges are tagged and suppressed while the switcher panel is visible (`HostSignals.switcherVisible`, a new `@Published` Bool on a lead-owned `HostSignals` object in `ModuleContext`). Hotkey conflicts across modules are reported by `GlobalHotkeys` with the owning module's name.
- **Host**: `ModuleHost` gains `awake: AwakeModule`, `awakeStore`, `awakeStateStore`, `awakeHistoryStore` (one store per key: `SnapticAwakeV1`, `SnapticAwakeStateV1`, `SnapticAwakeHistoryV1`), flushes them on quit, and includes them in Reset All Settings (history and state cleared too).

### 2.14 Config models (Kit; lossy decode per field, `sanitized()` clamps everything)

```swift
// Config/ConfigAwake.swift (lead): composition under key SnapticAwakeV1
package struct AwakeConfig: ConfigModel {
    package var features: LossyMap<AwakeFeature, Bool>
    package var sessions: AwakeSessionsConfig        // G
    package var guards: AwakeGuardsConfig            // G (§2.6)
    package var triggers: AwakeTriggersConfig        // G (§2.7)
    package var activity: AwakeActivityConfig        // J
    package var drives: DriveAliveConfig             // J
    package var indicator: AwakeIndicatorConfig     // G (edited on the Menu Bar page)
    package var shortcuts: LossyMap<AwakeActionID, HotkeyCombo>   // G
    package var migratedFromDisplays: Bool           // §4.6, run once
    /// Fields an outside process may not turn on (§3.5).
    package static func protectedChanges(old: AwakeConfig, new: AwakeConfig) -> AwakeConfig?   // returns `new` with them reverted, nil if none
}

// Config/ConfigAwakeSessions.swift (G)
package enum AwakePresetKind: Equatable, Sendable { case indefinite, duration(seconds: Int), untilTime(hour: Int, minute: Int) }
package struct AwakePreset: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var name: String?                // nil = generated ("1 Hour", "Until 5:00 PM", "Until Turned Off")
    package var kind: AwakePresetKind
    package var options: AwakeSessionOptions
}
package struct AwakeSessionsConfig: ConfigModel {
    package var presets: [AwakePreset]       // ≤ 12; default: 15 min, 30 min, 1 h, 2 h, 5 h, Until Turned Off
    package var defaultPresetID: StableID?   // nil or unknown → "Until Turned Off" (C10)
    package var lastCustomSeconds: Int       // 5400
    package var behavior: AwakeBehavior      // §2.6
    package var recentApps: [String]         // ≤ 5 bundle ids for "While an App Is Running"; local only, never exported
}

// Config/ConfigAwakeIndicator.swift (G)
package enum AwakeIndicatorStyle: String, Codable, CaseIterable, Sendable { case icon, iconAndTime, hidden }
package enum AwakeGlyphFamily: String, Codable, CaseIterable, Sendable {
    case cup, mug, eye, sun, bolt, lightbulb        // outline when idle, .fill when active (tested: every symbol exists on 14)
    package var idle: String; package var active: String
}
package struct AwakeIndicatorConfig: ConfigModel {
    package var style: AwakeIndicatorStyle          // .icon
    package var glyph: AwakeGlyphFamily             // .cup
    package var automaticGlyph: AwakeGlyphFamily?   // nil = same as glyph (Advanced "different icon for automatic sessions")
    package var countdown: AwakeCountdown.Style     // .minutes
    package var showEndTime: Bool                   // false: "1:42" left; true: "5:00 PM"
}

// Config/ConfigAwakeDevices.swift (J)
package struct AwakeActivityConfig: ConfigModel { package var intervalSeconds: Int /* 60, 30...600 */ }
package struct DriveAliveVolume: Codable, Equatable, Sendable { package var name: String; package var enabled: Bool }
package struct DriveAliveConfig: ConfigModel {
    package var volumes: LossyMap<VolumeUUIDKey, DriveAliveVolume>   // ≤ 16; key validated as a UUID string
    package var intervalSeconds: Int          // 120, 30...600
    package var evenWithoutSession: Bool      // false (C9)
}
```
Runtime snapshot (`SnapticAwakeStateV1`, G): `AwakeRuntimeSnapshot { manual: AwakeSession?, triggerState: LossyMap<StableID, TriggerRuntime>, guardMemory: GuardMemory }`. History (`SnapticAwakeHistoryV1`, G): `AwakeHistory { entries: [AwakeHistoryEntry] }` with `AwakeHistoryEntry { start, end: Double; kind: AwakeHistoryKind (indefinite|duration|until|app|automatic); presetID, triggerID: StableID?; endReason: AwakeEndReason }`, `append(_:cap: 500)`, `pruned(now:keepDays: 90)`, `totals(now:calendar:) -> (today: Double, week: Double)`.

---

## 3. Security and privacy (additions to 0.2 §4.10)

Threat model unchanged: a same-user process can already hold power assertions (`caffeinate`), write our defaults and launch Snaptic. Snaptic must not let it borrow Snaptic's TCC grants (Accessibility, Removable Volumes), run code, or extract data Snaptic observes.

### 3.1 CLI may start sessions (N1)

Allowed because starting an Awake session grants nothing new: any same-user process can create the identical assertion itself. Constraints that keep it that way:
- The CLI server is off by default (General › Command line) and keeps its 0.2 socket rules (0700/0600, `getpeereid`, rate limit).
- CLI sessions are `source: .commandLine`, visible in the indicator and menu ("Started from the command line"), and subject to every guard; no "Start Anyway".
- The CLI can never cause pointer movement (Accessibility) or Drive Alive writes (Removable Volumes): presets with `nudge` are refused; Drive Alive has no verbs; a CLI session with `evenWithoutSession == false` *does* let Drive Alive write if the user configured volumes — acceptable because the user chose those volumes in the UI and the write target is fixed (§3.3). **[OQ-1]** if the lead wants strict separation, Drive Alive ignores `.commandLine` sessions.
- Closed grammar only (`AwakeDurationGrammar`); max 30 days; no free-form strings reach the assertion.

### 3.2 Activity simulation

- Default `declare` uses no TCC and posts no events.
- `nudge` (experimental) is the only code path in Snaptic that posts mouse events: one file (`ActivitySimulator.swift`, lint), `mouseMoved` ±1 pt only, tagged 'SNPT', never key/click/scroll, never while locked, in the screensaver, off console or when the user was active within the interval; never from the CLI; Accessibility is requested lazily, only when the user turns nudge on (through `PermissionFlow`), and the toggle explains how to revoke it.
- Outside changes that turn on `pointerNudge`, set a preset or trigger's activity to `nudge`, or add/enable Drive Alive volumes are **reverted** on decode of the external change (`AwakeConfig.protectedChanges`) with toast "An Awake setting changed outside Snaptic was ignored." Backup export/import omit them.

### 3.3 Drive Alive writes

Fixed file name at the volume root; target path derived from the live mount list, never from stored paths or user text; `O_NOFOLLOW|O_CREAT`, `fstat` checks (regular, ours, one link, ≤ 64 B); 8 bytes of timestamp; never internal, system, read-only, network, disk-image or Time Machine volumes (Kit `DriveAlivePolicy`, tested); stop before unmount; I/O off main with results hopping back. The Removable Volumes grant is Snaptic's own, used only for this file.

### 3.4 No code execution, no network

Awake spawns nothing (lint: no `Process`, `posix_spawn`, `NSAppleScript`, `NSUserScriptTask`, `system(` in `Sources/Snaptic/Awake/**`); triggers have no actions besides starting a session; no URL scheme; no AppleScript. NetworkMonitor reads kernel/configd state only (`SCDynamicStore`, `getifaddrs`, routing-table `sysctl`); lint bans `URLSession`, `NWConnection`, `CFSocket`, `socket(`, `connect(` in Awake as elsewhere.

### 3.5 Privacy

- **Logs** (`EventLog`, `.awake`): kinds and reasons only ("session started: duration", "trigger 3 active: display"); never app names, bundle ids, volume names/UUIDs, USB names/serials, addresses, router data, trigger names.
- **Assertion properties** are world-readable (`pmset -g assertions`): name and details use fixed vocabulary (§2.4), never user strings or app names.
- **CLI** `awake status`: kinds and trigger numbers only.
- **Stored identifiers**: router MACs and USB serials as salted hashes (`SnapticAwakeSalt`, never exported); display matches as salted fingerprint tiers (existing salt).
- **Backup**: export includes Awake presets, guards, indicator and (non-protected) trigger definitions; omits history, runtime state, salts, `recentApps`, Drive Alive volumes, activity mode, nudge. Import strips the same fields.
- **Diagnostics** (shared report): Awake section with effective features, governing kind, assertion type, guard state, source activity (running/idle), counts of triggers/criteria by kind, Drive Alive volume count and last error codes; no names.

---

## 4. Settings redesign

### 4.1 SettingsUI component library (H, `Sources/Snaptic/SettingsUI/`)

All pages use these and nothing else for rows (lint: raw `Slider(`, `Stepper(` and `.font(.caption).foregroundStyle(.secondary)` are banned outside `SettingsUI/`). Grouped `Form` (`.formStyle(.grouped)`), system text styles, semantic colors, 4-pt grid, 0.15 s crossfades only, Reduce Motion/Transparency honored ([DS] §5).

```swift
enum SettingsTint: String { case gray, blue, indigo, orange, green, red, purple, teal; var color: Color }

struct SettingsIcon: View { init(_ symbol: String, tint: SettingsTint, size: CGFloat = 20) }   // rounded-square tile, a11y hidden

/// Top section of every page. `isOn` = master switch (module or feature group); `learnMore` = HelpLink target route.
struct SettingsPageHeader: View {
    init(_ title: String, summary: String, symbol: String, tint: SettingsTint,
         isOn: Binding<Bool>? = nil, badge: SettingsBadge? = nil, status: String? = nil)
}
enum SettingsBadge { case beta, experimental, paused(String), unavailable(String) }

/// Shown under the header while a module or feature group is off: 2–3 "what this does" rows.
struct FeatureHighlights: View { init(_ rows: [FeatureHighlight]) }
struct FeatureHighlight: Identifiable { let id: String; let symbol: String; let title: String; let text: String }

/// Title + optional one-line help (secondary subtitle) + trailing control + reset glyph + context-menu reset.
struct SettingRow<Control: View>: View {
    init(_ title: String, help: String? = nil, anchor: String? = nil,
         isDefault: Bool = true, reset: (() -> Void)? = nil, @ViewBuilder control: () -> Control)
}
struct ResetButton: View { init(visible: Bool, action: @escaping () -> Void) }   // reserves space; fades

struct ToggleSetting: View {
    init(_ title: String, help: String? = nil, isOn: Binding<Bool>, subordinate: Bool = false,
         anchor: String? = nil, badge: SettingsBadge? = nil, disabledReason: String? = nil)
}

/// Every slider in Settings (N4).
struct SliderSetting: View {
    init(_ title: String, help: String? = nil, value: Binding<Double>, in range: ClosedRange<Double>,
         step: Double? = nil, defaultValue: Double?, format: ValueFormat,
         minSymbol: String? = nil, maxSymbol: String? = nil,
         commit: SliderCommit = .throttled(hz: 15), preview: (@MainActor (Double) -> Void)? = nil,
         anchor: String? = nil, disabledReason: String? = nil)
}
enum SliderCommit: Equatable {
    case live                 // binding is a @Published model value that coalesces its own hardware writes
    case throttled(hz: Double) // config-backed: writes at most hz/s during a drag, final value on release
    case onRelease            // expensive side effects; `preview` gives live feedback meanwhile
}
/// Units and scaling for display, typing and VoiceOver (Kit `ValueFormat` in SliderMath.swift).
// e.g. .percent(of: 1) shows 0…1 as 0–100%; .seconds; .minutes; .hertz; .points; .nits; .kelvin; .plain(digits:)

struct NumberField: View {      // typed entry: commits on Return and blur; clamps + snaps to step; Esc reverts; shows unit
    init(_ accessibilityTitle: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double?,
         format: ValueFormat, width: CGFloat = 52)
}
struct StepperSetting: View {   // small integer ranges (≤ ~20 values): label + NumberField + Stepper + reset
    init(_ title: String, help: String? = nil, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         defaultValue: Int?, format: ValueFormat, anchor: String? = nil)
}
struct PickerSetting<V: Hashable>: View {   // pop-up (> 4 options), segmented (2–4 short), radio (2–5 with help)
    init(_ title: String, help: String? = nil, selection: Binding<V>, options: [PickerOption<V>],
         style: PickerSettingStyle = .automatic, defaultValue: V?, anchor: String? = nil)
}
struct PickerOption<V: Hashable>: Identifiable { let value: V; let title: String; let help: String?; let symbol: String? }

struct InfoButton: View { init(_ title: String, message: String) }            // (i) popover, 280 pt
struct NavigationRow: View {                                                   // icon tile + title + trailing value + chevron
    init(_ title: String, symbol: String, tint: SettingsTint, value: String? = nil, route: SettingsRoute, badge: SettingsBadge? = nil)
}
struct StatusRow: View { init(_ text: String, symbol: String? = nil, style: StatusStyle = .info, action: StatusAction? = nil) }
struct PerDisplayPicker: View { init(_ displays: [DisplayTile], selection: Binding<DisplayKey?>) }   // tiles; hidden with one display
struct DisplayTile: Identifiable, Hashable { let id: DisplayKey; let name: String; let isBuiltin: Bool; let badges: [String] }
struct PageFooterButtons: View { init(restoreDefaults: RestoreDefaults?, advanced: (() -> Void)?, help: SettingsRoute?) }
struct RestoreDefaults { let scopeName: String; let action: @MainActor () -> Void }   // confirmation names the scope
struct AdvancedSheet<Content: View>: View { init(_ title: String, @ViewBuilder content: () -> Content) }  // 520 wide, Done = Return
struct ReorderableList<Item: Identifiable, Row: View>: View { init(_ items: Binding<[Item]>, onDelete: ((Item) -> Void)?, @ViewBuilder row: (Item) -> Row) }  // List .onMove + ▲▼ menu for keyboard
struct AppListEditor: View { init(_ title: String, help: String?, bundleIDs: Binding<[String]>, anchor: String?) }   // moved from Switcher AppListSection; used by Switcher and PIP
struct ShortcutSetting: View { init(_ title: String, help: String? = nil, combo: Binding<HotkeyCombo?>, owner: String, anchor: String? = nil) }  // wraps ShortcutRecorder; shows conflicts by owner
extension View { func settingsAnchor(_ id: String) -> some View }   // ScrollViewReader id + search highlight (1.2 s tint; static with Reduce Motion)
```

Shell contracts (lead, `Core/ModuleContracts.swift`; replaces `settingsPages()`):

```swift
struct SettingsRoute: Hashable, Sendable { let id: String }          // "displays.color", "awake.history"
struct SettingsSearchEntry: Hashable, Sendable {
    let id: String; let title: String; let keywords: [String]
    let root: String                 // sidebar item id
    let route: SettingsRoute?        // sub-page, nil = root page
    let anchor: String               // settingsAnchor id
    let sheet: String?               // Advanced sheet id to open first
}
struct SettingsRoot: Identifiable, Hashable {
    let id: String; let title: String; let symbol: String; let tint: SettingsTint
    let makeView: @MainActor () -> AnyView
}
@MainActor protocol SnapticModule: AnyObject {
    // id, title, symbolName, summary, state, requiredPermissions, start, stop, menuSection — unchanged
    var tint: SettingsTint { get }
    var highlights: [FeatureHighlight] { get }                       // off-state block
    func settingsRoot() -> SettingsRoot                               // rendered whether running or not
    func settingsDestination(_ route: SettingsRoute) -> AnyView?
    func settingsIndex() -> [SettingsSearchEntry]                     // static per module; computed once
}
/// Environment object every page receives (H): master switches, navigation, sheets, highlight.
@MainActor final class SettingsShell: ObservableObject {
    func moduleEnabled(_ id: ModuleID) -> Binding<Bool>
    func push(_ route: SettingsRoute); func pop()
    @Published var openSheet: String?
    @Published var highlightedAnchor: String?
}
```

Kit (H, tested): `SliderMath.swift` (`ValueFormat`, `clampSnap`, `isDefault(value:default:step:)` with half-step tolerance, `format`, locale-aware `parse` accepting "70", "70 %", "1,5 s", `spoken` for VoiceOver); `SettingsIndex.swift` (`SettingsSearch.rank(entries:query:) -> [SettingsSearchEntry]`: diacritic/case-insensitive prefix-of-word match on title > keywords > synonyms table; synonyms: DDC↔monitor/hardware, caffeinate/insomnia/amphetamine/keep awake/sleep↔Awake, alt-tab/⌥⇥↔Window Switcher, PIP↔picture in picture, OSD↔brightness indicator, HiDPI↔sharper text, XDR↔extra brightness).

### 4.2 Information architecture

**Window**: `NavigationSplitView`, sidebar 200–240 pt with `.searchable(placement: .sidebar)` at the top, detail `NavigationStack` per root (back button for sub-pages), `.toolbar(removing: .sidebarToggle)`, default 780×640, min 715×520, title = current page, last root + route restored (`@AppStorage("settings.lastRoute")`). While open the app is `.regular` (0.2 R5.8 kept).

**Sidebar** (fixed; 8 rows; groups separated by spacing):

```
[Search]
General              gearshape          gray
Menu Bar             menubar.rectangle  blue
—
Window Switcher      rectangle.on.rectangle   indigo    (master switch on page)
Displays             sun.max.fill             blue      (master switch on page)
Awake                cup.and.saucer.fill      orange    (master switch on page)
—
Permissions          hand.raised.fill   blue
About                info.circle.fill   gray
```
Search results replace the list with "Title — Page" rows; choosing one selects the root, pushes the route, opens the sheet if any and highlights the anchor. No results → `ContentUnavailableView.search(text:)`.

**Copy rules** ([DS] §4, normative): sentence case for labels, help, section headers; Title Case for buttons, menu items, page titles; labels name the thing or the on-state, no "Enable/Disable/Allow X to"; one help sentence ≤ 90 characters describing the on state; "Mac", "display", "click", "press"; errors say what to do; real ellipsis; "20%", "60 Hz", "15 min" in value labels; Apple terms table [DS] §4.7 (Display, Virtual display, Picture in Picture, Brightness indicator, Saved layouts, Start automatically, Keep Awake, Display Information, Confirm display changes, Settings). Every visible control has help text or is self-evident by Apple precedent (lint-free review item: each `ToggleSetting`/`SliderSetting` without `help:` needs a reviewer note).

Budget: ≤ 8 controls visible per page before **Advanced…** ([DS] success test).

### 4.3 Pages (normative content; V = visible, A = Advanced sheet, S = sub-page, X = removed/merged)

**General** (hero header, no master switch; was 9 pages / ~34 controls)

| Section | Control | Where | From |
|---|---|---|---|
| Modules | Window Switcher / Displays / Awake rows: icon tile, name, "On"/"Off", chevron → module page | V (navigation, not switches: the master switch lives on each module page) | Modules page switches (X) |
| | "New: Awake" card (C7), dismissible | V once | "New: Displays" card |
| Startup | Open at login | V | Startup page (X: a page for one toggle) |
| Command line | Command-line control (help: "Lets scripts and tools like Raycast run `snaptic` commands.") · Copy Install Command | V | CLI page |
| | Commands can skip confirmation · exit-code table | A | CLI page |
| Backup | Export Settings… · Import Settings… | V | Backup & Reset |
| Footer | Restore Defaults… (= Reset All Settings, scope "all Snaptic settings") · Advanced… | V | |
| Advanced sheet | Restart in Safe Mode… / Leave Safe Mode (with its explanation) | A | Safe Mode page (X) |

"Other display apps" moves to Displays › Advanced. About & Licenses → About.

**Menu Bar** (M; N7; was General › Menu with ~28 controls)

| Section | Controls | Where |
|---|---|---|
| Snaptic icon | Icon picker as a row of glyph tiles (curated, rendered, never raw symbol names) | V |
| Modules | Per module: "Own icon" (switch) and "In Snaptic's menu" (switch) — `MenuPresence` (C2); help when both off: "Use the shortcut or Settings to reach it." | V (3 rows × 2 mini switches) |
| Awake icon | Show: Icon / Icon and time remaining (segmented, disabled when own icon off) · Icon style (glyph tiles) | V |
| | Different icon for automatic sessions · Show seconds · Show end time instead of time remaining | A |
| Displays menu | Display controls: Expanded / Compact · Show the main display first · Hide the Displays icon when no external display is connected | V (3) |
| | Customize Displays Menu… → sheet: display order + per-display visibility (one reorderable list with checkboxes), section order, per-item visibility grouped by area with human titles ("Volume", "Input", "Turn Display On or Off"), header switch per display (was Arrangement "Header switch"), status badges, header row with one display | A-style sheet |
| Sliders | Scroll over a slider to adjust it | V |
| Footer | Restore Defaults… (scope "menu bar settings") | V |

**Window Switcher** (H; header switch; was 6 pages / ~40 controls)

| Section | Controls | Where | Notes |
|---|---|---|---|
| Shortcut | Primary shortcut (modifier + key recorder) | V | first `Shortcut` |
| | Show: All windows / Active app / This display (pop-up) · Style: Thumbnails / Icons / List (segmented) | V | primary shortcut's scope/style |
| | Thumbnail size (SliderSetting 100–300 pt, step 10, default 170; shown only for Thumbnails; "Automatically" toggle subordinate) | V | fixes C2 |
| Windows | Include minimized and hidden windows · Windows from: All Spaces / Current Space / Other Spaces | V | per-shortcut options of the primary shortcut; the global `otherSpaces`/`windowlessApps` feature switches become A |
| Behavior | Switch when you release the keys · Show on: Display with the active window / Display with the pointer | V | |
| Footer | Restore Defaults… · Keyboard Shortcuts… (sheet: additional switcher shortcuts with their own options, Gather Windows shortcut) · Advanced… | V | |
| Advanced | Window actions (Close, Minimize, Full Screen, Hide, Quit — one checkbox group), Hover buttons, Select by hovering, Search, ⌘⇥ replaces the app switcher, Pass shortcuts through to apps (+ Only while full screen + app list), Apps hidden from the switcher (AppListEditor), Never show thumbnails for (password managers toggle + AppListEditor; renamed from "Privacy"), One entry per app, Include apps with no open windows | A | Features page (X), App Lists (X), Privacy (X) |

**Displays** (F composes; owners provide sections; header switch; was 16 pages / ~170–330 controls)

Root page:

| Section | Controls | Owner |
|---|---|---|
| Header | Displays switch; status line ("2 displays") | F |
| Display tiles | `PerDisplayPicker` (hidden with one display); each tile has (i) → **Display Details…** sheet | F |
| Brightness (selected display) | Brightness slider (☀︎ min/max symbols, full range incl. XDR, `.live`) · Automatically adjust brightness (built-in, if `autoBrightness` available) | C |
| Resolution (selected display) | Resolution pop-up (scaled modes, "Default for display" first, favorites marked) · Refresh rate (if > 1) · HDR (if supported and `hdrToggle`) · Rotation (if `rotation`) · Match Text Size… (if `scaleMatch`) | D |
| Arrangement | Arrange… (sheet: canvas + Snap to edges + keyboard Position/Align form as a disclosure) · Use as: Main display / Extended / Mirror for "X" (pop-up) | D |
| Navigation rows | Brightness › · Color › · Monitor Controls › (externals with DDC) · Keyboard & Indicator › · Saved Layouts › · Virtual Displays › · Picture in Picture › · Automations › — each row shows "On/Off" and is always present | F + owners |
| Footer | Restore Defaults… (scope "Displays settings") · Advanced… · (?) | F |

Display Details… sheet (per display; F + B): Name (field + Use the System Name), Icon (glyph tiles), Show in the menu and the Displays panel, Disconnect / Connect (if `disconnect`), Never disconnect automatically (built-in, if `autoDisconnectBuiltin`), menu bar strip and rounded corners (if `menuBarOverlays`), Copy Settings From…, Forget This Display…, Display Information (disclosure: transport, masked serial, EDID Copy/Export).

Displays › Advanced sheet (F composes; groups from owners):
1. **Use Snaptic for** (feature switches for standard features, plain words): Brightness control, Resolution control, Arrangement and mirroring, Keyboard shortcuts, Brightness indicator, Monitor controls (DDC). (F; replaces Features page)
2. **Brightness methods** (C): Apple native / DDC / Color table / Overlay checkboxes (the four method features), per-display "Use" picker, custom switchover + slider, minimum hardware level, XDR method, color-table check "Ask Again".
3. **Resolution** (D): Offer modes below 720p, Only native aspect ratio on the slider, Show values as, Snap to favorites, Remember my choice, per-display width limits / DPI / refresh filters, Show all resolutions (Experimental, `hiddenModes`), Match tolerance.
4. **Confirm display changes** (B; was Safety page): Confirm resolution changes (one picker, one label set), Revert after N s (StepperSetting 5–60), Tell me when displays were restored, Restore All Displays shortcut (now editable `ShortcutSetting`, default ⌃⌥⌘⎋), Restore All Displays Now, Resume Automation, Allowed without asking (the single list; DDC page copy X).
5. **Connection** (D): Disconnect feature (Beta) switch, auto-disconnect built-in + "My monitor has no DDC", Underscan (Experimental) per display.
6. **Other display apps** (A): Pause overlapping features / Run both (radio).
7. **Experimental** (F lists, owners implement): HDR toggle, Underscan, Night Shift, Apple display presets, Built-in auto-brightness, HDR virtual modes, Brightness broadcast (`osdBroadcast`) — each with Experimental badge and one help line.
8. **Display Information…** (F): the diagnostics report (live, refreshes on change), Copy Report, Export…; safety-helper status rows from the old Safety page.

Sub-pages (each: `SettingsPageHeader` with the feature-group switch where one exists, ≤ 8 visible controls, own Advanced… when needed):

| Sub-page | Switch (features) | Visible | Advanced / removed |
|---|---|---|---|
| Brightness (C) | — | Restore brightness at login and wake (pop-up incl. Off = `brightnessRestore`) · Smooth transitions · Sync brightness (switch `sync`; source, follow, offset per display as subordinate rows) · Extra brightness XDR (switch `xdr`, Beta; per-display maximum SliderSetting; Pause below battery SliderSetting) · Dim when the screen locks (switch `dimOnLock`; level slider) · Allow dimming to black (`dimToBlack`) · Show brightness in nits (`nits`; single field replaces duplicate 3) | A: custom nits range fields, Stop at 100% detent, XDR "Pause in Low Power Mode", sync "Follow outside changes" |
| Color (C) | Color adjustments (`color`) | Display tiles · Contrast, Gamma, Temperature, Black level, White level (5 SliderSettings, each with reset/field; "Software contrast" label to distinguish from monitor contrast, duplicate 8) · Invert colors · Suspend on this display · Color profile (pop-up, `colorProfiles`) | A: Gain, per-channel RGB gain and gamma (6), keep color-table dimming with custom profiles, all-displays suspend, shortcut step sizes; Night Shift (Experimental) lives in Advanced with Warmth (duplicate 9 resolved: "Temperature" = Snaptic's adjustment, Night Shift warmth only inside its own group). Menu-bar strip/corners X → Display Details |
| Monitor Controls (C) | Monitor controls (`ddcControls`) | External display tiles · Volume (`.live`) + Mute · Contrast (`.live`, "Monitor contrast") · Input (pop-up, if `ddcInput`) · Power: Turn Off/On (if `ddcPower`) · "Use monitor controls for this display" | A: read back values + interval, re-send after wake, per-control tuning (raw 0/100%, invert, show in menu, read-back interval) as a list with Details… sheet per control, input list editor, standby value, custom controls (`ddcCustom`), raw VCP get/set + unlock, timing (reply delay, retries, write twice, ignore checksums, forget framing), status/MCCS/supported codes (read-only, under "Monitor Information") |
| Keyboard & Indicator (C) | — | Brightness keys (switch `brightnessKeys`; "Change: display under the pointer / main / all" pop-up) · Volume keys (switch `volumeKeys`; target pop-up) · Indicator style (pop-up incl. "Use the system indicator" on 14/15) · Indicator position · Keyboard Shortcuts… (sheet: **one grouped list** of all Displays actions — Brightness, Volume & contrast, Resolution, Arrangement, Tools — with filter field) | A: also let macOS handle keys, steps / fine steps (StepperSetting), F14/F15, per-display "keys change this display", show volume indicator per display, sound output name, input slots, indicator "show on", show value; Modifiers reference table → (i) popover |
| Saved Layouts (D) | Saved layouts (`layouts`) | Save Current Layout… · list (name, Matches badge, Apply, (i) Details… sheet: apply automatically, priority, trust, update, delete) · Protect the current arrangement (switch `protection`) | A: protected fields (5 checkboxes), Offer Undo after automatic apply, Forget all |
| Virtual Displays (D) | Virtual displays (`virtualScreens`, Beta) | List (Connected switch, Details…) · New Virtual Display… (sheet with shape picker + recipes as tiles) · Sharper text on this display (Smart HiDPI, switch per display, Beta) | A: behavior toggles, bulk Connect/Disconnect All, HDR virtual modes; editor sheet replaces the inline form, "Sizes" becomes a table with + / − instead of a text editor |
| Picture in Picture (E) | Picture in Picture (`pip`) | Screen Recording status row · Running list (Pause/Show/Stop) · Saved PIPs list (Start, Edit…) · New PIP… / New Stream… | Editor = sheet (window, capture, orientation, full screen, filters `pipFilters` sections); A: privacy prefixes (AppListEditor, renamed "Never capture these apps"), pause covered PIPs, LUT import |
| Automations (A) | Event hooks (`hooks`), Custom actions (`customActions`) | Hooks list (Enabled, When, Details… sheet) · Actions list (Show in menu, Details… sheet) | Sheets bind directly to config (fixes B2); action shortcuts listed in Keyboard Shortcuts… too |

**Awake** (G; header switch "Awake", summary "Keep your Mac awake for a while, or whenever certain conditions are met.")

| Section | Controls | Where |
|---|---|---|
| Status | Status row: "Not active" + **Start** / "Awake until 3:45 PM (1 h 12 min left) · Started from the menu" + **Extend** + **End** (reaches everything when the status item is hidden, 27) | V |
| Session types | ReorderableList of presets (name, summary, ★ default); + / − ; Edit… sheet (name, kind: Until turned off / For a duration (h/m NumberFields) / Until a time (time picker), Display: Keep on / May sleep / Keep on while I'm active (+ minutes), Activity (if `activity`)) | V |
| | Display may sleep by default (help "Your Mac stays awake, but the display can sleep to save energy.") — sets the default preset's display policy | V |
| End sessions automatically | When battery is below (switch + SliderSetting 5–50%, step 5, default 20) · When the power adapter is disconnected | V (laptops only) |
| Start automatically | Switch (`triggers`); list of triggers (switch, name, `TriggerEngine.summary`, "Active" badge), drag to reorder (help "Higher in the list wins.") · Add Condition… (sheet: kind picker as tiles → kind-specific fields; All/Any; session options; start/end delays under a disclosure) · Pause for 1 Hour | V |
| Navigation rows | Drives › (Drive Alive: switch + eligible volumes list with switches + interval SliderSetting + "Even without a session"; J) · History › (totals, list, Start Again, Clear History…) | V |
| Footer | Restore Defaults… (scope "Awake settings"; keeps history) · Keyboard Shortcuts… · Advanced… | V |
| Advanced | Activity: Tell macOS you're active (switch `activity`) + interval · Move the pointer (Experimental `pointerNudge`, Accessibility status row) · When the Mac goes to sleep, end the session · When you switch users, end the session · Keep the display on while locked (C1) · When Low Power Mode turns on, end the session · Also end on serious heat · Continue sessions after Snaptic restarts · Start a session when Snaptic opens (pop-up of presets / None) · Sleep Status… (other apps' assertions, lid behavior) | A |

**Permissions** (H): Accessibility and Screen Recording rows (state, "Needed by …", Open Settings, Show Snaptic in Finder, relaunch), Removable Volumes info row when Drive Alive is on ("macOS asks the first time Snaptic writes to a drive"), signer line (R5.7).

**About** (H): app icon, version, Check for Updates…, Acknowledgements… (sheet with MIT text and credits), Diagnostics Report… (opens Displays › Display Information when Displays runs, else a host report).

Resulting counts (1 built-in + 1 DDC external, default features): sidebar 8 rows (was 26–31); visible controls before Advanced: General 6, Menu Bar 11, Window Switcher 8, Displays root 8 + 8 navigation rows, Awake 8 + list rows; total default-visible ≈ 70 (was ≈ 245).

### 4.4 Duplicates ([UA] §2.4) — one owner each

| # | Duplicate | Resolution |
|---|---|---|
| 1 | Confirm resolution changes (Resolution + Safety) | Displays › Advanced › Confirm display changes only; one label set |
| 2 | Allowed without asking (DDC + Safety) | Advanced › Confirm display changes only |
| 3 | Show nits (`brightness.showNits` + `keys.osdShowNits`) | One field `brightness.showNits` (migration §4.6) on Brightness |
| 4 | Display order/visibility (Names + Menu) | Menu Bar › Customize Displays Menu… only |
| 5 | Panel/Identify shortcuts (`menu.*Shortcut` + `keys.shortcuts`) | `keys.shortcuts` only (migration); Keyboard Shortcuts… sheet |
| 6 | Feature on/off on two pages + 4 "is off" variants | Feature switch where used; one `SettingsPageHeader` switch / `ToggleSetting`; `FeatureHighlights` for off state |
| 7 | Live controls on 4 surfaces, different ranges | One `DisplayLiveControls` model (F) with the full range used by root page, menu and panel; own pages keep only settings, not duplicate sliders |
| 8 | Contrast software vs hardware | Labels "Software contrast" (Color) and "Monitor contrast" (Monitor Controls) |
| 9 | Temperature vs Night Shift warmth | Night Shift moved to Advanced/Experimental group with its own label "Night Shift warmth" |
| 10 | Capture privacy Switcher vs PIP | Kept separate (different scopes), renamed "Never show thumbnails for" / "Never capture these apps", both `AppListEditor` |
| 11 | Switcher per-shortcut vs feature switches | Primary shortcut options visible; feature switches in Advanced with help "Applies to every shortcut" |
| 12 | Volume OSD (Keys + OSD page) | Keyboard & Indicator page only (OSD page X) |
| 13 | Menu settings inside Displays pages | All on Menu Bar page (N7) |
| 14 | Restore All Displays in 4 places, fixed shortcut | Menu Display Tools, panel, Advanced; shortcut editable in one place |

### 4.5 Live-update architecture (fixes [UA] §1 at the source)

| Change | Owner | Fixes |
|---|---|---|
| `DisplayRuntime` gains `@Published brightnessPosition: Double?` (full range incl. XDR), `brightnessRange: ClosedRange<Double>`, `contrastRange`, `volumeRange`; BrightnessService/DDCController write only through these; pages never read `BrightnessService.states` | lead (type), C (writers) | A1, A2, overview 0…1 range |
| Per-display sections are subviews with `@ObservedObject var live: DisplayRuntime` (the `DisplayControlsCard` pattern) | page owners | A1, A2 |
| `DisplaysRuntimeState.revisions: ControllerRevisions` (ObservableObject, `@Published private(set) var counts: [DisplayControllerID: UInt64]`, `bump(_:)` coalesced to one publish per main-queue turn, ≤ 15 Hz); controllers bump whenever page-visible state changes (rotation/HDR/underscan, protection, layouts, virtual live/busy, Smart HiDPI pairs, undo/redo/favorites, Night Shift, guard status, capture sessions); sections that show controller state observe it | lead (type), B/C/D/E (bumps) | A4, A6–A11; delete the `objectWillChange.send()` pokes and Safety's 2 s timer (lint bans `objectWillChange.send()` in `Displays/UI`) |
| No `@State(initialValue:)` copies of model values; editors bind to the store or resync with `.onChange(of:)` | owners of ShortcutEditor (H), Hook/Action/CommandEditor (A), NameField (F), CustomSliderRow (C, seeded from `ddc.lastReading`) | A3, B1–B3 |
| `SliderSetting` drag-local state: `@State drag: Double?`; shows `drag ?? value`; commit per `SliderCommit`; final value on release; `preview` for live hardware feedback without config writes | H | C1 "laggy drags" |
| Config fan-out by section: Kit `DisplaysConfig.changedSections(old:new:) -> Set<DisplaysConfigSection>`; `DisplayFeatureController` gains `static var observedSections: Set<DisplaysConfigSection>`; `DisplaysModule.configChanged` notifies only controllers whose sections changed; `ColorController` re-applies gamma only for displays whose `perDisplay.color` changed | lead (+ every controller declares its sections; default `allCases` until migrated) | C1 fan-out to every controller, gamma reapply per tick |
| `ManagementBindings.perDisplay` and other binding helpers stop calling `sanitized()` per tick (ConfigStore sanitizes on load and external change; UI ranges are already clamped by components); binding helpers collapse to `SettingsBinding` (H) | H + D | C1 |
| Switcher `AppSettings` saves through a 250 ms debounce like `ConfigStore` | A | C2 |
| `MenuSliderRow` (M) replaces `MenuSliderItem`: value label, `range` in init, `bind(to: AnyPublisher<Double?, Never>)` so volume/contrast/resolution/brightness follow live changes while the menu is open; never fights a drag | M (+ C/D contributors adopt) | M1 |

Rule (lint + review): a Settings view may read controller state only inside a view that observes `ControllerRevisions` or the relevant `DisplayRuntime`.

### 4.6 Config migration (no setting lost)

All migrations are pure Kit functions with tests; they run in `init(from:)` or once at host start, write back on the next save, and never delete source keys in 0.3 (old keys stay readable for one release so a downgrade to 0.2 still works).

| # | From | To | Where |
|---|---|---|---|
| M1 | `DisplaysConfig.features.sleepPrevention` + `perDisplay.*.management.preventSleep` (+ that display's `identity.fingerprint`, `customName`/`lastKnownName`) | One Awake trigger "While a display is connected" (`.any` over `display(.specific)` per display, options `.keepOn`), enabled iff the feature was on; if enabled, Awake module and `triggers` feature turned on; `AwakeConfig.migratedFromDisplays = true` | Kit `AwakeMigration.fromDisplays(rawJSON:) -> AwakeMigrationResult` (G), run by `ModuleHost` before modules start (lead) |
| M2 | `ModulePreferences.placement` (`shared/ownIcon/hidden`) | `MenuPresence(ownItem: placement == .ownIcon, inSnapticMenu: placement == .shared)`; Awake default `(ownItem: true, inSnapticMenu: false)` | `ConfigModules` decode (lead) |
| M3 | `ModulesConfig.showNewDisplaysCard` | `newModuleCards: Set<ModuleID>` | lead |
| M4 | `MenuConfig.showPanelShortcut`, `identifyShortcut` | `keys.shortcuts[showPanel]`, `[identify]` when those are unset | `DisplaysConfig.init(from:)` post-decode (lead) |
| M5 | `keys.osdShowNits` | `brightness.showNits = brightness.showNits || keys.osdShowNits` | `DisplaysConfig` post-decode (lead) |
| M6 | `SafetyConfig.panicHotkeyEnabled` + fixed combo | `panicHotkey` editable; enabled → default combo stored explicitly | B |
| M7 | Switcher features `otherSpaces`/`windowlessApps` vs per-shortcut flags | unchanged storage; UI only | — |
| M8 | Raw feature flags of features without a switch in the new UI | unchanged; each still reachable (Advanced › Use Snaptic for / Experimental) | — |

Page **Restore Defaults…** resets only that page's scope through Kit functions (`AwakeConfig.restoringDefaults()`, `DisplaysConfig.restoringDefaults(scope:)`, `MenuConfig()` etc.), each tested to leave other scopes, salts, history and protected fields untouched.

### 4.7 Onboarding (H)

Welcome → Choose modules (3 rows with switches and one-line descriptions; Awake preselected for fresh installs) → Displays chips (existing; summary lists **user words**, not feature ids; chips are toggles) → Awake quick setup (default session pop-up, battery switch; skipped if Awake is off) → Permissions (only what was chosen) → Done. One primary button, always in the window footer ("Continue" / "Done"); the in-form "Use These Features" button is removed.

---

## 5. Menu bar redesign (M owns the system; module owners own their sections)

### 5.1 MenuKit (M, `Core/MenuKit.swift`, `Core/MenuSliderRow.swift`, `Core/MenuHostingRows.swift`)

```swift
@MainActor enum MenuKit {
    static let width: CGFloat = 300                         // menus containing hosting rows
    static func header(_ title: String) -> NSMenuItem       // NSMenuItem.sectionHeader(title:) — the ONLY header style
    static func action(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
                       enabled: Bool = true, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem
    static func toggle(_ title: String, isOn: Bool, enabled: Bool = true, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem  // checkmark
    static func alternate(of item: NSMenuItem, title: String, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem   // ⌥, isAlternate
    static func submenu(_ title: String, enabled: Bool = true, _ items: [NSMenuItem]) -> NSMenuItem   // one level only (asserted in debug)
    static func status(_ text: String, symbol: String) -> NSMenuItem   // disabled info row (banners); symbol required: status rows form their own group
    static func device(_ title: String, symbol: String, badges: [String], submenu: [NSMenuItem]) -> NSMenuItem  // display rows: the only native rows with images
    static func switchHeader(_ title: String, isOn: Bool, detail: String?, onToggle: @escaping @MainActor (Bool) -> Void) -> NSMenuItem  // hosting: bold title + trailing switch (+ secondary detail line)
    static func detail(_ text: String) -> NSMenuItem          // hosting: secondary 11 pt line, non-actionable
    static func settings(_ title: String = L("Settings…"), _ handler: @escaping @MainActor () -> Void) -> NSMenuItem  // ⌘, last
}
@MainActor final class MenuSliderRow: NSMenuItem {
    init(title: String, symbol: String, value: Double?, range: ClosedRange<Double>, format: ValueFormat,
         onChange: @escaping @MainActor (Double) -> Void)
    func bind(to publisher: AnyPublisher<Double?, Never>)   // live updates while open; ignored during a drag
    func setValue(_ v: Double?)                             // nil → slider disabled, value "—"
}
```

Item rules: Title Case; no images except `device` and `status` rows (15-SDK builds show every attached image on 26/27, [DS] §3.3); ellipsis only when more input follows; toggles use checkmarks or a changing title; submenus one level deep, ≤ ~8 items plus at most one "More…" that opens Settings; hosting rows only where native items can't express the control (sliders, switch headers, detail lines) and never clickable; every slider action also has a keyboard path (submenu presets, shortcuts, Settings). `ClosureMenuItem`, `CMenu.item`, `ManagedMenuItem`, `DisplayMenuBlock.actionItem`, `PanicMenuItem` are deleted; contributors use MenuKit (lint bans `NSMenuItem(title:` outside `MenuKit.swift`).

**Slider row**: 300 × 32 pt; leading SF Symbol 14 pt secondary at the native text inset (14 pt, measured per OS [HW-15]); `NSSlider` regular control size; trailing value label 40 pt, `monospacedDigitSystemFont`, secondary; accessibility label "Brightness, DELL U2720Q", value "70 percent"; scroll-to-adjust per Menu Bar setting.

### 5.2 Snaptic icon menu (shared item)

Built in `menuNeedsUpdate` from the modules whose `MenuPresence.inSnapticMenu` is on, in start order; sections separated by one separator; values update in place while open.

```
[Safe Mode is on]                               status row + "Leave Safe Mode" (only in Safe Mode)
Window Switcher                                 header
  Switch Windows                         ⌥⇥    C8 (sticky switcher)
  Gather Windows on This Display
  [Turn On Thumbnails…]                         status row, only while Screen Recording is missing
───
Displays                                        header
  [display] Studio Display  Main          ›     device row; submenu below
  ☀︎ ━━━━━━━━●━━━━━  70%                         MenuSliderRow (brightness)
  [display] DELL U2720Q                   ›
  ☀︎ ━━━━━●━━━━━━━━  45%
  🔈 ━━━●━━━━━━━━━━  30%                         volume only if VCP 0x62
  Arrange Displays…
  Display Tools                           ›     Identify Displays · Redetect Displays · Show Displays Panel · Connect All Displays · Restore All Displays (C3)
───
Awake                                           only if Awake.inSnapticMenu (compact, §5.4)
───
Recent Notices                            ›     only when there are some
Settings…                                ⌘,
Quit Snaptic                             ⌘Q
```
Display submenu (one level): resolution modes (≤ 8: default, favorites, recommended scaled; checkmark on current) · More Resolutions… (Settings) · ─ · Input sources (if `ddcInput`, checkmarks) · ─ · Use as Main Display · Mirror ▸ is **not** nested: mirroring targets inline as "Mirror “X”" toggles · Contrast/Color quick items as toggles only (no sliders in submenus) · ─ · Turn Display Off / Disconnect (if enabled) · Display Settings… . Per-item visibility (Menu Bar › Customize) still applies; "In submenu" means this display submenu; sliders can be Visible or Hidden only.

With no modules enabled: "No Modules Are On" status row + "Open Settings…". With `Compact` display controls: one slider per display, device rows without badges.

### 5.3 Awake status item (G, `IndicatorController`)

`NSStatusItem(variableLength)`, `autosaveName = "SnapticAwake"`, `behavior = .removalAllowed` (KVO on `isVisible`: user ⌘-drag removal turns `ownItem` off with toast "Awake's menu bar icon was removed. Turn it on again in Settings › Menu Bar."), template SF Symbol (family idle/active glyph; automatic sessions may use `automaticGlyph`), `imagePosition = .imageLeading`, title in `monospacedDigitSystemFont(ofSize: menuBarFont size)`, accessibility label "Awake, 1 hour 42 minutes remaining" / "Awake, off" updated on state changes only. Countdown only for `iconAndTime` and timed sessions: `AwakeCountdown.short`, or end time "5:00 PM" (system 12/24 h); indefinite, whileApp and automatic sessions show the glyph only. Redraw at `nextChange` (minute boundaries; 1 s only with seconds on), `.common` mode.

Menu (plain `statusItem.menu`, identical on 14–27):

```
Keep Awake                         [switch]     switchHeader: on → default preset; off → end (automatic → manual end)
  Until 3:45 PM · 1 h 12 min left               detail (live); "Until turned off" / "While Xcode is running" / "Automatic: Desk dock"
  Closing the lid will put your Mac to sleep.   detail, laptops not in desktop mode, only while active
  Battery is below 20%. Awake is paused.        detail, when a guard holds
───
Keep Awake For                                  header
  15 Minutes                                    presets in order (✓ on the running preset); ⌥ alternate: "… (Display May Sleep)"
  1 Hour
  Until Turned Off
  Custom…                                       small non-activating panel: h / m fields or "Until" time; Return starts; remembers last value
  While an App Is Running                 ›     running regular apps (recent first, ≤ 12, app icons — the submenu is one group)
───                                             only while a manual session runs
  Add 15 Minutes  ·  Add 1 Hour                 two action items (no submenu)
  Display May Sleep                       ✓     toggle
───                                             only with `triggers`
Start Automatically                             header
  ✓ Desk dock                     Active        toggles enable each trigger; "Active" as trailing secondary text (attributed title)
  Pause for 1 Hour / Resume
───
Awake Settings…                                 opens Settings › Awake; ⌥ alternate: "Quit Snaptic"
```

### 5.4 Compact Awake section in the Snaptic menu

`Awake` header · switchHeader "Keep Awake" with detail line · "Keep Awake For ›" submenu (presets, Custom…, While an App Is Running items inline) · "Add 1 Hour" while timed. No triggers list (Settings and the Awake item have it).

### 5.5 macOS 26/27 hidden and overflow behavior

There is no API to learn that the system hid an item (26 "Allow in the Menu Bar", 27 overflow); occlusion is unreliable on 27 ([PA] §8). Therefore: every Awake and Displays function is reachable from Settings (Awake status row with Start/Extend/End; Displays root live controls), hotkeys, the CLI, and the floating Displays panel; relaunching Snaptic while no item is *known* visible opens Settings (0.2 rule kept, extended to the Awake item); the Snaptic item and the Awake item have separate autosave names so the system and the user can place them independently; the countdown has an icon-only option to save notch space; no right-click, hover, programmatic highlight or occlusion dependence (C3).

### 5.6 Floating Displays panel

Restyled with the same `DisplayLiveControls` rows as the Displays root page (shared SwiftUI views from F); the "⋯" button opens the display's native submenu content as an `NSMenu` popped at the button (no mixed panel/menu blocks); footer buttons: Identify, Restore All Displays, Settings.

---

## 6. Files, ownership, CI, delivery

### 6.1 Teams

| Team | Owns |
|---|---|
| **Lead** | Contracts, stubs, CI, lint, Info.plist, Package.swift, Awake module shell, host wiring, cross-section migrations |
| **G — Awake core** | Awake Kit models and logic, sessions/assertions/guards/triggers/history/automation controllers, indicator and Awake menu, Awake settings pages |
| **J — Awake sources** | Criterion sources, PowerMonitor, SystemEventsMonitor, activity simulation, Drive Alive (+ Drives page) |
| **H — Settings UI** | SettingsUI library, Settings shell + search, General/Permissions/About pages, Onboarding, Window Switcher page |
| **M — Menu system** | MenuKit, MenuSliderRow, StatusMenu, Menu Bar page + Customize sheet, Displays menu builder/blocks, `ConfigMenu` |
| **A, B, C, D, E, F** (existing) | Their Displays controllers (observability, menu contributors on MenuKit) and the new pages/sections for their features (§4.3), per the table below; A also Switcher runtime changes |

### 6.2 Files (normative; every path goes into `scripts/stubs.tsv` with owner and kind in step 0; ⇢ = ownership moves; ✗ = deleted)

```
Lead:
  Package.swift (link CoreAudio, SystemConfiguration), Resources/Info.plist (0.3.0, NSRemovableVolumesUsageDescription),
  .github/workflows/build.yml, scripts/{lint.sh, stubs.tsv, gen-stubs.py}
  SnapticKit/KitModules.swift (ModuleID.awake, EventCategory.awake, AwakeActionID, AwakeCriterionKind; DisplayFeature −sleepPrevention)
  SnapticKit/AwakeFeatureGraph.swift (new), SnapticKit/FeatureGraph.swift (−sleepPrevention)
  SnapticKit/Config/ConfigAwake.swift (new), Config/ConfigDisplays.swift (M4, M5, changedSections, restoringDefaults),
  SnapticKit/Config/ConfigModules.swift (⇢ from A; MenuPresence, newModuleCards, M2, M3)
  Snaptic/Core/{ModuleContracts (settings contracts §4.1), ModuleContext (⇢ from A; hostSignals), HostSignals (new),
               ModuleHost (⇢ from A; Awake wiring, stores, M1 hook, Reset All)}.swift
  Snaptic/Awake/{AwakeModule, AwakeContext, AwakeContracts, AwakeRuntimeState}.swift (new)
  Snaptic/Displays/{DisplaysModule (fan-out by section), DisplaysRuntimeState (ControllerRevisions, DisplayRuntime fields,
               −sleepPreventionActive), DisplaysContracts (observedSections)}.swift

G (Kit, each with Tests/SnapticKitTests/<Name>Tests.swift):
  AwakeSession, AwakeClock, AwakeArbiter, AwakeGuards, AwakeTriggers, AwakeTriggerEngine, AwakeHistory, AwakeMigration,
  AwakeCommandGrammar, Config/ConfigAwakeSessions, Config/ConfigAwakeIndicator
G (app): Snaptic/Awake/Core/{AssertionManager, SessionController, GuardsController, TriggerController, Ticker,
               HistoryController, AwakeAutomation, AwakeDiagnostics}.swift
         Snaptic/Awake/UI/{IndicatorController, AwakeMenuBuilder, CustomSessionPanel, AwakePage, PresetEditorSheet,
               TriggerEditorSheet, CriterionEditors, AwakeAdvancedSheet, AwakeHistoryPage, SleepStatusSheet,
               AwakeOnboardingStep}.swift

J (Kit): CPUMath, NetworkMath (CIDR/IPv6 parse + match, MAC normalize), ActivityPolicy, DriveAlivePolicy,
         Config/ConfigAwakeDevices
J (app): Snaptic/Awake/Sources/{PowerMonitor, SystemEventsMonitor, AppMonitor, DisplayPresence, USBWatcher, VolumeMonitor,
               AudioMonitor, CPUSampler, IdleSampler, NetworkMonitor, BluetoothPresence, ActivitySimulator,
               DriveAliveService, OtherAssertionsReader}.swift
         Snaptic/Awake/Core/{ActivityController, DriveAliveController}.swift, Snaptic/Awake/UI/DrivesPage.swift

H (Kit): SliderMath, SettingsIndex
H (app): Snaptic/SettingsUI/{SettingsIcon, SettingsPageHeader, FeatureHighlights, SettingRow, ToggleSetting, SliderSetting,
               NumberField, StepperSetting, PickerSetting, InfoButton, NavigationRow, StatusRow, PerDisplayPicker,
               PageFooterButtons, AdvancedSheet, ReorderableList, AppListEditor, ShortcutSetting, SettingsAnchor,
               SettingsBinding, SettingsShell, SettingsSearchView}.swift
         Snaptic/Core/{SettingsWindowHost, GeneralPages, Onboarding}.swift (⇢ from A)
         Snaptic/Switcher/{SwitcherPages, SettingsView}.swift (⇢ from A)

M (Kit): MenuLayout (new), Config/ConfigMenu (⇢ from F; −showPanelShortcut/identifyShortcut after M4)
M (app): Snaptic/Core/{MenuKit, MenuSliderRow, MenuHostingRows, MenuBarPage, CustomizeMenuSheet}.swift (new),
         Snaptic/Core/{StatusMenu, MenuPlacement}.swift (⇢ from A), Core/MenuSliderItem.swift ✗,
         Snaptic/Displays/UI/{DisplaysMenuBuilder, DisplayMenuBlock}.swift (⇢ from F), Displays/UI/MenuCustomizationPage.swift ✗

F: Displays/UI/{DisplaysPage, DisplayLiveControls, DisplayDetailsSheet, DisplaysAdvancedSheet, DisplaysFeatureGroups,
               DisplayInformationView}.swift (new); DisplaysOverviewPage ✗, FeaturesPage ✗, DisplayIdentityPage ✗ (→ DetailsSheet),
               DiagnosticsPage ✗ (→ DisplayInformationView); OverviewController (panel restyle), DisplaysOnboardingStep;
   Kit DisplaysUIModel (groups, user titles, −sleepPrevention)
C: Displays/UI/{BrightnessSubpage, BrightnessSections, ColorPage, MonitorControlsPage, KeyboardIndicatorPage}.swift;
   BrightnessPage ✗ (→ Subpage/Sections), DDCPage ✗ (→ MonitorControlsPage), KeysPage ✗ + OSDPage ✗ (→ KeyboardIndicatorPage);
   BrightnessMenuItems, DDCMenuItems (MenuKit); controllers: runtime fields + revision bumps; Kit ConfigKeys (osdShowNits legacy)
D: Displays/UI/{ResolutionSections, MatchTextSizeSheet, ArrangeSheet, ArrangementCanvas, SavedLayoutsPage,
               VirtualDisplaysPage, VirtualDisplayEditorSheet, ConnectionSection}.swift; ResolutionPage ✗, ArrangementPage ✗,
               ProtectionLayoutsPage ✗, VirtualScreensPage ✗, ManagementPageParts ✗ (→ SettingsUI);
   ResolutionMenuItems, VirtualMenuItems, LayoutsMenuItems (MenuKit); PowerController (−sleep prevention), Kit ManagementIDs,
   Config/ConfigManagement (preventSleep decode-only)
E: Displays/UI/{PIPPage, PIPEditorSheet (new), PIPMenuItems}.swift
B: Displays/UI/ConfirmChangesSection.swift (new; SafetyPage ✗), PanicCoordinator (MenuKit items), Config/ConfigSafety (M6)
A: Displays/UI/{AutomationsPage, HookEditorSheet, ActionEditorSheet}.swift (AutomationPage ✗); Switcher/{SwitcherController (sticky
   mode C8), Settings (250 ms debounce)}.swift; Core/ControlCommandRegistry (protected list); Kit KitBackup (Awake omissions),
   KitControl (−sleepPrevention names)
```

Unique basenames are kept (e.g. `AwakePage` vs no other `AwakePage`; `PowerMonitor` (J) vs `PowerController` (D)). Lead adds `.awake` to the extension-placement lint allowlist (`SharedExtensions.swift` stays the only shared home).

### 6.3 CI and lint changes (lead, step 0)

- Linux job: new Kit files/tests build and run with Swift 5.10 (Foundation only).
- macOS job unchanged (Xcode 16.4, debug + tests + universal + helper self-test); Awake adds no helper, so no new self-test.
- `FeatureAvailability` moves from `DisplaysContracts.swift` to `Core/ModuleContracts.swift` (lead, step 0) so Awake doesn't depend on a Displays file.
- Lint additions:
  - L1 `IOPMAssertionCreate`/`IOPMAssertionRelease`/`IOPMAssertionSetProperty` only in `Awake/Core/AssertionManager.swift`.
  - L2 `IOPMAssertionDeclareUserActivity` and `.post(tap:` only in `Awake/Sources/ActivitySimulator.swift`; `keyboardEventSource`, `CGEvent(keyboardEvent` banned everywhere in Awake.
  - L3 No `Process(`, `posix_spawn`, `NSAppleScript`, `NSUserScriptTask`, `system(` under `Sources/Snaptic/Awake/`.
  - L4 Banned everywhere: `UNUserNotificationCenter`, `import CoreWLAN`, `import IOBluetooth`, `CLLocationManager`, the string literals `"pmset"` and `"sudo"`.
  - L5 `Slider(`, `Stepper(`, `.font(.caption)` + `.foregroundStyle(.secondary)` pairs only under `Sources/Snaptic/SettingsUI/` (and `ArrangementCanvas`, `MenuHostingRows`).
  - L6 `NSMenuItem(title:` and `NSMenuItem(` constructors only in `MenuKit.swift`/`MenuSliderRow.swift`/`MenuHostingRows.swift`.
  - L7 `objectWillChange.send()` banned in `Displays/UI/` and `Awake/UI/`; `State(initialValue:` banned in Settings views.
  - L8 Settings search: every `SettingsSearchEntry(... anchor: "x")` literal has a matching `.settingsAnchor("x")` (python scan), anchors unique.
  - L9 EventLog lines in `Awake/**` contain no string interpolation of variables named `name`, `bundleID`, `title` (heuristic).

### 6.4 Delivery order

| Step | Who (parallel) | Exit criterion |
|---|---|---|
| 0 | Lead | Every §6.2 file exists as a compiling stub with safe returns and exhaustive protocol members; `AwakeFeatureGraph` + `ConfigAwake` + migrations M2–M5 + `changedSections` + tests; ModuleHost runs the stub Awake module (no status item yet); ControllerRevisions + DisplayRuntime fields; HostSignals; Info.plist; lint L1–L9; green |
| 1 | G (Kit only) ∥ J ∥ H (library, shell, search, Kit) ∥ M (MenuKit, MenuSliderRow, StatusMenu with MenuPresence, MenuLayout) ∥ A (Switcher debounce, sticky mode) | Kit tests for G/J/H/M; sources activate/deactivate cleanly; shell shows all 8 roots with stub pages; StatusMenu renders existing sections through MenuKit; green, merged |
| 2 | G (controllers, assertion, sessions, guards, triggers, automation, indicator + Awake menu; lead runs M1 in ModuleHost) ∥ H (General, Permissions, About, Onboarding, Switcher page) ∥ M (Displays menu builder/blocks, Menu Bar page, Customize sheet) ∥ B/C/D/E (controller observability + revision bumps + MenuKit contributors) ∥ F (Displays root page, live controls, Details sheet, panel) | Awake works end to end from the menu, hotkeys and CLI; menus per §5; Displays root page live; green, merged |
| 3 | G (Awake page, editors, history, Advanced, Sleep Status) ∥ J (Drives page, nudge path, Bluetooth Beta) ∥ C/D/E/A/B/F (sub-pages and Advanced groups per §4.3; sleepPrevention removal by D + F; duplicates per §4.4) ∥ H (search index assembly, highlight, coverage of Advanced sheets) | Every §4.3 page meets its budget; every slider is a `SliderSetting`; search finds every entry; green, merged |
| 4 | Review | Adversarial reviews: security (§3), correctness (clock, guards, triggers, assertion swaps, migration), UX (copy rules, budgets, light/dark/Increase Contrast, VoiceOver), consistency (contracts vs code); fixes |
| 5 | Lead | README (Awake, CLI verbs and exit codes, privacy, "why not lid-closed on battery"), website, THIRD_PARTY_NOTICES (Insomnia, KeepingYouAwake if logic is followed closely; no code from APSL sources such as `caffeinate.c` — behavior only), Appendix hardware session, merge |

### 6.5 Done means

- Every In row of §1.1 and §1.5 implemented, reachable in Settings (and menu, hotkey and CLI where listed), wired to availability, kill switch, Safe Mode, diagnostics and `configDidChange`; idempotent start/stop; no stubs left.
- Awake holds at most one sleep assertion at any time (assert in debug + test via `AssertionManager` counters); `pmset -g assertions` shows only fixed-vocabulary strings.
- Every Settings slider is a `SliderSetting` with live value, typed field and reset; every slider in the menu is a `MenuSliderRow` with a live value; no slider in a submenu.
- Page budgets of §4.3 met; the 14 duplicates resolved as in §4.4; no developer titles, camelCase ids or raw SF Symbol names visible.
- Migrations M1–M6 tested; a 0.2 settings fixture (all features on) loads with no setting lost.
- Lint passes; CI green on all jobs; hardware list §6.7 run and Beta labels updated.

### 6.6 Kit unit tests (new)

- `AwakeFeatureGraph`: spec totality, resolve (kill switches, Safe Mode, requirements), `requiredServices` per criterion kind, activation order respects dependencies.
- `AwakeSession`/`AwakeClock`: start for every kind; remaining with continuous vs wall; reboot expiry; clock jumps ±1 day don't move duration sessions; until across DST change and time-zone change; extend caps at 30 days; indefinite/whileApp extend no-op; `untilTime` today vs tomorrow.
- `AwakeCountdown`: every format boundary (59:59, 1:00:00, 60 s, 59 s, 0), rounding up, `nextChange` never 0, spoken strings.
- `AwakeDurationGrammar` / `AwakeCommandGrammar`: valid and invalid inputs, limits, locale-independent parsing, fuzz (seeded).
- `AwakeArbiter`: governing precedence; every display policy × locked × console × idle; timeout grace; disk-idle flag; plan stable when nothing changes.
- `AwakeGuards`: desktop/no battery, AC, floor crossing, hysteresis +5, two unreadable reads, adapter disconnect, LPM, serious warn-once, critical end + cooldown, override only for battery/LPM.
- `AwakeTriggers` decode: lossy per entry, unknown kinds dropped, limits (32/8), sanitize (names, CIDRs, bundle ids, minutes).
- `TriggerEngine`: every criterion kind true/false/unknown; negation; all/any with unknowns; start/end delays; priority order and reorder; pause; guard hold; manual end with and without `resumeAfterManualEndMinutes`; overnight schedules and week wrap; `nextScheduleChange`; `summary` wording; seeded fuzz of random triggers/facts never crashes and is deterministic.
- `AwakeHistory`: cap, prune, totals across midnight and DST.
- `AwakeMigration`: no Displays settings; feature off with flags; feature on with 1 and 3 displays; missing fingerprints; corrupt JSON; idempotence.
- `AwakeConfig.protectedChanges`: nudge, preset/trigger activity → nudge, Drive Alive volume add/enable reverted; other changes pass.
- `NetworkMath`: IPv4/IPv6 CIDR parse/match, invalid input, MAC normalization and hashing input.
- `CPUMath`: tick deltas incl. wraparound; `ActivityPolicy` truth table; `DriveAlivePolicy` eligibility table.
- `SliderMath`: clamp/snap, isDefault tolerance, formats and spoken units, parse with units and both decimal separators.
- `SettingsIndex`: ranking, synonyms, diacritics, empty query, anchors unique across modules (test over the static indices exposed through Kit tables).
- `MenuLayout`: presence → sections, visibility rules (slider never "inSubmenu"), ordering, compact mode.
- `DisplaysConfig`: `changedSections` per field, M4/M5, `restoringDefaults(scope:)` leaves other scopes; `ModulesConfig` M2/M3 and `MenuPresence` plan.

### 6.7 Hardware checks (first session; Beta labels depend on them)

| # | Check |
|---|---|
| HW-1 | Both assertion types on 14/15/26/27, Intel + Apple silicon; `pmset -g assertions` rendering of name/details |
| HW-2 | `IOPMAssertionSetProperty(TimeoutSeconds)` re-arms from now; timeout behavior across system sleep |
| HW-3 | Assertion type swap (create-then-release) leaves no gap (display doesn't dim at the swap) |
| HW-4 | Screen saver and "require password after screen saver" with each assertion type and with `declare` |
| HW-5 | `IOPMAssertionDeclareUserActivity` vs `CGEventSourceSecondsSinceLastEventType` (does Slack/Teams go Away?) |
| HW-6 | ±1-pt nudge resets HID idle; not visible; Accessibility-denied path; tagged events ignored by switcher hover |
| HW-7 | `keepOnWhileActive` downgrade/upgrade timing; lock-screen downgrade (C1) actually lets the display sleep |
| HW-8 | Lid close on battery / AC / desktop mode; `AppleClamshellCausesSleep` values; wake path ends/continues sessions correctly |
| HW-9 | CoreAudio `DeviceIsRunningSomewhere` on input causes no microphone prompt or orange indicator |
| HW-10 | IOHIDDevice registry reads for Bluetooth input devices need no Input Monitoring |
| HW-11 | Router MAC via routing-table `sysctl` on 15/26/27 triggers no Local Network prompt |
| HW-12 | Removable Volumes prompt text and denial path; Drive Alive keeps a USB HDD spinning; eject not blocked |
| HW-13 | IOPS notifications on desktop Macs (no battery) and on battery percent changes; LPM notification |
| HW-14 | Status item `autosaveName`, `isVisible` KVO after ⌘-drag on 14–27; countdown width stability; 26 "Allow in the Menu Bar" off; 27 overflow |
| HW-15 | MenuKit hosting rows: text inset alignment with native items, slider keyboard behavior, `sectionHeader` look on 14/15/26/27; Option alternates on 27 |
| HW-16 | Settings: `.searchable(placement: .sidebar)` + `ScrollViewReader` scroll in grouped `Form` on 14; NavigationStack back button; `.toolbar(removing: .sidebarToggle)`; footer-only Section spacing |
| HW-17 | `NumberField` commit on blur inside `Form`; Esc revert; VoiceOver values with units |
| HW-18 | Thermal states (via a load generator) produce the toasts/ends; `CLOCK_MONOTONIC_RAW` advances across sleep |

### 6.8 Open questions

- **OQ-1** Should Drive Alive ignore CLI-started sessions (§3.1)? Default: no (user-chosen volumes only).
- **OQ-2** Default for `keepOnWhileActive` minutes (30) and whether it should be the default display policy instead of `keepOn` (battery-friendlier). Default: `keepOn`.
- **OQ-3** History on by default (S) vs opt-in. Default: on, local only, 90 days.
- **OQ-4** Whether the Displays root page keeps a Refresh rate pop-up when Resolution's pop-up already lists rates per mode. Default: keep (Apple precedent).
- **OQ-5** Glyph families: confirm the six symbols exist with `.fill` variants on macOS 14 (`mug` needs SF Symbols 4; fall back to `cup` if missing at runtime).
- **OQ-6** Sticky-switcher menu item (C8) interaction with `releaseToSwitch` users; fallback is to omit the item.

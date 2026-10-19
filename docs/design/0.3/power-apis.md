# Snaptic "Awake": Power, Trigger and Menu-Bar API Reference

Target: Swift 5 mode, AppKit/SwiftUI, deployment macOS 14, verified behavior needed on 14/15/26/27. Constraints: no root, no privileged helper, no network, hardened runtime, **no entitlements**, private API only via `dlsym` with fallback. Status tags: **[verified-src]** = read in Apple open-source/headers; **[doc]** = Apple docs/forums; **[verify]** = plausible but must be tested on device.

---

## 1. IOKit power assertions

### 1.1 Types (from `IOPMLib.h` / `IOPMLibPrivate.h`) [verified-src]

| String | Constant | Public? | Effect / caveats |
|---|---|---|---|
| `PreventUserIdleSystemSleep` | `kIOPMAssertPreventUserIdleSystemSleep` (alias `kIOPMAssertionTypePreventUserIdleSystemSleep`) | Yes, no privileges | Stops *idle* system sleep only. Header: "The system may still sleep for lid close, Apple menu, low battery, or other sleep reasons." Display may still sleep. No effect in Dark Wake. |
| `PreventUserIdleDisplaySleep` | `kIOPMAssertPreventUserIdleDisplaySleep` | Yes | Stops display dimming/sleep **and** implies no idle system sleep. Does not light a display that is already off. Display still sleeps on lid close. In practice also keeps the screensaver (and screensaver-triggered lock) from starting [verify]. |
| `PreventSystemSleep` | `kIOPMAssertionTypePreventSystemSleep` | Usable, but public header marks it "Deprecated in 10.9 … Do not use it" | Still honored by powerd and used by `caffeinate -s`. Private header: by default "applied only when system is running on unlimited power source" (AC). Making it apply on battery needs `kIOPMAssertionAppliesToLimitedPowerKey` + private entitlement `com.apple.private.iokit.assertonbattery`. Does **not** stop lid-close sleep. |
| `PreventDiskIdle` | `kIOPMAssertPreventDiskIdle` | Yes | Stops attached disks idling to low-power; does not spin a sleeping disk up; system may still sleep. |
| `NetworkClientActive` | `kIOPMAssertNetworkClientActive` | Yes | For servers with remote clients; AC: holds through dark wake. Not useful for Awake. |
| `NoIdleSleepAssertion`, `NoDisplaySleepAssertion` | `kIOPMAssertionTypeNoIdleSleep/NoDisplaySleep` | Deprecated 10.7 | Mapped to the modern types; don't use. |
| `UserIsActive` | `kIOPMAssertionUserIsActive` (private header) | Private string, but creatable | Backend of `IOPMAssertionDeclareUserActivity`; used directly by `caffeinate -u`. The lid-close modifier `kIOPMAssertionAppliesOnLidClose` requires private entitlement `com.apple.private.iokit.assertonlidclose`, and powerd rejects unentitled callers ("Pid %d is not privileged to set property"). |

Nothing third-party can get past lid-close sleep using assertions alone (see §2).

### 1.2 Creation APIs
- `IOPMAssertionCreateWithName(type, level, name, &id)`: simplest. Name is required and capped at 128 chars.
- `IOPMAssertionCreateWithDescription(type, name, details, humanReadableReason, bundlePath, timeout, timeoutAction, &id)`: what caffeinate uses. If you pass `HumanReadableReason` you must also pass a bundle path that has the localization.
- `IOPMAssertionCreateWithProperties(dict, &id)`: full control. Keys are `AssertType`, `AssertName` (both required), `AssertLevel` (defaults to On = 255), `Details`, `HumanReadableReason`, `BundlePath`, `TimeoutSeconds`, `TimeoutAction`.
- `IOPMAssertionSetProperty(id, key, value)`: updates `Details` or re-arms `TimeoutSeconds` on a live assertion, which is what an "extend session" feature needs.
- `IOPMAssertionRelease(id)`: decrements the CF-style retain count. The assertion dies at zero.

**Timeouts** [verified-src]: `kIOPMAssertionTimeoutKey` = "outer bound, in seconds". The default action is **`TimeoutActionTurnOff`**: the level goes to Off but the assertion object stays alive, so you still have to release it. `TimeoutActionRelease` frees it, and `TimeoutActionLog` only logs. **Always use `TimeoutActionRelease`** for timed sessions. Expiry then holds even if Snaptic hangs or gets App-Napped. powerd posts `com.apple.system.powermanagement.assertions.timeout` on expiry.

**Crash semantics** [verified-src]: powerd watches every client pid with `DISPATCH_SOURCE_TYPE_PROC`/`DISPATCH_PROC_EXIT`. `HandleProcessExit()` then releases all of that pid's assertions and logs them as client-death (`pmset -g assertionslog`). In-process assertions therefore cannot leak past a crash. A spawned `/usr/bin/caffeinate` child **can** outlive you, so KeepingYouAwake passes `-w <own pid>`. Note: `kIOPMAssertionOnBehalfOfPID` is accounting only, and "no action is taken when [it] dies".

**Visibility**: `pmset -g assertions` lists them per pid, e.g. `pid 812(Snaptic): [0x…] 00:12:03 PreventUserIdleDisplaySleep named: "Snaptic Awake"`, followed by a `Details:` line and `Timeout will fire in N secs Action=TimeoutActionRelease` (format illustrative). Activity Monitor › Energy › "Preventing Sleep" column shows Yes. Put the trigger in `Details` (for example "Trigger: Xcode running") so power users can tell why.

### 1.3 `caffeinate` internals [verified-src: PowerManagement/caffeinate/caffeinate.c]
- `-i` → `PreventUserIdleSystemSleep` (the default when no flag is given). `-d` → `PreventUserIdleDisplaySleep`. `-s` → `PreventSystemSleep` (AC only). `-m` → `PreventDiskIdle`. `-u` → `UserIsActive` via `IOPMAssertionCreateWithDescription`, with a **forced 5 s timeout** when `-t` is absent. It does *not* call `IOPMAssertionDeclareUserActivity`.
- Name: `"caffeinate command-line tool"`. `-t` is passed as the assertion timeout with `kIOPMAssertionTimeoutActionRelease`, plus a `dispatch_after(exit)` when no command is given. `-w pid` uses a `DISPATCH_PROC_EXIT` source and tags `kIOPMAssertionOnBehalfOfPID`.
- In command mode it forks: the child holds the assertions and the original process execs the command.

### 1.4 `IOPMAssertionDeclareUserActivity` vs `ProcessInfo.beginActivity`
- `DeclareUserActivity(name, kIOPMUserActiveLocal, &id)` "causes the display to power on and postpone display sleep, up to the user's display sleep … settings". Pass the returned id back on later calls. It **turns the display on**, so never call it on a timer while the user has deliberately darkened the screen. It is a one-shot idle-timer reset, not a hold.
- `ProcessInfo.beginActivity(options:reason:)`: `.idleDisplaySleepDisabled` / `.idleSystemSleepDisabled` create the matching IOPM assertions, with the reason string as the name [verify exact `pmset` rendering]. `.userInitiated` includes idle-system-sleep-disabled and also disables App Nap and sudden termination. You must keep the token and call `endActivity`. There is no timeout and no Details field. Use raw IOKit for Awake (timeouts, details, crash-safe expiry). `beginActivity` is fine for short internal work.

### 1.5 Core snippet

```swift
import IOKit.pwr_mgt

enum AwakeMode { case system, display }   // display ⊃ system

final class AssertionHolder {
    private(set) var id: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

    @discardableResult
    func acquire(_ mode: AwakeMode, details: String, timeout: TimeInterval?) -> Bool {
        release()
        var props: [String: Any] = [
            "AssertType": mode == .display ? "PreventUserIdleDisplaySleep" : "PreventUserIdleSystemSleep",
            "AssertName": "Snaptic Awake",
            "AssertLevel": NSNumber(value: kIOPMAssertionLevelOn),
            "Details": details,
        ]
        if let t = timeout, t > 0 {
            props["TimeoutSeconds"] = NSNumber(value: t)
            props["TimeoutAction"] = "TimeoutActionRelease"   // not the TurnOff default
        }
        var newID = IOPMAssertionID(0)
        let kr = IOPMAssertionCreateWithProperties(props as CFDictionary, &newID)
        guard kr == kIOReturnSuccess else { return false }
        id = newID
        return true
    }

    func updateDetails(_ s: String) {
        guard id != 0 else { return }
        IOPMAssertionSetProperty(id, "Details" as CFString, s as CFString)
    }

    func extend(to seconds: TimeInterval) {          // re-arm [verify: counts from now]
        guard id != 0 else { return }
        IOPMAssertionSetProperty(id, "TimeoutSeconds" as CFString, NSNumber(value: seconds))
    }

    func release() {
        if id != 0 { IOPMAssertionRelease(id); id = 0 }
    }
    deinit { release() }
}
```

Using string literals avoids relying on Swift's import of `CFSTR` macros. If the timeout fires, `id` goes stale and releasing it later just returns an error. To keep UI state accurate, check `IOPMCopyAssertionsByProcess` or register for the timeout notify name.

**Gotchas**: (1) Apple-menu Sleep, lid close, low-battery and thermal-emergency sleep all override these assertions. (2) Keep **one** assertion per mode and swap it on change rather than stacking several. (3) Timers pause during system sleep: on `NSWorkspace.didWakeNotification`, recompute the remaining time from a wall-clock deadline. (4) Hold only the assertion actually needed. Display mode costs much more battery.

---

## 2. Closed-lid (clamshell)

**What powerd does** [verified-src: `PMAssertions.c: setClamshellSleepState`]: lid-close sleep is disabled only if (a) **desktop mode**, meaning external display + AC power (the log reads "DesktopMode with AC"), or (b) an active `UserIsActive`/tickless-display-wake assertion carries the entitled lid modifier, or (on arm64) a WindowServer hot-plug assertion does, or (c) the kernel `SleepDisabled` flag is set (`pmset -a disablesleep 1`, root). Apple's supported closed-display mode = AC + external display (+ external keyboard/mouse, per Apple support). `PreventSystemSleep` does **not** survive lid close. Sleepless and the Adrafinil HN discussion confirm this empirically: assertions "stop the idle timer but can't override the hardware lid-close trigger."

**What's achievable without root**:
1. Detect and explain: show "Closing the lid will sleep: Yes/No" from `AppleClamshellCausesSleep`, and guide the user into supported clamshell mode.
2. When a lid-close sleep is coming, end or pause the session cleanly. There is no API that vetoes it.
3. Optional and explicitly outside the core constraints: `pmset -a disablesleep 1/0` through an admin prompt (`NSAppleScript` "do shell script … with administrator privileges"), each time. Insomnia and Sleepless instead install a **sudoers NOPASSWD rule**, and Insomnia's own README warns that any user process can then use it. Amphetamine on Apple silicon needs an installed "closed-display mode script", plus "Power Protect" for authentication-free execution. Without the script, sessions break when power is connected or disconnected. **Amphetamine Enhancer** is a separate notarized, non-sandboxed helper. It adds a "fail-safe for the closed-display mode feature" (restoring sleep if Amphetamine dies) and full process listing for triggers. Snaptic needs no Enhancer equivalent for process listing because it is not sandboxed. If disablesleep is ever offered: write a recovery journal before flipping it (Insomnia's approach), add a launchd agent check, battery floor, thermal cutoff and session-end revert, and read the state back by parsing `pmset -g` (`SleepDisabled 1`).

**Risks**: a closed lid reduces airflow, and fanless Airs use the chassis as a heatsink. In a bag a Mac can overheat and thermal-shut-down. Sustained heat at high charge accelerates battery ageing. Guard on `ProcessInfo.thermalState >= .serious`, on battery %, and on `AppleSmartBattery` `Temperature` in IORegistry (hundredths of °C [verify units]). SMC sensor reads go through a semi-private user client, so avoid them.

**Lid state & change notifications** (public IOKit, no TCC):

```swift
import IOKit

final class LidMonitor {
    private var port: IONotificationPortRef?
    private var note: io_object_t = 0
    private let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    var onChange: ((_ closed: Bool, _ causesSleep: Bool) -> Void)?

    /// nil = no lid (desktop Mac)
    var isClosed: Bool? { prop("AppleClamshellState") }
    var lidCloseWillSleep: Bool? { prop("AppleClamshellCausesSleep") }

    private func prop(_ key: String) -> Bool? {
        IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    func start() {
        port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, .main)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { ctx, _, type, arg in
            // kIOPMMessageClamshellStateChange = iokit_family_msg(sub_iokit_powermanagement, 0x100)
            guard type == 0xE003_4100, let ctx = ctx else { return }
            let bits = UInt(bitPattern: arg)            // kClamshellStateBit=1, kClamshellSleepBit=2
            let me = Unmanaged<LidMonitor>.fromOpaque(ctx).takeUnretainedValue()
            me.onChange?(bits & 1 != 0, bits & 2 != 0)
        }, ctx, &note)
    }
    deinit {
        if note != 0 { IOObjectRelease(note) }
        if let p = port { IONotificationPortDestroy(p) }
        IOObjectRelease(root)
    }
}
```

---

## 3. Power source, battery, Low Power Mode, thermal

```swift
import IOKit.ps

struct PowerSnapshot { let onAC: Bool; let percent: Int?; let charging: Bool }

func readPower() -> PowerSnapshot {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
        return .init(onAC: true, percent: nil, charging: false)
    }
    let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
    let onAC = (type ?? kIOPMACPowerKey) == kIOPMACPowerKey
    let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
    for ps in list {
        guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let cur = d[kIOPSCurrentCapacityKey] as? Int,
              let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
        return .init(onAC: onAC, percent: cur * 100 / max,
                     charging: d[kIOPSIsChargingKey] as? Bool ?? false)
    }
    return .init(onAC: onAC, percent: nil, charging: false)   // desktop: no battery
}

// Change notifications: notify(3) is easier in Swift than IOPSNotificationCreateRunLoopSource
var psToken: Int32 = 0
notify_register_dispatch(kIOPSNotifyPowerSource, &psToken, .main) { _ in /* re-read */ }
var pctToken: Int32 = 0
notify_register_dispatch(kIOPSNotifyPercentChange, &pctToken, .main) { _ in /* re-read */ }
```

`IOPSNotificationCreateRunLoopSource(cb, ctx)` also works (KeepingYouAwake uses it), but it needs a `@convention(c)` callback and a context pointer. Other sources:
- **Low Power Mode**: `ProcessInfo.processInfo.isLowPowerModeEnabled` (macOS 12+), with change notification `.NSProcessInfoPowerStateDidChange` (KeepingYouAwake ends sessions on it). Setting LPM requires `pmset -a lowpowermode 1` as root, so it is out of scope. On Tahoe, LPM caps full-screen vsync apps at 30 fps (forums 795447), which matters for any "presentation" trigger.
- **Thermal**: `ProcessInfo.processInfo.thermalState` (`.nominal/.fair/.serious/.critical`) with `ProcessInfo.thermalStateDidChangeNotification`.

Policy: battery-floor end (default 10–20%), optional "only on AC", end on LPM, end on `.critical` heat.

---

## 4. Trigger detection

| Trigger | API | TCC / entitlement | Notes |
|---|---|---|---|
| App running | `NSWorkspace.shared.runningApplications`, `didLaunchApplicationNotification`, `didTerminateApplicationNotification` | none | Faceless processes (CLI, daemons) aren't listed. Use `proc_listallpids` + `proc_pidpath`/`proc_name` (libproc) and poll. |
| Frontmost app | `didActivateApplicationNotification`, `frontmostApplication` | none | |
| Download in progress | Watch the Downloads folder (or a user-picked one): FSEvents (`kFSEventStreamCreateFlagFileEvents`) or `DispatchSource.makeFileSystemObjectSource`, plus marker extensions `.crdownload` (Chrome/Edge), `.download` bundles (Safari), `.part` (Firefox), and **size growth across ≥2 samples** | **TCC Downloads-folder prompt** (`NSDownloadsFolderUsageDescription` needed) | Amphetamine offers "While a file is downloading" as a session type but doesn't document how it detects it. A no-TCC fallback: network throughput from `getifaddrs` `if_data.ifi_ibytes` deltas ("keep awake while download rate > X KB/s for N min"). |
| External display / mirroring | `NSApplication.didChangeScreenParametersNotification` or `CGDisplayRegisterReconfigurationCallback`. Count `CGGetOnlineDisplayList` entries where `!CGDisplayIsBuiltin`. `CGDisplayIsInMirrorSet` for mirroring | none | Sidecar/AirPlay/DisplayLink show up as displays. |
| Wi-Fi SSID | `CWWiFiClient.shared().interface()?.ssid()` | **Location authorization** (since macOS 14: "SSID information is not available unless Location Services is enabled and the user has authorized the calling app"). Under hardened runtime this also needs the **`com.apple.security.personal-information.location` entitlement** | Incompatible with "no entitlements", so **drop the SSID trigger**, or ship it as a separately signed opt-in. `ipconfig getsummary` output is redacted too [verify]. Alternatives with no TCC: SystemConfiguration (`SCDynamicStore` keys `State:/Network/Global/IPv4` → router IP/primary interface, `State:/Network/Global/DNS`), subnet/IP match (Amphetamine offers IP and DNS triggers), and router MAC from the ARP table via `sysctl(NET_RT_FLAGS)` [verify that macOS 15 Local Network privacy doesn't apply]. `CWEventDelegate` link/SSID-changed events still fire as "network changed" signals. |
| VPN | `SCDynamicStore` notification on `State:/Network/Interface/.*/IPv4`. VPN = `utun*`/`ipsec*`/`ppp*` with an IPv4 address, or `PrimaryInterface` = `utun*`. `NWPathMonitor` is an alternative | none | macOS always has several idle `utun` interfaces (Private Relay, Continuity), so require an address. |
| USB device | `IOServiceAddMatchingNotification(port, kIOFirstMatchNotification / kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"), …)`. Read `USB Product Name`, `idVendor`, `idProduct`, `USB Serial Number` | none | Each call consumes its matching dict, so create one per notification type. **Drain the iterator immediately** or the notification never arms. |
| Bluetooth device | `IOBluetoothDevice.register(forConnectNotifications:selector:)` | **Bluetooth TCC** (`NSBluetoothAlwaysUsageDescription`). Without the key the process may be killed [verify for IOBluetooth] | No-TCC alternatives: BT audio via CoreAudio device list with `kAudioDevicePropertyTransportType == kAudioDeviceTransportTypeBluetooth/BluetoothLE`. BT HID via IOKit matching on `IOHIDDevice` with `Transport` = "Bluetooth" (registry properties only; *opening* a HID device needs Input Monitoring). |
| CPU usage | System: `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas. Per process: `proc_pid_rusage(pid, RUSAGE_INFO_V4)` `ri_user_time + ri_system_time` deltas | none (same-user processes; others' may fail with EPERM [verify]) | `ri_*_time` values are **mach-absolute units**, so convert with `mach_timebase_info` (on arm64 the ratio is 125/3 and the raw values are not ns). Cache `mach_host_self()`, which leaks a send right per call. |
| Audio playing | Default output device `kAudioDevicePropertyDeviceIsRunningSomewhere`, with `AudioObjectAddPropertyListenerBlock` | none | Means "IO engine running", not audible: apps (browsers, Teams) keep it running while silent. Input device + same property = mic in use. Per-process: `kAudioHardwarePropertyProcessObjectList` / `kAudioProcessPropertyIsRunningOutput` (14.2+) [verify no TCC]. |
| User idle time | `CGEventSourceSecondsSinceLastEventType(.combinedSessionState, CGEventType(rawValue: UInt32.max)!)` (= `kCGAnyInputEventType`), or IORegistry `IOHIDSystem` → `HIDIdleTime` (ns) | none | Poll every 5–30 s, since there is no notification. |
| Screen lock / screensaver | `DistributedNotificationCenter`: `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`, `com.apple.screensaver.didstart/didstop`. Current state: `CGSessionCopyCurrentDictionary()` → `"CGSSessionScreenIsLocked"`. Also `NSWorkspace.screensDidSleep/DidWake`, `willSleep/didWake`, `sessionDidResignActive/BecomeActive` | none | Notification names are undocumented but Chromium relies on them (`ui/base/idle/idle_mac.mm`). |
| Mounted volume | `NSWorkspace.didMountNotification` / `didUnmountNotification` (`volumeURLUserInfoKey`). Identify by `URLResourceKey.volumeUUIDStringKey`. DiskArbitration (`DARegisterDiskAppearedCallback`) for unmounted disks | none for listing | Reading or writing *contents* triggers Removable/Network Volumes TCC. |
| Schedule | Wall-clock evaluator with `DateComponents`, re-evaluated on a minute timer + `didWakeNotification` + `.NSSystemClockDidChange` + `.NSSystemTimeZoneDidChange` + `.NSCalendarDayChanged` | none | Waking the Mac at a scheduled time (`IOPMSchedulePowerEvent`, `pmset schedule`) needs root, so schedules apply only while awake. |

Evaluate triggers in one engine. Sessions are the OR of active triggers, each one adds its reason to `Details`, and a hysteresis/grace period (e.g. 30–60 s) stops flapping.

```swift
// USB example
final class USBWatcher {
    private let port = IONotificationPortCreate(kIOMainPortDefault)!
    private var addIter: io_iterator_t = 0
    var onAdd: ((_ name: String, _ vid: Int, _ pid: Int) -> Void)?

    func start() {
        IONotificationPortSetDispatchQueue(port, .main)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification,
            IOServiceMatching("IOUSBHostDevice"), { ctx, it in
                Unmanaged<USBWatcher>.fromOpaque(ctx!).takeUnretainedValue().drain(it)
            }, ctx, &addIter)
        drain(addIter)   // arms the notification and reports devices already present
    }
    private func drain(_ it: io_iterator_t) {
        while case let svc = IOIteratorNext(it), svc != 0 {
            defer { IOObjectRelease(svc) }
            func p(_ k: String) -> Any? {
                IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            onAdd?(p("USB Product Name") as? String ?? "USB device",
                   p("idVendor") as? Int ?? 0, p("idProduct") as? Int ?? 0)
        }
    }
}
```

---

## 5. "Simulate activity" (mouse jiggle)

- **What chat apps measure**: Chromium/Electron (Slack, the Chromium-based new Teams [verify for current Teams build]) compute idle as `CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType)` (Chromium `idle_mac.mm`, read directly), and they treat a running screensaver or a locked screen as idle.
- **`IOPMAssertionDeclareUserActivity` / `caffeinate -u`** reset powerd's display/idle-sleep timers. They do *not* post HID events, so WindowServer's last-event timestamps should not change, and Slack/Teams will likely still go "Away" [verify on a test harness that logs `CGEventSourceSecondsSinceLastEventType` before and after the call]. An assertion is enough to keep the Mac and display awake. Keeping a presence indicator green needs real posted events.
- **CGEvent posting** resets those counters but needs the **Accessibility / "PostEvent" TCC** grant (`CGPreflightPostEventAccess()` / `CGRequestPostEventAccess()`, 10.15+). It needs no entitlement. Posted events don't reach secure-input fields and don't unlock a locked session.

```swift
func nudgeActivity() -> Bool {
    guard CGPreflightPostEventAccess() else { _ = CGRequestPostEventAccess(); return false }
    let src = CGEventSource(stateID: .hidSystemState)
    let here = CGEvent(source: nil)?.location ?? .zero          // global, top-left origin
    // zero-delta move: no visible jump [verify it resets idle; else +1pt then back]
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
            mouseCursorPosition: here, mouseButton: .left)?.post(tap: .cghidEventTap)
    return true
}
```

Security and ethics: an Accessibility grant lets the app drive the entire UI. Keep the feature opt-in and isolated, explain the grant, show how to revoke it, and **never synthesize key events**, which could type into the focused app. Faking presence may break employer policy. MDM can block the grant (PPPC). Skip nudges while the screen is locked or the user is active (idle < interval). Amphetamine offers "Move the mouse cursor periodically" separately from its sessions.

---

## 6. Drive Alive (external disks)

- `PreventDiskIdle` (`caffeinate -m`) applies to **all** disks, doesn't wake a disk that is already asleep, and is **ignored by USB/Thunderbolt enclosure firmware** that runs its own spin-down timer (often 5–30 min). It is not sufficient on its own.
- What works: **periodic real I/O**. Write a tiny hidden file `/<vol>/.snaptic-keepalive` every 60–240 s (below the drive's timer, user-configurable), opened `O_WRONLY|O_CREAT`, followed by `fcntl(fd, F_FULLFSYNC)` so it reaches the media. Alternatively read a random block with `F_NOCACHE`. Reads served from the buffer cache don't touch the disk.
- Gotchas: the first write to an external volume triggers the **Removable Volumes** (or Network Volumes) TCC prompt. Add `NSRemovableVolumesUsageDescription`/`NSNetworkVolumesUsageDescription`. Skip read-only volumes (`volumeIsReadOnlyKey`), Time Machine destinations and disk images. Stop on `willUnmount` so the file doesn't block ejection. Combine with `PreventUserIdleSystemSleep`, because a sleeping Mac spins disks down anyway. Let SSD users turn it off.

---

## 7. Locking the screen

1. **Private, best UX**: `SACLockScreenImmediate()` in `login.framework`, resolved at runtime. Under hardened runtime this is fine: library validation accepts Apple-signed system code, and `dlopen` resolves the path from the dyld shared cache even though no file exists on disk.

```swift
func lockScreen() {
    typealias Fn = @convention(c) () -> Int32
    if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
       let s = dlsym(h, "SACLockScreenImmediate") {
        _ = unsafeBitCast(s, to: Fn.self)(); return
    }
    // Fallback 1: display sleep. Locks only if "Require password after … display is turned off" is set to Immediately
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["displaysleepnow"]; try? p.run()     // no root needed
}
```

2. Public-ish fallbacks: `pmset displaysleepnow` (above). Launching `/System/Library/CoreServices/ScreenSaverEngine.app` with `NSWorkspace.openApplication`, which locks depending on the same Lock Screen setting. A synthetic ⌃⌘Q needs Accessibility. `CGSession -suspend` is gone since Big Sur. Read the "require password" delay so the UI can warn when a fallback won't actually lock [verify where it lives on 14+, which uses a sysadminctl/`com.apple.screensaver` move].
3. "Lock after inactivity": idle time (§4) > threshold **and** no Awake session active, then lock. Release the display assertion *before* locking.

---

## 8. Menu-bar status items

- **Multiple items**: call `NSStatusBar.system.statusItem(withLength:)` once per item. Keep strong references, because a released item disappears. Give each a stable `autosaveName` (persists position and `isVisible` in defaults; renaming it loses the saved position) and set `behavior = [.removalAllowed]` so ⌘-drag removal is observable through `isVisible` KVO. Per Apple DTS, that is the only way to learn the user removed the item: **there is no API to read the macOS 26 "Allow in the Menu Bar" toggle** (FB18341478).
- **Countdown**: use `NSStatusItem.variableLength`. Set `button.attributedTitle` with `NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)` so the width doesn't jitter, `imagePosition = .imageLeading`, and template SF Symbols (`image.isTemplate = true`). Display `h:mm` and switch to `m:ss` only under 10 min, to save menu-bar space and wakeups. Drive updates from a deadline `Date` with `Timer` tolerance ≥ 10%. Every item fights for notch space, and on 26/27 an overflowing item is hidden, so offer an "icon only" option.
- **SF Symbol animation**: `NSStatusBarButton` takes static images. To animate, add an `NSImageView` subview and call `addSymbolEffect(.pulse)` (macOS 14+), or swap symbol variants on a timer. Honor `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`. A SwiftUI `MenuBarExtra` label is rasterized, so effects there are unreliable [verify].
- **Accessibility**: call `button.setAccessibilityLabel("Awake, 42 minutes remaining")` and update it on *state* changes, not every second. Give the image an `accessibilityDescription`. Make every menu action keyboard-reachable.
- **macOS 26 Tahoe**: System Settings › Menu Bar has per-app "Allow in the Menu Bar" toggles, and items that don't fit are hidden. Tahoe also adds Control Center/menu-bar *controls* (WidgetKit `ControlWidget`). Those require a sandboxed extension, which means entitlements, so they're out of scope. App Intents (Shortcuts/Spotlight "Start Awake for 1 h") need no entitlement and are a good substitute.
- **macOS 27 "Golden Gate"** (from WWDC26 and the beta-era forums. **Retest on 27.0/27.1**):
  - The whole menu bar now renders in a single window, so Bartender, Ice and Hidden Bar broke. An overflow chevron near the notch reveals hidden items.
  - New API: `NSStatusItem.expandedInterfaceDelegate` (macOS 27+) with `NSStatusItemExpandedInterfaceDelegate.statusItem(_:didBegin:)` / `statusItemDidEndExpandedInterfaceSession(_:animated:)`, and `statusItem.expandedInterfaceSession?.cancel()`. "Status items that assign an NSMenu … don't receive expanded interface callbacks — the system handles [it] automatically."
  - Reported regressions: right-click no longer delivered to the item, toggle-close click missing, `button.highlight(true)` has no effect, hover/tracking areas broken until beta 5, `button.window.occlusionState` no longer reflects hiding (FB23349447), dropping files on the item triggers Mission Control, and no touch-outside detection for custom panels.
  - **Recommendation**: give each item a plain `statusItem.menu = NSMenu` (works the same on 14–27). Put alternate actions in the menu as Option-key alternates (`isAlternate`), not on right-click. If a custom panel is needed on 27, adopt the delegate behind `#available(macOS 27, *)`, which requires building with the 27 SDK.

---

## 9. macOS 26/27 changes summary
- **Assertions**: no documented API or behavior changes found. Current `IOPMLib.h` and powerd source still show the same types, timeouts and client-death cleanup. Retest `PreventSystemSleep` (marked deprecated in the header but honored) on each release.
- **Low Power Mode**: the API is unchanged. On Tahoe, LPM throttles full-screen vsync to 30 fps. No macOS 27 change was found.
- **Menu bar**: see §8. 27 is the riskier release. Beta forum threads: 832823, 836113.
- **Wi-Fi**: the SSID/Location requirement continues (reports through 15.x), so assume it still holds on 26/27.

## 10. Top gotchas checklist
1. Assertions never beat lid close, Apple-menu sleep, low battery or thermal sleep.
2. Use `TimeoutActionRelease`. The default `TurnOff` leaves a zombie assertion.
3. Prefer in-process assertions to spawning `caffeinate`. If you spawn it, always pass `-w $PID`.
4. Recompute deadlines after wake. App Nap can delay UI timers, so don't let correctness depend on them.
5. `DeclareUserActivity` turns the display on. Never loop it while the screen is deliberately off.
6. The SSID trigger needs Location TCC **and** a hardened-runtime entitlement, so it is not shippable under the constraints.
7. Downloads-folder, removable-volume, Bluetooth and Accessibility features each cost a TCC prompt. Request each lazily, only when the user enables that trigger.
8. `ri_user_time` is in mach ticks. IOKit matching iterators must be drained.
9. On macOS 27, don't rely on right-click, hover, programmatic highlight or occlusion for status items.

---

## Sources
- Apple open source: [IOPMLib.h](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h), [IOPMLibPrivate.h](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLibPrivate.h), [caffeinate.c](https://github.com/apple-oss-distributions/PowerManagement/blob/main/caffeinate/caffeinate.c), [PMAssertions.c (HandleProcessExit, setClamshellSleepState)](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmconfigd/PMAssertions.c), [IOPMAssertions.c (older)](https://opensource.apple.com/source/IOKitUser/IOKitUser-1178.1.4/pwr_mgt.subproj/IOPMAssertions.c.auto.html)
- Apple: [expandedInterfaceDelegate](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate), [WWDC26 289 "Modernize your AppKit app"](https://developer.apple.com/videos/play/wwdc2026/289/), [QA1340](https://developer.apple.com/library/archive/qa/qa1340/_index.html), [NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar)
- Developer Forums: [Detect disallowed menu bar item (788101)](https://developer.apple.com/forums/thread/788101), [NSStatusItem interactions on 27 (832823)](https://developer.apple.com/forums/thread/832823), [Various NSStatusItem issues on 27 (836113)](https://developer.apple.com/forums/thread/836113), [MenuBarExtra not showing on 26 (794920)](https://developer.apple.com/forums/thread/794920), [SSID requires Location (732431)](https://developer.apple.com/forums/thread/732431), [CoreWLAN nil SSID 14.4 (748518)](https://developer.apple.com/forums/thread/748518), [scanForNetworks SSIDs on 15.1 (769950)](https://developer.apple.com/forums/thread/769950), [LPM 30 fps on Tahoe (795447)](https://developer.apple.com/forums/thread/795447)
- Chromium [ui/base/idle/idle_mac.mm](https://github.com/chromium/chromium/blob/main/ui/base/idle/idle_mac.mm); [Electron powerMonitor](https://electronjs.org/docs/latest/api/power-monitor)
- Open-source apps: [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) (spawns `caffeinate -di -t -w`, IOPS run-loop source, LPM monitor), [Insomnia](https://github.com/krishhgg/Insomnia) (pmset disablesleep via sudoers, recovery journal, launchd recovery, SIGSTOP freezing), [Sleepless](https://github.com/Aboudjem/Sleepless), [Amphetamine Enhancer](https://github.com/x74353/Amphetamine-Enhancer), [Amphetamine (App Store)](https://apps.apple.com/app/amphetamine/id937984704), [Amphetamine 5.3.1 closed-display script](https://softantenna.com/blog/?p=115581), [Adrafinil HN thread](https://hn.svelte.dev/item/48701512)
- News: [Badgeify on macOS 27 menu bar](https://badgeify.app/macos-27-golden-gate-menu-bar-changes/), [MacRumors macOS 27 menu items](https://macrumors.com/2026/06/11/macos-27-golden-gate-menu-items/)

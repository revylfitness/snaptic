# Snaptic "Displays" module: macOS display API research (macOS 14 / 15 / 26)

Research date: 2026-10-17. Scope: what a SwiftPM, non-sandboxed, hardened-runtime AppKit/SwiftUI app needs to match
BetterDisplay / BetterDisplay Pro. All code we ship is new; GPL projects were *not* read beyond README-level descriptions.

## 0. How to read this document

Confidence tags used throughout:

- **[V]** verified against a primary source: Apple documentation, or source code read for this report (file named).
- **[O]** observed in shipping permissive OSS (the code works in the field) but not documented by Apple.
- **[U]** unverified. This covers community claims, single-source measurements, or my inference. Probe it at runtime and test it on real hardware before relying on it.

"AS" means Apple silicon. "Intel" means x86_64 Macs with IOFramebuffer.

### 0.1 Reference projects and licenses (checked 2026-10-17)

| Project | License | What it is useful for | Notes |
|---|---|---|---|
| MonitorControl/MonitorControl (HEAD 2026-10-14) | **MIT** | AS + Intel DDC, DisplayServices brightness, gamma dimming, overlay "shade", OSD (incl. macOS 26 path), media keys | Read: `Support/Arm64DDC.swift`, `IntelDDC.swift`, `DisplayManager.swift`, `OSDUtils.swift`, `Model/Display.swift`, `OtherDisplay.swift`, `Bridging-Header.h` |
| waydabber/m1ddc (HEAD 2026-08) | **MIT** | AS DDC framing, display↔DCPAVServiceProxy matching via IORegistry path, **M1/M2 built-in HDMI (MCDP29xx, chip 0xB7)** | Read: `sources/i2c.m`, `sources/ioregistry.m` |
| waydabber/AppleSiliconDDC | **MIT** | Swift AS DDC library | README notes that the M1 HDMI support is not in the open code |
| waydabber/BetterDummy, branch `opensource` (≤ 2022-02) | **MIT** | CGVirtualDisplay usage, CGS mode structs | Later BetterDisplay is closed source |
| Stengo/DeskPad | **MIT** | Virtual display, plus streaming it into a window (uses deprecated CGDisplayStream) | `CGVirtualDisplayPrivate.h`, `ScreenViewController.swift` |
| jakehilborn/displayplacer | **MIT** | CGS mode enumeration, `CGSConfigureDisplayEnabled`, rotation via MonitorPanel `MPDisplay` | Ships class-dumped MonitorPanel headers |
| sammcj/force-hidpi (2026) | **MIT** | **SwiftPM** app on macOS 26: virtual display at 2x plus hardware mirror for HiDPI on M4/M5, HDR (PQ) virtual mode | Closest analogue to Snaptic's build setup |
| go-macos/virtualdisplay (2026) | **BSD-3** | Careful measurements of CGVirtualDisplay behaviour on macOS 26.6.2 | Single-source findings, tagged [U] |
| Chromium `ui/display/mac/test/virtual_display_util_mac.mm` | **BSD-3** | CGVirtualDisplay declarations (incl. `serialNumber`, `rotation`, `transferFunction`) and macOS 14 quirks | |
| alin23/Lunar | LICENSE file is **MIT**, but the Pro parts are encrypted and the repo does not build | DisplayServices/CoreDisplay declarations, gamma "zero-table" bug handling, DCP matching | Use only for the open parts |
| nriley/brightness | **BSD-2** | DisplayServices vs CoreDisplay brightness fallbacks | Its comment says CoreDisplay setters don't work on AS |
| huberdf/FreeDisplay | README says MIT, **no LICENSE file in repo** | Feature map only | Do not copy |
| NUIKit/CGSInternal | **No license file** | Names only | Do not copy |
| kfix/ddcctl, niklasr22/BrightIntosh, starkdmi/BrightXDR, toobuntu/blackoutd | **GPL-3** | **Do not read code.** README-level facts only | |
| Vivid, BetterDisplay (current), Lunar Pro | Proprietary | Feature parity reference only | |

Attribution rule for Snaptic: if we closely follow non-trivial logic from an MIT/BSD project (e.g., the MCDP29xx detection
in m1ddc, or MonitorControl's display↔IOAVService match scoring), add that project's copyright notice to
`THIRD_PARTY_NOTICES`. The facts themselves (selector names, VCP codes, register keys) are not copyrightable. Re-implement them
in our own structure.

---

## 1. Cross-cutting design (applies to every capability)

### 1.1 Private-symbol resolution layer ("PrivateAPI" registry)

Snaptic already uses `dlopen`/`dlsym` for SkyLight. Extend that to one registry that resolves every private symbol once at
startup. The registry records availability for each symbol and exposes typed Swift closures. Each feature gate then asks the
registry for its capability set, and the UI hides any feature that is unavailable.

Library paths. All of these are in the dyld shared cache, so the files do not exist on disk, but `dlopen` by path still works:

| Library | Path | Contains |
|---|---|---|
| CoreGraphics | `/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics` | `CGS*` display functions (re-exported from SkyLight), `CGVirtualDisplay*` ObjC classes |
| SkyLight | `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` | `SLS*` names of the same functions |
| CoreDisplay | `/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay` | `CoreDisplay_DisplayCreateInfoDictionary`, `CoreDisplay_Display_*Brightness` (private API, despite the folder) |
| DisplayServices | `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices` | `DisplayServices*` brightness |
| IOKit | `/System/Library/Frameworks/IOKit.framework/IOKit` | `IOAVService*` (private, exported from IOKit [O]: m1ddc and force-hidpi link it from IOKit) |
| MonitorPanel | `/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel` | `MPDisplay`, `MPDisplayMgr`, `MPDisplayMode` ObjC classes (rotation, HDR preference) |
| OSD | `/System/Library/PrivateFrameworks/OSD.framework/OSD` | `OSDManager` |
| CoreBrightness | `/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness` | `CBBlueLightClient` (Night Shift) [O, from Lunar headers] |

Rules:

1. **C functions:** use `dlsym(handle, "Name")`, and when it is missing also try `RTLD_DEFAULT` and the `SLS`↔`CGS` alias.
   Cast to a `@convention(c)` typealias. Never declare these as `@_silgen_name` or `extern`, because a missing symbol would then stop the app from launching (dyld bind failure).
2. **ObjC classes:** look them up with `NSClassFromString` / `objc_getClass` after `dlopen`ing the framework. **Never** let
   the linker see a private class reference. An ObjC `@interface` used with `[CGVirtualDisplay alloc]` emits
   `_OBJC_CLASS_$_CGVirtualDisplay`, and the app fails to launch if Apple renames the class. force-hidpi does take this risk.
3. **Selectors:** before first use, verify each one with `class_getInstanceMethod` / `class_getClassMethod` **and** compare
   `method_getTypeEncoding` with the expected encoding (example: `setHiDPI:` = `v20@0:8I16`, an unsigned int, not BOOL [O,
   go-macos]). Sending an unrecognized selector raises an ObjC exception, and **Swift cannot catch it**. A missing or changed
   encoding should mark the feature unavailable.
4. **Ownership and exceptions:** create a tiny **Objective-C SwiftPM target** (e.g. `SnapticPrivateShims`, `.m` plus a header
   with *no* private `@interface`s). It messages `id`-typed objects whose selectors are declared in a local `@protocol`. ARC
   then gets the alloc/init ownership families right, and the shim can wrap calls in `@try/@catch`. Swift calls the shim.
   Pure-Swift alternative [U]: declare an `@objc protocol` that mirrors the private API (including `init(descriptor:)`), call
   `class_addProtocol(cls, Proto.self)`, then cast `cls as! Proto.Type`. This avoids hand-written `objc_msgSend` ownership
   bugs, but test it on every OS release.
5. **Kill switches:** keep a remote-free, local `defaults` key per private feature
   (`Displays.disable.<feature>`) so users and support can turn off a crashing path without a rebuild. Record OS build and
   model in diagnostics.
6. **Hardened runtime:** `dlopen` of Apple system frameworks needs **no entitlement**. Library validation only rejects
   non-platform, differently-signed code, and the shared-cache frameworks are platform binaries [V by construction;
   MonitorControl links the same private frameworks]. No `disable-library-validation`, no JIT, and no special
   entitlements are needed for anything in this report. Exceptions: Screen Recording, Accessibility and Input Monitoring are
   **TCC** prompts, not entitlements, and the optional `com.apple.developer.persistent-content-capture` entitlement is restricted by Apple.

### 1.2 Threading model

| Work | Queue | Why |
|---|---|---|
| CG display configuration (`CGBeginDisplayConfiguration` … `CGCompleteDisplayConfiguration`), `CGVirtualDisplay` create/destroy, `MPDisplay`, NSWindow overlays | **Main thread** | AppKit/WindowServer state. A virtual display only becomes visible to the creating process while its run loop is being serviced [U, go-macos measured on 26.6.2] |
| `CGDisplayRegisterReconfigurationCallback` handler | Called on main run loop | **Never reconfigure inside the callback.** Coalesce events, then act after a 0.5–2 s debounce via `DispatchQueue.main.asyncAfter` |
| DDC/CI I/O (`IOAVService*`, `IOI2CSendRequest`) | **One global serial queue** (not per display), `.userInitiated` | Calls block with `usleep`. MonitorControl serializes all DDC on a global queue and coalesces writes [V, `OtherDisplay.swift`] |
| DisplayServices get/set | Serial utility queue per display | Can block on USB/Thunderbolt Apple displays. MonitorControl wraps `DisplayServicesSetBrightness` in `queue.sync` [V] |
| Gamma `CGSetDisplayTransferByTable` | Main or a serial queue (thread-safe in practice [O]); keep **one writer** | Avoid interleaved partial ramps |
| ScreenCaptureKit sample handler | Its own serial queue | Hand IOSurfaces to the layer on the main thread, or use `AVSampleBufferDisplayLayer` |

Pause **all** hardware writes (DDC and mode changes) between `willSleep`/`screensDidSleep` and wake + ~3–5 s, and also during a
display reconfiguration. MonitorControl refuses DDC writes while `sleepID != 0 || reconfigureID != 0` [V].

### 1.3 Event sources to subscribe to

- `CGDisplayRegisterReconfigurationCallback`: add, remove, mode, mirror and enable changes [V public].
- `NSApplication.didChangeScreenParametersNotification` [V].
- `NSWorkspace.willSleepNotification` / `didWakeNotification` / `screensDidSleepNotification` / `screensDidWakeNotification` [V].
- Distributed `kColorSyncDisplayDeviceProfilesNotification` for profile changes, which reset gamma [O, MonitorControl and Lunar].
- `IOServiceAddMatchingNotification` for `DCPAVServiceProxy` / `AppleCLCD2` / `IOMobileFramebufferShim` publish and terminate on AS, so the DDC service map can be rebuilt [O, Lunar].
- Accessibility-trust changes: distributed `com.apple.accessibility.api` [O, MonitorControl].

### 1.4 Safety framework (required before shipping any hardware or config writes)

Implement one **`DisplayChangeTransaction`** primitive and route every risky operation through it. Risky operations are mode
change, enable/disable, mirror, rotation, main display, virtual-display mirror, input switch and power state.

1. **Snapshot** the current state: per display UUID, the mode, origin, rotation, enabled flag, mirror set, gamma tables, and last-known DDC values.
2. **Journal.** Write `~/Library/Application Support/Snaptic/Displays/pending-revert.json` (snapshot, deadline, op id) and
   `fsync`. On the next launch, if a journal exists that was never committed, **revert first** before anything else. This
   covers SIGKILL, power loss and crash loops.
3. **Apply with the narrowest scope.** Use `CGCompleteDisplayConfiguration(cfg, .forAppOnly)` while unconfirmed. Apple
   documents that `.forAppOnly` changes "revert to the current login session" when the app terminates [V, `CGConfigureOption`
   docs]. That gives a free safety net on crash; whether it also holds after SIGKILL is [U]. After the user confirms, re-apply
   with `.permanently` (or `.forSession` for things that must not survive reboot, such as mirroring onto a virtual display).
4. **Confirmation UI** modelled on System Settings' "Keep changes?" dialog: a **15 s countdown**, shown on a display that is
   *not* affected (or on all displays). Return keeps the change. Esc or the timeout reverts.
5. **Out-of-process guard.** Spawn a child guard process. It can be our own executable with `--display-guard`, launched via
   `posix_spawn`, which avoids needing a second SwiftPM product. Pass it the snapshot over a pipe. If the parent dies (pipe EOF /
   `kqueue NOTE_EXIT`) or the deadline passes without a `commit` message, the guard reverts: re-enable displays, break mirrors,
   restore modes, call `CGDisplayRestoreColorSyncSettings()`. The guard uses `.forSession` for its own revert so the result
   survives the guard exiting.
6. **Panic hotkey** that works with no permissions: Carbon `RegisterEventHotKey` (e.g. ⌃⌥⌘⎋). It restores everything,
   destroys overlays and virtual displays, and re-enables all *online but inactive* displays.
7. **Hard invariants**, enforced in code rather than UI:
   - at least one active, non-virtual, non-mirrored-away display must remain;
   - never disable the display that hosts the confirmation UI unless another one is active;
   - never mirror every physical display onto a virtual one unless the guard is armed;
   - gamma tables never go below a floor (e.g. max ≥ 0.08) unless "dim to black" is explicitly requested, and even then the guard is armed.
8. **Rate limiters** (§6.6) on DDC writes and on config re-apply loops ("protection" mode).

### 1.5 TCC and entitlement matrix

| Capability | TCC | Entitlement | Notes |
|---|---|---|---|
| Enumerate, modes, mirroring, arrangement, rotation, enable/disable | none | none | |
| Virtual displays (CGVirtualDisplay) | none | none | Each new identity leaves an ICC profile in `/Library/ColorSync/Profiles/Displays` [U, go-macos] |
| DDC/CI | none | none | |
| Built-in/Apple display brightness (DisplayServices) | none | none | |
| Gamma, overlays, EDR overlay | none | none | |
| Native OSD (OSDUIHelper XPC) | none | none | |
| Media/brightness keys via `CGEventTap` **listen-only** | **Input Monitoring** | none | `CGPreflightListenEventAccess` / `CGRequestListenEventAccess` [V, Apple DTS (Quinn), forum 707680] |
| Media keys **swallowed** (active tap / `NSEvent` global monitor) | **Accessibility** | none | Needed to stop the system from also acting on the key [O, MonitorControl checks `AXIsProcessTrusted`] |
| PiP / streaming (ScreenCaptureKit) | **Screen Recording** | optional `com.apple.developer.persistent-content-capture` (Apple-granted, for screen-sharing products) | macOS 15+ re-confirmation prompts. See §11 |
| Display override plists in `/Library/Displays/...` | admin authorization | none | SIP does not protect `/Library/Displays`; it does protect `/System/Library/Displays` |
| Inbound AppleScript | the *sender* gets an Automation prompt | none | Needs `NSAppleScriptEnabled` and `OSAScriptingDefinition` in Info.plist |

---

## 2. Capability 1: enumeration and stable identity

### Public API [V]
- `CGGetOnlineDisplayList` lists everything, including disabled-but-connected and mirrored displays. `CGGetActiveDisplayList` lists drawable displays only. A display disabled with `CGSConfigureDisplayEnabled` stays *online* but not *active* (displayplacer's `isScreenEnabled = CGDisplayIsActive || CGDisplayIsInMirrorSet`) [O].
- `CGDisplayVendorNumber` / `CGDisplayModelNumber` / `CGDisplaySerialNumber` (EDID numeric serial is often 0 or a duplicate), `CGDisplayIsBuiltin`, `CGDisplayUnitNumber`, `CGDisplayScreenSize` (mm), `CGDisplayIsInMirrorSet`, `CGDisplayMirrorsDisplay`, `CGDisplayPrimaryDisplay`.
- `CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID) -> CFUUID` (ColorSync / ApplicationServices) and `CGDisplayGetDisplayIDFromUUID`. WindowServer derives the UUID from the EDID identity and **reuses it across reboots**. For identical monitors without unique serials the UUID can depend on the port, and two such monitors may swap [O].
- `NSScreen.localizedName`; the `NSScreenNumber` entry in `deviceDescription` gives the CGDirectDisplayID.
- **Virtual displays:** model number `0x76697274` ('virt') marks a virtual or headless display [V, Chromium]. The CoreDisplay info dictionary has `kCGDisplayIsVirtualDevice` and `kCGDisplayIsAirPlay` [O].

### Private, both architectures
- `CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID)` (CoreDisplay, returns +1) [O; used by MonitorControl, m1ddc, BetterDummy, force-hidpi]. Keys seen in OSS: `DisplayProductName` (localized dict), `DisplayVendorID`, `DisplayProductID`, `DisplaySerialNumber`, `DisplayYearOfManufacture`, `DisplayWeekOfManufacture`, `DisplayHorizontalImageSize`/`Vertical…`, `kCGDisplayUUID`, `IODisplayLocation` (IORegistry path), `kCGDisplayIsVirtualDevice`, `kCGDisplayIsAirPlay`. It returns NULL for some Sidecar/AirPlay displays, so handle nil [V, m1ddc fix 2026-01].

### Apple silicon: IORegistry and EDID
- **Best join** [V, m1ddc `ioregistry.m`]:
  1. Read `IODisplayLocation` from the CoreDisplay dictionary.
  2. Call `IORegistryEntryCopyFromPath(kIOMainPortDefault, location)` to get the framebuffer entry (`AppleCLCD2` or `IOMobileFramebufferShim`, conforming to `IOMobileFramebuffer`).
  3. Read `IORegistryEntryGetRegistryEntryID`.
  4. Walk the service plane. After each `IOMobileFramebuffer` with a matching entry ID, the next `DCPAVServiceProxy` whose `Location == "External"` is this display's AV service.
  
  MonitorControl uses a fallback score-based match. It scores EDID UUID substrings (vendor, product, manufacture date, image size), IODisplayLocation equality (+10), product name and serial [V, `Arm64DDC.swift`].
- Framebuffer properties [O]: `EDID UUID` (fallback `IOMFBUUID` [O, Lunar]), `DisplayAttributes.ProductAttributes.{ManufacturerID, ProductName, SerialNumber, AlphanumericSerialNumber, YearOfManufacture, ProductID, LegacyManufacturerID, NativeFormatHorizontalPixels/VerticalPixels}`, `Transport.{Upstream, Downstream}` (e.g. DP→HDMI).
- **Raw EDID on AS:** `IOReturn IOAVServiceCopyEDID(IOAVServiceRef, CFDataRef *outEDID)` (IOKit, private) [O, documented in Lunar author's notes; U for exact ownership, assume +1]. Externals only (`Location == External`). `IODisplayConnect` / `IODPDevice` do not exist on AS [V, Apple forum 674047].

### Intel
- `IOServiceGetMatchingServices(IOServiceMatching("IODisplayConnect"))` → `IODisplayCreateInfoDictionary(service, kIODisplayOnlyPreferredName)`. Keys: `DisplayVendorID`, `DisplayProductID`, `DisplaySerialNumber`, `IODisplayLocation`, `IODisplayEDID` (raw), `IODisplayEDIDOriginal` [V public IOGraphics].
- Framebuffer for a CGDirectDisplayID: `void CGSServiceForDisplayNumber(CGDirectDisplayID, io_service_t *)` (private, CoreGraphics) [O, MonitorControl Intel path]. Fallback: match vendor, product and serial, plus the unit number parsed from the trailing `@n` of `IODisplayLocation`. `CGDisplayIOServicePort` is deprecated and returns nothing useful on AS.
- Raw EDID over I2C: `IOFBCopyI2CInterfaceForBus` → `IOI2CSendRequest` at address 0xA0/0xA1 (256 bytes) [O, Lunar notes].

### Recommended identity key
Persist a **fingerprint record** for each display rather than a single key:
`{uuid (CGDisplayCreateUUIDFromDisplayID), vendor, model, serialNumber, alphanumericSerial, edidUUID or SHA-256(EDID), productName, isBuiltin, ioDisplayLocation (port hint)}`.

Match by score, with tiers:
1. EDID hash plus alphanumeric serial.
2. UUID.
3. vendor/model/serial.
4. Port location.

Keep the display ID only as a session handle, because IDs change across reconnects and GPU switches. Duplicate identical monitors need the port tie-break. Show the user an "identify" overlay that flashes a number on each screen to disambiguate them.

---

## 3. Capability 2: display modes, including hidden HiDPI modes and refresh rates

### Public (default path) [V]
- `CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary)`. The option (macOS 10.8+) adds the HiDPI "duplicate" modes, where pixel size is 2× point size. Without it, Retina variants are invisible.
- Per mode: `CGDisplayModeGetWidth/Height` (points), `GetPixelWidth/PixelHeight`, `GetRefreshRate` (0 on some built-ins), `GetIOFlags` (`kDisplayModeNativeFlag`, `kDisplayModeDefaultFlag`, `kDisplayModeSafetyFlags`, …), `GetIODisplayModeID`, and `CGDisplayModeIsUsableForDesktopGUI`.
- Set a mode with `CGBeginDisplayConfiguration` → `CGConfigureDisplayWithDisplayMode(cfg, id, mode, nil)` → `CGCompleteDisplayConfiguration(cfg, option)`. Options: `.forAppOnly` (reverts when the app terminates), `.forSession`, `.permanently`. WindowServer persists permanent configs per display identity.

### Private CGS (an "all modes / unsafe" advanced view only) [O; struct layout agreed by displayplacer and BetterDummy]
```c
void CGSGetNumberOfDisplayModes(CGDirectDisplayID, int *count);
void CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID, int index, void *out, int length /* 0xD4 */);
void CGSGetCurrentDisplayMode(CGDirectDisplayID, int *modeNumber);
void CGSConfigureDisplayMode(CGDisplayConfigRef, CGDirectDisplayID, int modeNumber);
// 0xD4-byte record: +0x00 uint32 mode, +0x04 flags, +0x08 width, +0x0C height, +0x10 depth,
//                   +0xBC uint16 refresh Hz, +0xD0 float density (1.0 or 2.0 = HiDPI)
```
- Resolve these through the CoreGraphics handle, with an `SLS` alias fallback. Sanity-check each record (width and height in 1…16384, density in {1, 1.5, 2, …}). If any check fails, disable the CGS path.
- The CGS list includes modes the public API hides, such as non-GUI-usable and "unsafe" ones. **These are where black screens come from.** Gate them behind Advanced and the §1.4 transaction.

### MonitorPanel (System Settings' own model) [O]
`MPDisplay` (`-initWithCGSDisplayID:(int)`) exposes `allModes`, `currentMode`, `setMode:`/`setModeNumber:`, `scanRates`, `hasMultipleRates`, `isHiDPI`, `hasHDRModes`, `preferHDRModes`/`setPreferHDRModes:`, `canChangeOrientation`, `orientation`, `underscan`, presets (`presets`, `setActivePreset:`), `isBuiltInRetina`, `hasMenuBar`, `uuid` (from the class-dump in displayplacer). Use it for presets and refresh-rate grouping only if the public API is insufficient.

### Notes
- **AS HiDPI limits:** Apple silicon offers HiDPI on sub-4K panels only in limited ways. BetterDisplay notes that 13.2+ enables "some HiDPI" by default. On **M4/M5 the highest HiDPI on a 4K external is 3360×1890**, because the DCP firmware caps `MaxSrcRectWidthForPipe` at 6720. Override plists and EDID hacks don't help [V-ish, smcleod.net 2026-03 Ghidra analysis; FB22365722]. The virtual display + mirror path (§5) is the only workaround.
- **Refresh rates:** distinct modes share the same size with a different `refreshRate`. ProMotion built-ins expose 120/variable. BetterDisplay adds extra NTSC rates "on supported AS configurations" (mechanism unknown, [U]).
- **Persistence and "configuration protection":** store the desired mode per fingerprint. On reconfigure or wake, compare and re-apply after a debounce. Loop guard: at most 3 re-applies per display per 60 s. Back off if the mode doesn't stick (macOS rejected it), and pause while System Settings → Displays is frontmost, because the user is changing things.
- **Failure modes:** a mode the panel can't sync to gives a black display, which needs the auto-revert. Changing the mode of a **virtual** display may make it un-removable until process exit [U, go-macos 26.6.2]. Mode changes are slow (0.5–3 s) and fire several reconfiguration callbacks.

---

## 4. Capability 3: virtual (dummy) displays (CGVirtualDisplay)

### Classes (CoreGraphics, private; present since macOS 11) [O, BetterDummy/DeskPad/Chromium/force-hidpi]

```objc
@interface CGVirtualDisplayDescriptor : NSObject   // -init
  unsigned int vendorID, productID, serialNum;     // ALSO serialNumber (Chromium sets both) [O]
  NSString *name; CGSize sizeInMillimeters; unsigned int maxPixelsWide, maxPixelsHigh;
  CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;   // CIE xy
  dispatch_queue_t queue;  // also -setDispatchQueue: / -dispatchQueue
  void (^terminationHandler)(id, CGVirtualDisplay *);          // copy
@interface CGVirtualDisplayMode : NSObject
  -initWithWidth:(unsigned)w height:(unsigned)h refreshRate:(double)hz;
  -initWithWidth:height:refreshRate:transferFunction:          // macOS 13.3+ (HDR) – TYPE DISPUTED, see below
  readonly width, height, refreshRate; transferFunction
@interface CGVirtualDisplaySettings : NSObject     // -init
  NSArray<CGVirtualDisplayMode*> *modes; unsigned int hiDPI;  unsigned int rotation;
@interface CGVirtualDisplay : NSObject
  -initWithDescriptor:(CGVirtualDisplayDescriptor*)d;   // nil if WindowServer refuses
  -(BOOL)applySettings:(CGVirtualDisplaySettings*)s;
  readonly displayID, hiDPI, modes, rotation, vendorID, productID, serialNum, name, ...
```

### How to call it from Swift without headers
- Use the ObjC shim target recommended in §1.1(4). It declares a local `@protocol SNVirtualDisplayAPI` with the selectors above, gets the class via `NSClassFromString(@"CGVirtualDisplay")`, verifies the selectors and encodings, then does `[[cls alloc] initWithDescriptor:d]` inside `@try`.
- Simple setters can use KVC from Swift (`setValue(NSNumber(value: UInt32(…)), forKey: "vendorID")`, `NSValue(size:)` for `sizeInMillimeters`, `NSValue(point:)` for primaries). KVC unboxes to `unsigned int` and CGSize/CGPoint correctly. `terminationHandler` is a block: pass an `@convention(block) (AnyObject?, AnyObject?) -> Void` closure cast to `AnyObject`.
- **`transferFunction` type conflict.** Chromium declares it as `id` (object). force-hidpi passes `unsigned int 1` (PQ) and that works on macOS 26 [O]. **Read `method_getTypeEncoding` at runtime.** Offer HDR virtual modes only if the 5th argument encodes as `I`, `i` or `Q`. If it encodes as `@`, hide HDR until the object type is reverse-engineered.

### Required and recommended descriptor values
- macOS 14 requires a **non-zero vendorID** and **unique serial numbers** per virtual display [V, Chromium comments]. Set **both** `serialNum` and `serialNumber` if both respond.
- Use a stable `(vendor, product, serial)` per user-defined virtual screen. macOS remembers the last mode and arrangement per identity and restores it [U, go-macos]. Use our own vendor ID (BetterDummy used `0xF0F0`, Chromium 505) and derive the serial from a persistent UUID.
- `maxPixelsWide/High` must cover the largest mode × (hiDPI ? 2 : 1). `sizeInMillimeters` determines DPI, and with it the default scale macOS picks.
- Primaries: copy the physical display's (force-hidpi reads them from the ICC profile) or use P3 or sRGB values.
- `queue`: a dedicated serial queue, not main, unless you are sure the main run loop runs.
- `terminationHandler`: optional. It is invoked when WindowServer tears the display down. **Leave nil unless needed**: go-macos saw intermittent crashes when it fires during process exit [U].

### Lifetime and behaviour
- The display exists while the `CGVirtualDisplay` object is alive. **Releasing it removes the display**, and removal is **asynchronous** (0.7–1.9 s for several displays [U, go-macos]). Wait for removal via the reconfiguration callback before re-creating the same identity.
- When the process dies, including crash or SIGKILL, WindowServer reclaims the display, so no phantom display remains [U, go-macos verified on 26.6.2]. This is good for safety.
- After a mode change (via CG config), the display may **not disappear on release until process exit** [U, go-macos; reproduced with all three CGConfigureOption scopes]. Mitigation: to "disconnect" a virtual screen whose mode was changed, re-create the app's display set from the guard helper, or accept the limitation and document it. Test this on 14/15/26.
- The creating process may be unable to read the new display's modes (`CGDisplayCopyDisplayMode` returns NULL) if it enumerated displays *before* creating it. Calling `CGGetActiveDisplayList` again and pumping the run loop usually fixes this [U, go-macos].
- Chromium found that the *first* removal is flaky if done alone, and removes it together with a temporary second display [V, Chromium]. Treat removal as best-effort plus verification.
- `settings.hiDPI = 1` makes macOS **advertise** HiDPI modes (pixels/2 points). The user or app still selects one.
- HDR virtual modes (macOS 13.3+ `transferFunction`) need 16-bit compositing and add GPU load (§5).
- Each new identity writes an ICC profile to `/Library/ColorSync/Profiles/Displays` that is never cleaned up [U]. Keep identities stable to avoid litter.
- **Not usable in the App Store**, which doesn't apply to Snaptic. No TCC is needed.

### Safeguards
- Cap the count (e.g. 4) and the max size (e.g. 8K×8K at HiDPI, i.e. ≤ 16384 px backing) to avoid WindowServer memory blowups.
- Don't create virtual displays while the screens sleep.
- Never make a virtual display the **main** display *and* the mirror source of all physical displays without the guard armed. If our process wedges without dying, the user sees only a mirror of a virtual desktop, which is still usable but confusing.

---

## 5. Capability 4: HiDPI and flexible scaling on non-HiDPI externals

### A. Virtual display at 2× plus a hardware mirror (recommended, no admin) [O, force-hidpi MIT, BetterDisplay]
1. Create a virtual display whose modes match the panel's aspect ratio, with `hiDPI=1` and `maxPixels = 2 × mode`. Use additional modes for a "resolution slider" (e.g. 2560×1440 points → 5120×2880 backing on a 1440p panel).
2. `CGBeginDisplayConfiguration(&cfg)`; `CGConfigureDisplayMirrorOfDisplay(cfg, physicalID, virtualID)`. This makes the **physical display mirror the virtual one**. Then `CGConfigureDisplayOrigin(cfg, virtualID, x, y)` to take the physical display's place in the arrangement. Finish with `CGCompleteDisplayConfiguration(cfg, .forSession)`. **Use `.forSession`, never `.permanently`**, so a reboot can't leave a mirror to a nonexistent display.
3. Undo with `CGConfigureDisplayMirrorOfDisplay(cfg, physicalID, kCGNullDirectDisplay)` and release the virtual display.

Caveats:
- WindowServer composites the full 2× surface every frame. GPU load rises, especially at 120 Hz: force-hidpi measured 6–44% vs ~0% GPU idle on an M5 Max.
- The pointer is sampled at the virtual display's refresh, so a 60 Hz virtual caps cursor sampling on all screens. Snap the virtual refresh to an integer multiple of the panel's (59.94 vs 60 causes periodic dropped frames) [O, force-hidpi comments].
- EDR/HDR on the mirrored panel needs an HDR (PQ) virtual mode plus gamma correction [O].
- Software dimming and gamma must target the *physical* (mirror-target) display. Overlay "shades" don't work on mirror targets, so put them on the virtual source [O, MonitorControl `isDisqualifiedFromShade`].
- DDC still talks to the physical display's AV service.
- If Snaptic crashes, the virtual display vanishes, macOS breaks the mirror and the panel returns to its native mode. This fails safe.

### B. Display override plist (admin, reboot or reconnect) [O, BetterDisplay "flexible scaling" requires admin + reboot]
- Path: `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<hex>/DisplayProductID-<hex>` (no extension), a plist with `DisplayProductName`, `scale-resolutions` (array of `<data>` entries, each big-endian `uint32 width, height[, flags]`; the HiDPI flag is commonly `0x00000001`, [U] exact flag semantics across versions), optionally `target-default-ppmm`, `DisplayPixelDimensions`, and `IODisplayEDID` (full EDID override).
- SIP does not block `/Library/Displays`. It needs root, so write via `osascript -e 'do shell script … with administrator privileges'`, or via a privileged helper (overkill).
- AS honours scale-resolutions only partly, and **M4/M5 firmware caps apply regardless** [V-ish, smcleod 2026].
- **Risks:** a bad `IODisplayEDID` or timing can black-screen that display at login. Recovery requires another display, Safe Mode, or deleting the folder from Recovery.
- **Recommendation:** v1 should **not** write overrides. v2 may offer "scale-resolutions only, never EDID". Show a big warning, keep a one-click "Remove all Snaptic overrides" action, and track every file we create in a manifest. EDID override parity with Pro: defer or skip it.

---

## 6. Capability 5: brightness

### 6.1 Built-in and Apple displays (Studio Display, Pro Display XDR, LG UltraFine) via DisplayServices [O; MonitorControl, Lunar, brightness]
```c
int  DisplayServicesGetBrightness(CGDirectDisplayID, float *out);   // 0 = success, 0..1
int  DisplayServicesSetBrightness(CGDirectDisplayID, float value);
bool DisplayServicesCanChangeBrightness(CGDirectDisplayID);
int  DisplayServicesGetLinearBrightness / SetLinearBrightness(CGDirectDisplayID, float*/float);
int  DisplayServicesSetBrightnessSmooth(CGDirectDisplayID, float);          // [O Lunar decl]
void DisplayServicesBrightnessChanged(CGDirectDisplayID, double);           // notify UI [O brightness.c]
int  DisplayServicesRegisterForBrightnessChangeNotifications(CGDirectDisplayID display,
        CGDirectDisplayID observer /* likely `const void *` */, CFNotificationCallback cb);  // [U signature]
bool DisplayServicesHasAmbientLightCompensation / AmbientLightCompensationEnabled(...)    // [O decl]
```
- **Detecting "Apple display":** MonitorControl treats a display as Apple-controllable if `DisplayServicesGetBrightness` returns 0 with a value ≥ 0, or if it is built-in. On macOS 15+ it also excludes non-Apple-vendor HDR displays (vendor ≠ 1552 / 0x610 with `CGSIsHDRSupported && CGSIsHDREnabled`) [V, `DisplayManager.isAppleDisplay`].
- `CoreDisplay_Display_SetUserBrightness(CGDirectDisplayID, double)` / `GetUserBrightness` give **no success indication and don't work on AS** [V, comment in nriley/brightness]. Use them only as an Intel fallback.
- Threading: DisplayServices can block for USB-backlight Apple displays, so call it off-main on a serial queue.
- macOS 26.3 changed "preset management" on XDR built-ins, and BetterDisplay's native XDR upscaling stopped working [V, BetterDisplay wiki]. Don't build on XDR presets.

### 6.2 External displays via DDC/CI VCP 0x10 (luminance), see §7
Coalesce writes (§7.6). Read the max value from the Get-VCP reply bytes 6–7 (big-endian); m1ddc fixed a wrong offset in 2026-06 [V].

### 6.3 Software dimming via gamma (works on most displays, including virtual displays and TVs)
- `CGGetDisplayTransferByTable(id, capacity, r, g, b, &count)` reads the current (ColorSync-derived) ramp. Capture it **once** as the baseline after each reconfigure or ColorSync change, then write `baseline × factor` with `CGSetDisplayTransferByTable(id, count, r, g, b)` [V public; pattern O MonitorControl].
- `CGSetDisplayTransferByFormula(id, rMin, rMax, rGamma, gMin, …)` is an alternative. `CGDisplayRestoreColorSyncSettings()` restores **all displays** (it is global). After calling it, re-apply our tables to every other display we manage [O, Lunar].
- **Resets** happen on display reconfigure, wake, ColorSync profile change (`kColorSyncDisplayDeviceProfilesNotification`), Night Shift transitions, and when another gamma app (f.lux, Lunar, BetterDisplay) writes. Re-apply on each of these after a short debounce. Detect fights: if the read-back differs from what we wrote ≥ 3 times, offer to switch to overlay dimming (MonitorControl's "gamma interference" alert) [O].
- **Apple silicon quirk:** the gamma change may not show until the screen redraws. MonitorControl keeps a 1×1, alpha 0.01 window at `.screenSaver` level and toggles its alpha after each gamma write to force a composite ("gamma activity enforcer") [O].
- **Known OS bugs (important):**
  - Tahoe betas: `CGSetDisplayTransferByTable` silently no-ops while "Automatically adjust brightness" is on (FB19136488, reported fixed in beta 5) [V, forum 795074].
  - **macOS 26.3–26.4 on M5 Pro/Max and "MacBook Neo": calls succeed and read-back matches, but nothing changes on screen.** Affects BetterDisplay, MonitorControl, f.lux and Lunar. Open bug (FB22273782); Apple reproduced it [V, forum 819331]. **Gamma success cannot be detected programmatically**, so the UI needs a user-visible "dimming method" choice (gamma / overlay / DDC) and a hint on affected models.
  - **Zeroed-gamma "screen blanking" bug**: after wake, tables can read back as all zeros and the screen goes black. Lunar polls every 3 s for an all-zero table, then re-applies the last good table, and falls back to `CGDisplayRestoreColorSyncSettings` [O, Lunar `AppDelegate.listenForScreenConfigurationChanged`]. **We must implement the same watchdog.**

### 6.4 Software dimming via overlay window (fallback, works when gamma doesn't)
- One borderless `NSWindow` per screen: `ignoresMouseEvents = true`, `level = CGShieldingWindowLevel()` (or `.screenSaver`), `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`, a black layer with alpha = 1 − brightness, and `sharingType = .none` [O, MonitorControl "shade"].
- Downsides:
  - The cursor is drawn above it and is not dimmed. It does dim screenshots and recordings unless excluded, and exclusion is unreliable on macOS 15+ (§11).
  - It doesn't reduce backlight power.
  - It cannot go above 100%.
  - Full-screen apps on other Spaces need `.fullScreenAuxiliary`.
- MonitorControl prefers overlays on virtual and mirrored displays and gamma elsewhere.

### 6.5 Combined scale (BetterDisplay-style)
Map 0–100%: the upper range drives hardware (DDC/DisplayServices) and the lower range adds software dimming down to near-black. Keep the switch point configurable. MonitorControl's "combined brightness" works this way.

### 6.6 Write rate limits (all brightness paths)
- UI slider: coalesce to the latest value, apply at most **every 50 ms for gamma/overlay** and every **100–200 ms for DDC** (see §7.6). DisplayServices: ≤ 20 Hz.
- Key-repeat: step size 1/16 (OSD chiclets) with optional ¼-step on ⌥⇧ (MonitorControl convention).

---

## 7. Capability 6: DDC/CI

### 7.1 Apple silicon transport [O; MonitorControl, m1ddc, Lunar]
```c
typedef CFTypeRef IOAVServiceRef;
IOAVServiceRef IOAVServiceCreate(CFAllocatorRef);                                   // default/first service
IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef, io_service_t);          // from DCPAVServiceProxy
IOReturn IOAVServiceReadI2C (IOAVServiceRef, uint32_t chipAddress, uint32_t offset,      void *buf, uint32_t len);
IOReturn IOAVServiceWriteI2C(IOAVServiceRef, uint32_t chipAddress, uint32_t dataAddress, void *buf, uint32_t len);
IOReturn IOAVServiceCopyEDID(IOAVServiceRef, CFDataRef *edid);                       // [O Lunar notes]
```
- **Service discovery:** `DCPAVServiceProxy` entries with property `Location == "External"`; the built-in has `Embedded`. Match each to a CGDirectDisplayID via §2 (IODisplayLocation → framebuffer registry ID → following DCPAVServiceProxy). MonitorControl's score match is the fallback.
- **Chip address 0x37** (7-bit DDC/CI). `dataAddress` = **0x51** (host source address). For LG's alternate input code 0xF4, m1ddc uses source/data address 0x50 [O].
- **M1 and entry-M2 Mac mini, and M2-gen MacBook Pro built-in HDMI:** these go through an MCDP29xx DP→HDMI converter. DDC works at **chip address 0xB7**. Detect it by checking that the *parent* of the `DCPAVServiceProxy` has `EPICProviderClass == "AppleDCPMCDP29XX"`. Use a longer read wait (50 ms; 10 ms returned empty replies) [V, m1ddc commit a561e56, 2026-08]. MonitorControl historically flagged these ports as "discouraged" (now disabled in code). Treat MCDP DDC as **beta**, read-mostly, with retries.
- Docks, adapters, DisplayLink and some HDMI-switches don't pass DDC. Detect this by failed reads and fall back to software dimming. DisplayLink exposes its own vendor paths and is not covered here.
- Some monitors' DDC breaks after the Mac's DCP power-cycles the link (sleep). Wait 3–5 s after wake.

### 7.2 Intel transport [V public IOKit `IOI2CInterface.h`; O MonitorControl]
- Framebuffer via `CGSServiceForDisplayNumber` (§2), then `IOFBGetI2CInterfaceCount` → `IOFBCopyI2CInterfaceForBus(fb, bus, &iface)` → `IOI2CInterfaceOpen` → `IOI2CSendRequest(connect, 0, &request)` → `IOI2CInterfaceClose`. Try each bus until one succeeds.
- `IOI2CRequest` for write: `sendAddress = 0x6E`, `sendTransactionType = kIOI2CSimpleTransactionType`, `sendBuffer/sendBytes`, `replyTransactionType = kIOI2CNoTransactionType`.
- For read: `replyAddress = 0x6F`, `replySubAddress = 0x51`, `replyTransactionType = kIOI2CDDCciReplyTransactionType` if the `IOFramebufferI2CInterface`'s `kIOI2CTransactionTypesKey` advertises it, else `kIOI2CSimpleTransactionType`, `minReplyDelay` ≈ 10 ms (some displays need 40 ms+).
- The 2018 Intel Mac mini's built-in HDMI needs special handling. BetterDisplay supports it; the mechanism is unknown [U].

### 7.3 Message framing (MCCS / DDC/CI)
Host→display packet, as written on the wire after the 0x6E destination address:
```
Set VCP:  [0x51] [0x84] [0x03] [vcp] [valHi] [valLo] [chk]
Get VCP:  [0x51] [0x82] [0x01] [vcp] [chk]
Caps req: [0x51] [0x83] [0xF3] [offHi] [offLo] [chk]
chk = 0x6E XOR every preceding byte (incl. 0x51)
```
- **Intel path:** the buffer starts with 0x51 as above [V, MonitorControl IntelDDC].
- **AS path:** `IOAVServiceWriteI2C(svc, 0x37, 0x51, buf)` sends 0x51 as the "data address", so `buf` starts at the length byte.
  - MonitorControl builds `buf = [0x80 | (n+1), n, payload…, chk]`, where n is the payload length (1 for Get, 3 for Set). For writes, `chk = 0x6E ^ 0x51 ^ (all preceding buf bytes)`. m1ddc builds the same bytes (`0x84 0x03 vcp hi lo chk`).
  - **For 1-byte Get requests both MonitorControl and m1ddc seed the checksum with 0x6E only (omitting 0x51)** [V, both sources]. This deviates from the spec, which includes 0x51, but works in the field.
  - Recommendation: replicate the field-proven framing, and on read failure retry once with the spec-exact checksum. Log which variant each display accepts.
- **Get VCP reply** (11 bytes, read via `IOAVServiceReadI2C(svc, 0x37, 0, buf, 11)` on AS): `[0x6E][0x88][0x02][result][vcp][type][maxHi][maxLo][curHi][curLo][chk]`, where `chk = 0x50 XOR bytes[0..9]` (0x50 is the virtual host address for replies).
  - Validate `buf[2] == 0x02` (Get VCP reply opcode), `buf[3] == 0x00` (0x01 means unsupported VCP), and `buf[4] == vcp`. Then max = bytes 6–7 and cur = bytes 8–9 [V, MonitorControl IntelDDC, m1ddc fix].
- **Capabilities string:**
  - Repeat the `0xF3` request at increasing offsets. Each reply is `[0x6E][0x80|len][0xE3][offHi][offLo][data ≤ 32 B][chk]`. Stop at a zero-length fragment. Total ≤ ~1–2 KB.
  - Allow 50 ms+ between fragments. Expect checksum failures and retry fragments, not the whole string.
  - Parse `vcp(10 12 14(05 08 0B) 16 18 1A 60(0F 11 12) 62 8D D6(01 04 05) …)`. Use it to auto-enable controls and to fill input-source menus.
  - Cache per fingerprint. Many displays return garbage or nothing, so have a manual override.
  - [U] for AS framing of multi-fragment reads; BetterDisplay implements it ("DDC capability detection").

### 7.4 Timing and retries
- Spec: ≥ 40 ms between a Get request and reading its reply; ≥ 50 ms between consecutive commands. "Save current settings" needs ≥ 200 ms.
- Field defaults (MonitorControl AS): pre-write sleep 10 ms, **each write sent twice** (2 "write cycles"), 50 ms before the read, up to 4 retries with a 20 ms gap. m1ddc: 10 ms, 2 iterations. A "longer delay" preference (40 ms reply) exists for slow displays [V].
- Note that the double write doubles the EEPROM write count (§7.6). Prefer **one** write followed by a verification read for brightness, and allow per-display "double write" only if single writes are flaky.

### 7.5 VCP code policy (enforce in code, not just in UI)

| Class | Codes | Policy |
|---|---|---|
| **Safe, continuous** | 0x10 luminance, 0x12 contrast, 0x62 speaker volume, 0x16/0x18/0x1A RGB video gain, 0x87 sharpness | Allowed. Clamp to the reported max. Coalesce |
| **Safe, discrete** | 0x14 color preset (values from caps: 01 sRGB, 05 6500K, 0B user1, …) | Allowed with values from caps or known lists |
| **Read-only, informational** | 0xDF VCP version, 0xC8 controller type, 0xC9 firmware, 0xC0 usage hours, 0xAC/0xAE frequencies, 0xB6 tech type, 0xAA orientation | Read only |
| **Confirm-required** (can leave the user without a picture) | 0x60 input select (and LG 0xF4); 0x8D mute (on some models "mute/**screen blank**"); 0xD6 power: 0x01 on is allowed; 0x02/0x03/0x04 standby/suspend/off need a confirmation and are **never sent automatically**; vendor KVM/PBP codes 0xE7 (Dell KVM), 0xE8/0xE9 (Dell PBP), 0xF3 (ASUS KVM) | Confirmation dialog shown on another display, plus a "this will switch away from this Mac" warning. Never accepted from URL scheme or unauthenticated channels |
| **Denied by default** | 0x01 degauss; **0x04 restore factory defaults**; **0x05** restore lum/contrast; **0x06** restore geometry; **0x08** restore color; **0x0A** restore TV; **0xB0 settings store/restore** (writes EEPROM / factory restore); **0xCA OSD/button lock** (can lock the monitor's own buttons); 0xCC OSD language; **0xD6 = 0x05 hard power-off** (usually can't be woken via DDC; the user must press the power button); any 0xE0–0xFF manufacturer code not on a per-model allowlist; the DDC/CI "Save Current Settings" opcode 0x0C | Hidden. Available only in a "Service" mode with typed confirmation (BetterDisplay exposes `hardwareFactoryReset`; we shouldn't by default) |
| **Never** | Any I²C chip address other than 0x37 (and 0xB7 for MCDP). Specifically never write **0x50 (EDID EEPROM)**, 0x30 (E-DDC segment), 0x3A (HDCP) | Hard-coded refusal. EDID EEPROMs are usually write-protected but not always (Lunar's author tried to write and failed only because of write protection) |

### 7.6 EEPROM wear and write coalescing
- Many monitors persist luminance, contrast and volume to EEPROM or flash on every change, or after a short idle. Others only on OSD exit (vendor-specific, [U]). Typical endurance is 10⁵–10⁶ cycles, and a 60 Hz slider drag can produce thousands of writes per minute.
- MonitorControl's pattern [V]: keep a `nextValue` per command, run a single global serial DDC queue, skip the write if `value == lastWrittenValue`, and skip during sleep or reconfigure.
- Snaptic policy:
  - Latest-value-wins coalescing per (display, VCP).
  - ≤ 5 writes/s per display while interacting.
  - Final value written on slider release.
  - Deadband for automatic sources (ambient/brightness sync): only write on a change of ≥ 2 units and no more often than once per 3–5 s.
  - No periodic "re-assert" writes. Re-apply after wake only if the read-back differs.
  - Never auto-write 0xB0.
  - Smooth transitions (fades) happen in software (gamma) or with ≤ 10 DDC steps.
  - Keep a per-display daily write counter in diagnostics.

---

## 8. Capability 7: XDR/HDR extra brightness (EDR)

### Public pieces [V Apple docs]
- `NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue` (10.15+): the static headroom; > 1.0 means EDR is supported. `maximumExtendedDynamicRangeColorComponentValue`: the **current** headroom. It rises only while EDR content is on screen and changes with the brightness slider, ambient light and thermals. `maximumReferenceExtendedDynamicRangeColorComponentValue` (reference modes).
- `CAMetalLayer.wantsExtendedDynamicRangeContent = true`, `pixelFormat = .rgba16Float`, `colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)`.
- `CALayer.wantsExtendedDynamicRangeContent` exists on macOS **14.0–26.0** and is deprecated in 26. macOS 26 adds `CALayer.contentsHeadroom` (and the `preferredDynamicRange` family).

### Technique A: multiply overlay (works on AS and Intel with HDR displays)
1. Create a full-screen, borderless, click-through window per target screen: `ignoresMouseEvents`, high level (overlay/shielding), `canJoinAllSpaces|stationary|fullScreenAuxiliary|ignoresCycle`, `isOpaque=false`, clear background, `sharingType = .none` (best-effort, §11).
2. Its content view hosts a `CAMetalLayer` with EDR enabled. Render a constant colour `(k, k, k, 1)` with `1 < k ≤ currentHeadroom` in extended-linear P3.
3. Set the layer's `compositingFilter` to the multiply blend mode (`"multiplyBlendMode"` CIFilter name) so the window **multiplies** underlying desktop pixels by k. White SDR UI becomes ~k× brighter. The BrightXDR README describes this approach in general terms ("overlay … in EDR color space … applying color blending filter").
4. Poll `maximumExtendedDynamicRangeColorComponentValue` ~1 Hz (there is no reliable notification; Lunar polls) and clamp k. Redraw only when k changes. This is a static frame, so GPU cost is the compositor cost.

Downsides: HDR video can blow out (BetterDisplay wiki), and Mission Control/Spaces transitions briefly lose EDR or show white thumbnails (BrightXDR README limitation).

### Technique B: EDR trigger plus gamma tables > 1.0 (Apple silicon only)
- Keep a tiny (1–2 px) EDR Metal layer on screen so the display enters EDR mode. Then write gamma tables whose values exceed 1.0, up to the current headroom. Lunar's open code computes `maxEDR` from the `NSScreen` EDR values and scales gamma tables with `maxValue: maxEDR` [O, Lunar `Display.swift`]. The BetterDisplay wiki calls this "color table XDR/HDR upscaling … clips HDR content".
- Apple's docs specify gamma values in 0–1 [V], so values > 1 are undocumented [U, works on AS in Lunar/BetterDisplay].
- **It inherits the gamma bugs in §6.3.** It is broken on M5 + 26.3/26.4.

### Power and thermal
- XDR MacBook Pros sustain ~1000 nits full-screen and peak ~1600 nits. Holding desktop UI at HDR levels draws a lot of power and heats the panel.
- Auto-disable when:
  - `ProcessInfo.thermalState >= .serious`;
  - `isLowPowerModeEnabled`;
  - on battery below a user threshold;
  - screens sleep or lock.
- Reduce k when the system lowers headroom. macOS itself throttles EDR headroom thermally.
- OLED HDR externals: risk of static-UI burn-in, so warn.

### Keeping it out of captures
Gamma-based effects are applied post-composition and **don't appear in screenshots** [O]. Overlay effects **do** unless excluded. `sharingType = .none` is not reliably honoured by ScreenCaptureKit (§11). Also exclude the overlay windows explicitly in our own SCK filters.

---

## 9. Capability 8: colour and image adjustments (gamma, contrast, temperature, invert)

- Build per-channel tables of 256 or 1024 samples. Keep the ColorSync baseline (`CGGetDisplayTransferByTable`) and compose: `out = baseline(f(x))`, where f applies gain (per-channel RGB), gamma exponent, contrast (S-curve around 0.5), temperature (multiply R/G/B gains from a blackbody→RGB approximation relative to 6500 K), black/white points, and **invert** (`f(x) = 1 − x`, which works with tables) [V public API].
- Also offer system invert via Accessibility "Invert colors". It is private (UniversalAccess, [U]), so prefer the table.
- **Night Shift interaction:** on AS, Night Shift and True Tone are applied in the display pipeline (DCP/CoreBrightness) and largely compose with gamma tables. On Intel, Night Shift itself uses gamma-like ramps and can fight with them [U; Lunar and f.lux document conflicts]. Night Shift status/control: `CBBlueLightClient` in CoreBrightness (`getBlueLightStatus:`, `setEnabled:`, `setStrength:commit:`) [O, Lunar headers; U for signatures]. BetterDisplay's "Night Shift for TVs" suggests Night Shift availability is gated per display type [U mechanism].
- **ColorSync profiles:** a profile switch resets gamma, so re-capture the baseline and re-apply. Change profiles with `ColorSyncDeviceSetCustomProfiles` (public ColorSync) [V public; details U].
- **Restore on quit and crash. What persists?**
  - On normal quit: call `CGDisplayRestoreColorSyncSettings()` and remove overlays.
  - Crash or SIGTERM/SIGKILL: WindowServer resets gamma tables owned by a process when that process's connection dies. This is how quitting MonitorControl restores brightness. It is observed behaviour [O]; Apple's current docs don't state it [U].
  - CG configuration changes made with `.forAppOnly` revert on termination [V docs].
  - `.forSession` and `.permanently` changes, display **enable/disable** state [U: blackoutd reports a SIGKILL can leave a disabled display off until re-enumeration], and DDC values written to the monitor **persist**.
  - Override plists persist.
  - Virtual displays vanish [U, go-macos].
  - Hence the journal and guard in §1.4.
- SIGTERM handler: install a `DispatchSource.makeSignalSource(.term)` that runs the normal restore and then exits. Never do real work inside a raw signal handler.

---

## 10. Capability 9: display management

### Enable / disable ("disconnect")
```c
CGError CGSConfigureDisplayEnabled(CGDisplayConfigRef, CGDirectDisplayID, bool enabled);  // CoreGraphics (re-export)
CGError SLSConfigureDisplayEnabled(CGDisplayConfigRef, CGDirectDisplayID, bool enabled);  // SkyLight name [U presence]
```
- Use it inside `CGBeginDisplayConfiguration` … `CGCompleteDisplayConfiguration`. It works on AS: displayplacer v1.3 added "disable a screen" together with M1/M2 support, and blackoutd was tested on an M2 with macOS 13+ [O].
- The display remains online, so keep its ID **and** fingerprint to re-enable it. The ID may change if it is re-plugged.
- **Risks:** disabling the last active display leaves the user with no screen. Disabling the built-in with the lid open is fine. Disabling while mirrored, or disabling the main display, causes menu bar relocation.
- blackoutd notes a SIGKILL can leave the display disabled until re-enumeration (re-plug, logout) [U].
- Safeguards: the invariants in §1.4, scope `.forSession` (never `.permanently` for disable), the guard process, the journal, the panic hotkey, and auto-re-enable when the "other" display disconnects ("leaving a Mac with no usable display is never acceptable", blackoutd README).

### Main display and arrangement [V public]
- `CGConfigureDisplayOrigin(cfg, id, x, y)`. The display at origin (0,0) is the main display (menu bar). To make display B main, translate all origins by −B.origin.
- Validate with `CGDisplayBounds` after completion. macOS may snap layouts.

### Mirroring [V public]
- `CGConfigureDisplayMirrorOfDisplay(cfg, display, primary)`; `kCGNullDirectDisplay` un-mirrors. Query with `CGDisplayIsInMirrorSet`, `CGDisplayMirrorsDisplay`, `CGDisplayIsInHWMirrorSet`.
- MonitorControl's `engageMirror` uses `.permanently` [V]. Snaptic should prefer `.forSession` for virtual-source mirrors.

### Rotation
- **AS (and Intel):** MonitorPanel `MPDisplay`: `[[MPDisplay alloc] initWithCGSDisplayID:id]`, check `canChangeOrientation`, then `setOrientation:(int degrees)`. It is **asynchronous**: poll `CGDisplayRotation(id)` until it equals the target, with a timeout of 10 s [O, displayplacer `MonitorPanel.m`; v1.3 "Fixed M1/M2 rotation"].
- **Intel legacy:** `IOServiceRequestProbe(framebufferService, kIOFBSetTransform | (transform << 16))`, with `kIOFBSetTransform = 0x400`, `kIOScaleRotate90 = kIOScaleSwapAxes|kIOScaleInvertX (0x30)`, `180 = InvertX|InvertY (0x60)`, `270 = SwapAxes|InvertY (0x50)` [U values recalled from `IOGraphicsTypes.h`; verify in the SDK header].
- `CGSSetDisplayRotation`: [U]. I found no evidence of it being exported. Don't rely on it.
- Virtual displays: `CGVirtualDisplaySettings.rotation` [O, Chromium/force-hidpi headers].
- Built-in displays usually refuse rotation (`canChangeOrientation == NO`).

### HDR on/off
- Read with `bool CGSIsHDRSupported(CGDirectDisplayID)` and `bool CGSIsHDREnabled(CGDirectDisplayID)` (weak, CoreGraphics) [O, MonitorControl].
- Toggle with `MPDisplay.hasHDRModes` / `preferHDRModes` / `-setPreferHDRModes:(BOOL)` [O class-dump; U that this matches System Settings' toggle on 14/15/26]. I found no verified SkyLight setter (`SLSDisplaySetHDRModeEnabled`), so don't use guessed names.
- Toggling HDR re-modesets the display (black flash for 1–3 s). Run it through the transaction.

### Configuration protection
Store the desired layout, mode, main display, mirror and rotation per **set of connected fingerprints** (a "layout profile"). On each debounced reconfigure, diff and re-apply. Use the loop guard in §3. Never fight the user: suspend protection for 30 s after any change that we didn't make while System Settings is frontmost.

### Hang and black-screen hazards (summary)
CG configuration transactions are synchronous and can take seconds. Run them on main but never from inside reconfiguration callbacks, and never in tight loops. Creating dozens of virtual displays, or applying many mode changes per second, can make WindowServer sluggish. Rate-limit config ops to 1 per 2 s outside of the user's explicit actions.

---

## 11. Capability 10: picture-in-picture and display streaming

- **ScreenCaptureKit** (macOS 12.3+):
  1. `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)` gives the list of `SCDisplay` (virtual displays included, since they are real CG displays) and `SCWindow`.
  2. Build a filter: `SCContentFilter(display:excludingApplications:exceptingWindows:)` (exclude **our own app**) or `SCContentFilter(desktopIndependentWindow:)` for single-window PiP.
  3. `SCStreamConfiguration`: `width/height` in pixels (match the target view × backing scale), `minimumFrameInterval = CMTime(1, fps)`, `queueDepth` 3–5, `pixelFormat = kCVPixelFormatType_32BGRA` (or `420v` for lower bandwidth), `showsCursor`, and `colorSpaceName` / `captureDynamicRange` (macOS 15+) for HDR capture.
  4. Feed the `CMSampleBuffer`'s IOSurface into `layer.contents` (zero-copy) or an `AVSampleBufferDisplayLayer`.
- **Performance:** about one frame of latency, and modest GPU use at display resolution. Scale down in SCK, not in our layer. Pause the stream when the PiP window is occluded or minimized (`NSWindow.occlusionState`).
- `CGDisplayStream` (what DeskPad uses) is **deprecated since macOS 14** and triggers the stricter privacy alerts on 15+. Don't use it.
- **TCC:** Screen Recording is required (`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`).
  - On **macOS 15+** apps that capture programmatically get a recurring "…is requesting to bypass the system private window picker" alert ("Allow for one month") [V, Apple DTS in forum 765103; 9to5mac].
  - Apple's two avoidances are the `com.apple.developer.persistent-content-capture` entitlement (granted by Apple for screen-sharing products) and the `SCContentSharingPicker` UI (user picks per session; designed not to need the global permission [V, nonstrict.eu, with beta caveats]).
  - For PiP of a chosen window, **use `SCContentSharingPicker` where possible.** For "mirror virtual display into a window" we need programmatic display capture, so accept the monthly prompt.
- **Feedback loops:** never capture the display that hosts the PiP window without excluding that window. That makes the exclusion filter mandatory.
- **Keeping our windows out of capture:** `NSWindow.sharingType = .none` historically excluded windows from `CGWindowListCreateImage` and capture. Under ScreenCaptureKit the behaviour is **inconsistent**: a `.none` window was omitted at stream start but appeared after a filter change, and QuickTime captured it immediately (FB21115847, no Apple ruling) [V, forum 808016]. Treat `.none` as best-effort. For our own captures, exclude our windows explicitly in the filter.
- **Virtual screen you can watch** (DeskPad-style): create a virtual display, then stream it via SCK into a resizable window. Map clicks back with `CGWarpMouseCursorPosition` or post events. Posting events needs Accessibility. DeskPad warps the cursor only.

---

## 12. Capability 11: keyboard brightness and volume keys for external displays

- **Intercept:** `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: …, eventsOfInterest: 1 << NX_SYSDEFINED (14))`.
  - Decode `NSEvent(cgEvent:)` with `subtype == 8`. `data1` gives `keyCode = (data1 & 0xFFFF0000) >> 16` and `keyDown = ((data1 & 0xFF00) >> 8) == 0xA`, with keys `NX_KEYTYPE_SOUND_UP 0`, `SOUND_DOWN 1`, `BRIGHTNESS_UP 2`, `BRIGHTNESS_DOWN 3`, `MUTE 7`, and `ILLUMINATION_*` 21–23 (keyboard backlight) [V `ev_keymap.h`/IOKit public].
  - **Listen-only taps need Input Monitoring. To *consume* the key (so macOS doesn't also change the built-in display or the system volume) you need an active tap, which needs Accessibility** (§1.5).
  - MonitorControl uses the MediaKeyTap library with an active tap and re-checks `AXIsProcessTrusted` [O].
  - Re-create the tap when it gets `kCGEventTapDisabledByTimeout` or `ByUserInput`. Keep the callback fast: hand off to a queue, and never do DDC inside it.
- **Caveat [U]:** on some Apple silicon laptops and keyboards, brightness keys for the built-in display are handled before the session tap, and F-key/fn settings change what arrives. Provide custom shortcuts as a fallback (Carbon `RegisterEventHotKey` needs no permission).
- **Native OSD:**
  - macOS 14/15: `OSDManager` (OSD.framework) `+sharedManager`, then `-showImage:(long long)img onDisplayID:(unsigned)id priority:(unsigned)0x1F4 msecUntilFade:(unsigned)1000 filledChiclets:(unsigned)f totalChiclets:(unsigned)t locked:(BOOL)l`. Image IDs: brightness 1, speaker 3, muted 4, contrast-like 0. Other images 21/22 show "disabled" states [V, MonitorControl `OSDUtils.swift`].
  - **macOS 26 (and 27 per their version gate):** MonitorControl bypasses `OSDManager`. It opens `NSXPCConnection(machServiceName: "com.apple.OSDUIHelper")` with `remoteObjectInterface = NSXPCInterface(with: OSDUIHelperProtocol.self)` and calls the same `showImage:…` selectors on the proxy, on the main thread, with interruption/invalidation handlers that reset the connection [V source]. The reason is not documented [U]: probably that Tahoe's new HUD ignores `OSDManager` for external display IDs.
  - Our version: declare the `@objc protocol` in Swift with the exact selectors, verify the connection, and **fall back to our own HUD** (a SwiftUI panel, `.statusBar`+ level, non-activating, `canJoinAllSpaces`). BetterDisplay 5 likewise offers a "Traditional OSD option" and custom styling.

---

## 13. Capability 12: ambient light sync and following the built-in brightness

- **Recommended:** sync externals to the **built-in display's brightness**, which already includes macOS's ambient-light curve. Poll `DisplayServicesGetBrightness(builtinID)` at 1–2 Hz (cheap), or register `DisplayServicesRegisterForBrightnessChangeNotifications` if its signature verifies [U].
  - Map through a per-display curve (piecewise linear with user calibration points; BetterDisplay Pro normalizes in nits).
  - Apply the §7.6 deadband and rate limits for DDC.
  - Pause syncing while the user is adjusting the external manually (≥ 10 s), as MonitorControl does with `brightnessSyncSourceValue` [O].
- **Raw lux (optional, private) [U]:**
  - AS: `IOHIDEventSystemClientCreate` with matching `PrimaryUsagePage 0xFF00 / PrimaryUsage 4` (AppleSPU ALS), then `IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeAmbientLightSensor=12, 0, 0)` and `IOHIDEventGetFloatValue(event, 12<<16)`. Lunar declares `IOHIDServiceClientCopyEvent`, `IOHIDEventGetFloatValue` and `ALCALSCopyALSServiceClient()` (framework unknown).
  - Intel: `AppleLMUController` with `IOConnectCallMethod` selector 0.
  - Some external Apple displays (Studio Display) have their own sensors. BetterDisplay 5 shows "per-display ambient light readings" [V wiki].
  - Treat all of this as optional, behind the registry.
- Lunar's original external-sensor approach (ESP32/ESPHome YAMLs in `ALS/`) is out of scope.

---

## 14. Capability 13: notch and menu-bar features

- **Notch-free modes:** MacBook Pro/Air notched panels expose extra modes whose height excludes the notch strip (e.g. 1512×945 vs 1512×982 points on a 14"). Selecting one moves the menu bar below the notch with black bars. They appear in `CGDisplayCopyAllDisplayModes` with the duplicate-modes option [O; U exact list per model]. Detect the notch via `NSScreen.safeAreaInsets.top > 0` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (macOS 12+) [V].
- **Black menu bar / hide notch:** an overlay window covering the menu bar strip (FreeDisplay "notch hiding via a black overlay"). Get the height from `SLSGetDisplayMenubarHeight(CGDirectDisplayID, uint32_t *height)` [O, Lunar decl; signature from the yabai pattern], or from `NSScreen.frame.maxY − visibleFrame.maxY`. With a wallpaper-coloured overlay this approximates BetterDisplay's look.
- BetterDisplay 5 also lists "External HUD and notch-app integration" [V wiki]. That is an app-integration surface, not an OS feature.

---

## 15. Capability 14: automation surfaces

### URL scheme (`snaptic://display/...`)
- **Threat:** any web page can attempt to open a custom scheme (browsers show a prompt the first time, then often remember it). Any local app can too, via `NSWorkspace.open` or `open snaptic://…`. There is **no caller identity**.
- Policy:
  - Allow only idempotent, bounded, non-destructive actions: brightness and volume within 5–100%, preset recall *of user-created presets*, show PiP of an existing configuration.
  - **Never** via URL: disable display, mode or refresh changes, rotation, mirroring, DDC input/power/raw VCP, factory codes, override plists, virtual-display creation, gamma below the floor.
  - Require a per-install random **token** (≥ 128-bit, Keychain) for *any* state change, as BetterDisplay does optionally. We should make it mandatory.
  - Rate-limit to a few actions per second.
  - Never return data via x-callback that could leak (display serials, EDID).

### AppleScript
- Cocoa Scripting works in a SwiftPM-built bundle. Add `NSAppleScriptEnabled = YES` and `OSAScriptingDefinition = Snaptic.sdef` to Info.plist, put the `.sdef` in `Contents/Resources`, and add `NSScriptCommand` subclasses exposed with `@objc(SnapticSetBrightnessCommand)`.
- Callers need the user's **Automation** consent (TCC), which makes this the safest "Shortcuts-compatible" surface. Shortcuts can call it with "Run AppleScript".

### App Intents in a SwiftPM executable
- App Intents metadata (`Metadata.appintents` in the bundle) is produced by **Xcode's build system** ("Extract App Intents Metadata" phase, tool `appintentsmetadataprocessor`) from compiler-emitted const values [V, Swift Forums; Apple engineer statement]. Plain `swift build` does **not** run this step [U, but no evidence it does], so intents compile but are not discoverable by Shortcuts.
- Options:
  - (a) build the app product with `xcodebuild` against the package. Whether the extraction runs for SwiftPM executables is [U]; test it.
  - (b) reproduce the step manually with `swiftc -emit-const-values-path` and `xcrun appintentsmetadataprocessor`. The arguments are undocumented and fragile [U].
  - (c) defer, and rely on AppleScript and the CLI. Shortcuts has "Run Shell Script".
- **Recommendation:** (c) for v1.

### CLI (`snaptic display …`)
- Use a second SwiftPM `executableTarget` copied into `Contents/MacOS/` or `Contents/Helpers/`, or the main binary with `--command`. It talks to the running app over a **Unix domain socket**:
  - path in `~/Library/Application Support/Snaptic/run/ctl.sock` (dir `0700`, socket `0600`);
  - on accept, check the peer with `getpeereid()` / `getsockopt(SOL_LOCAL, LOCAL_PEERCRED)` (uid must equal ours), and if available `LOCAL_PEERTOKEN` (audit token) → `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)` → `SecCodeCheckValidity` against a designated requirement (same Team ID, or our identifier for ad-hoc dev builds) [U availability of `LOCAL_PEERTOKEN` on 14; fall back to uid-only];
  - avoid PID-based checks (PID reuse race);
  - length-prefixed JSON messages with a max size;
  - the same command policy as the URL scheme, except that dangerous actions are allowed **only** with `--yes` *and* still go through the §1.4 transaction (and confirmation UI unless `--no-confirm` plus a config opt-in).
- `NSXPCConnection` with a Mach service needs a launchd-registered agent (`SMAppService.agent`), which is heavier. Use it only if we later split out a helper. `NSXPCConnection.setCodeSigningRequirement` (macOS 13+) is then available.
- **Do not** accept commands via `DistributedNotificationCenter`: any process, including sandboxed ones, can post, and posts are spoofable and unauthenticated. BetterDisplay offers this. We shouldn't.
- **Do not** open an HTTP listener. BetterDisplay's HTTP integration (port 55777, optional token, remote hostnames allowed) is a LAN attack surface. If one is ever added: loopback-only and a mandatory token.

---

## 16. Risk register (what can hang, blank, damage, or bypass security)

| # | Risk | Severity | Trigger | Safeguard |
|---|---|---|---|---|
| R1 | **No usable display** | Critical | Disable last display; mirror all displays onto a virtual one, then hang; unsupported mode; HDR toggle failure | §1.4 invariants, `.forAppOnly` trial, 15 s confirm, guard process, journal revert on next launch, panic hotkey |
| R2 | **Black screen from gamma** | High | Zeroed-gamma OS bug after wake; our own min-brightness 0 | 3 s zero-table watchdog → re-apply last good → `CGDisplayRestoreColorSyncSettings`; floor 0.08; panic hotkey |
| R3 | Gamma silently ignored (M5 + 26.3/26.4; Tahoe beta auto-brightness) | Medium (functional) | OS bug | User-selectable dimming method; overlay fallback; model/OS hint; cannot auto-detect |
| R4 | **Monitor EEPROM wear** | Medium/long-term | High-rate DDC writes (slider drags, sync loops, double writes) | Coalescing, ≤ 5 Hz, deadband, no periodic re-assert, single write + verify |
| R5 | **Monitor factory reset or config loss** | High | VCP 0x04/05/06/08/0A, 0xB0 | Hard deny-list; service mode only |
| R6 | **User stranded by DDC** | High | 0x60 input switch, 0xD6 power off (0x05 hard off), 0x8D screen blank, 0xCA OSD lock | Confirm on another display; never via URL/CLI without explicit flags; deny 0xCA and 0xD6=5 by default |
| R7 | **EDID EEPROM corruption** | Critical (hardware) | Any I²C write to 0x50 | Code-level refusal of all chip addresses except 0x37 and 0xB7 |
| R8 | Bad override plist → display black at boot | High | EDID/timing overrides | Don't ship EDID overrides in v1; manifest and "remove all"; scale-resolutions only |
| R9 | WindowServer stalls | Medium | Rapid config loops, many virtual displays, reconfigure inside callbacks | Debounce, protection loop guard, caps on virtual display count and size, 1 config op per 2 s automatic |
| R10 | Crash from private API change | Medium | Selector or symbol removed or retyped (e.g. `transferFunction`) | Runtime registry, type-encoding checks, ObjC shim `@try`, never link private classes, kill switches |
| R11 | Un-removable virtual display | Low | Mode change on a virtual display [U] | Avoid mode changes on throwaway virtual displays; document; re-create on relaunch |
| R12 | Unauthenticated local control | High (security) | URL scheme, distributed notifications, HTTP | Token, allowlist, UDS with peer credential and code-signing check, no HTTP, no DNC |
| R13 | Privacy leak via capture | Medium | Overlays and PiP windows captured; feedback loops | Explicit SCK exclusion; `sharingType=.none` best-effort; SCContentSharingPicker for window PiP |
| R14 | Battery and thermal from EDR | Medium | Sustained XDR boost | thermalState, low-power and battery cutoffs; clamp to current headroom |
| R15 | Key handling breaks input | Medium | Event tap timeout or slow callback | Re-enable on `tapDisabledByTimeout`; O(1) callback; Carbon hotkey fallback |

---

## 17. Suggested build order

1. Registry + enumeration/fingerprints + public modes (with HiDPI duplicates) + transaction/guard/journal + panic hotkey.
2. Brightness: DisplayServices (built-in/Apple), DDC (AS incl. MCDP, Intel), gamma and overlay dimming with watchdog, combined scale, rate limiting.
3. Keys + OSD (OSDManager / OSDUIHelper XPC / own HUD), sync-to-built-in.
4. Virtual displays (ObjC shim) → HiDPI via virtual + mirror (`.forSession`).
5. Arrangement/main/mirroring/rotation (MPDisplay), enable/disable (guarded), protection.
6. Colour adjustments (tables), EDR overlay (technique A first), PiP via SCK.
7. Automation: UDS CLI, AppleScript, token-gated URL scheme. App Intents later.
8. Optional/Advanced: CGS hidden modes, override plists (scale-only), raw lux, HDR toggle via MPDisplay.

---

## Appendix A: private symbol table (resolve at runtime; all optional)

| Symbol | Library | C signature / selector | Status | Used for |
|---|---|---|---|---|
| `CoreDisplay_DisplayCreateInfoDictionary` | CoreDisplay | `CFDictionaryRef (CGDirectDisplayID)` (+1) | [O] | identity, IODisplayLocation |
| `CoreDisplay_Display_GetUserBrightness` / `SetUserBrightness` | CoreDisplay | `double (CGDirectDisplayID)` / `void (CGDirectDisplayID, double)` | [O], not on AS | Intel built-in fallback |
| `DisplayServicesGetBrightness` / `SetBrightness` | DisplayServices | `int (CGDirectDisplayID, float*)` / `int (CGDirectDisplayID, float)` | [O] | built-in/Apple brightness |
| `DisplayServicesCanChangeBrightness` | DisplayServices | `bool (CGDirectDisplayID)` | [O] | capability |
| `DisplayServicesBrightnessChanged` | DisplayServices | `void (CGDirectDisplayID, double)` | [O] | notify system UI |
| `DisplayServicesRegisterForBrightnessChangeNotifications` | DisplayServices | `int (CGDirectDisplayID, const void*?, CFNotificationCallback)` | [U] | sync |
| `IOAVServiceCreateWithService` | IOKit | `CFTypeRef (CFAllocatorRef, io_service_t)` | [O] | AS DDC |
| `IOAVServiceReadI2C` / `WriteI2C` | IOKit | `IOReturn (CFTypeRef, uint32 chip, uint32 off, void*, uint32)` | [O] | AS DDC |
| `IOAVServiceCopyEDID` | IOKit | `IOReturn (CFTypeRef, CFDataRef*)` | [O] | AS EDID |
| `CGSServiceForDisplayNumber` | CoreGraphics | `void (CGDirectDisplayID, io_service_t*)` | [O] | Intel framebuffer |
| `CGSGetNumberOfDisplayModes` | CoreGraphics | `void (CGDirectDisplayID, int*)` | [O] | hidden modes |
| `CGSGetDisplayModeDescriptionOfLength` | CoreGraphics | `void (CGDirectDisplayID, int, void*, int /*0xD4*/)` | [O] | hidden modes |
| `CGSGetCurrentDisplayMode` | CoreGraphics | `void (CGDirectDisplayID, int*)` | [O] | hidden modes |
| `CGSConfigureDisplayMode` | CoreGraphics | `void (CGDisplayConfigRef, CGDirectDisplayID, int)` | [O] | hidden modes |
| `CGSConfigureDisplayEnabled` (`SLS…`) | CoreGraphics / SkyLight | `CGError (CGDisplayConfigRef, CGDirectDisplayID, bool)` | [O] / SLS name [U] | disconnect |
| `CGSIsHDRSupported` / `CGSIsHDREnabled` | CoreGraphics | `bool (CGDirectDisplayID)` | [O] | HDR state |
| `SLSGetDisplayMenubarHeight` | SkyLight | `CGError (uint32_t, uint32_t*)` | [O] | notch/menu bar |
| `CGVirtualDisplay`, `…Descriptor`, `…Mode`, `…Settings` | CoreGraphics (ObjC) | see §4 | [O]; `transferFunction` type [U] | virtual displays |
| `MPDisplay` | MonitorPanel (ObjC) | `-initWithCGSDisplayID:(int)`, `-setOrientation:(int)`, `-canChangeOrientation`, `-setPreferHDRModes:(BOOL)`, `-hasHDRModes`, `-allModes`, `-setMode:` | [O] class-dump; HDR toggle [U] | rotation, HDR |
| `OSDManager` | OSD (ObjC) | `+sharedManager`; `-showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:` | [O] 14/15 | native OSD |
| `com.apple.OSDUIHelper` | Mach XPC service | same protocol over `NSXPCConnection(machServiceName:)` | [O] 26 | native OSD on Tahoe |
| `CBBlueLightClient` | CoreBrightness (ObjC) | `-getBlueLightStatus:`, `-setEnabled:`, `-setStrength:commit:` | [U] | Night Shift |
| `IOHIDServiceClientCopyEvent`, `IOHIDEventGetFloatValue` | IOKit | `IOHIDEventRef (IOHIDServiceClientRef, int64, int32, int64)`, `double (IOHIDEventRef, int32)` | [U] | raw ALS |

## Appendix B: public APIs used (no risk of disappearing)
`CGGetOnlineDisplayList`, `CGGetActiveDisplayList`, `CGDisplayCopyAllDisplayModes` + `kCGDisplayShowDuplicateLowResolutionModes`, `CGDisplayMode*`, `CGBeginDisplayConfiguration`, `CGConfigureDisplayWithDisplayMode`, `CGConfigureDisplayOrigin`, `CGConfigureDisplayMirrorOfDisplay`, `CGCompleteDisplayConfiguration` (`.forAppOnly`/`.forSession`/`.permanently`), `CGCancelDisplayConfiguration`, `CGDisplayRegisterReconfigurationCallback`, `CGDisplayCreateUUIDFromDisplayID`, `CGDisplayRotation`, `CGGetDisplayTransferByTable`, `CGSetDisplayTransferByTable/ByFormula`, `CGDisplayRestoreColorSyncSettings`, `IOI2CInterface` (Intel), `IODisplayCreateInfoDictionary` (Intel), `NSScreen` EDR properties, `CAMetalLayer.wantsExtendedDynamicRangeContent`, ScreenCaptureKit, `CGEvent.tapCreate`, `CGPreflight/RequestListenEventAccess`, `CGPreflight/RequestScreenCaptureAccess`, `AXIsProcessTrustedWithOptions`, Carbon `RegisterEventHotKey`.

## Appendix C: sources consulted
- Code read (permissive): MonitorControl (MIT), m1ddc (MIT), BetterDummy `opensource` branch (MIT), DeskPad (MIT), displayplacer (MIT), force-hidpi (MIT), go-macos/virtualdisplay (BSD-3), Chromium `virtual_display_util_mac.mm` (BSD-3), Lunar open parts (MIT), nriley/brightness (BSD-2).
- Apple docs: CGConfigureOption, CGSetDisplayTransferByTable, CGDisplayRestoreColorSyncSettings, kCGDisplayShowDuplicateLowResolutionModes, NSScreen EDR properties, CALayer `wantsExtendedDynamicRangeContent` (14.0–26.0) and `contentsHeadroom` (26.0+).
- Apple Developer Forums: 795074 and 819331 (gamma broken on Tahoe / M5), 707680 (event-tap permissions), 765103 (Sequoia picker-bypass alert, persistent-content-capture), 808016 (sharingType .none vs SCK), 674047 (EDID on M1).
- Swift Forums thread 59981 (App Intents metadata extraction).
- smcleod.net 2026-03 (M4/M5 HiDPI firmware cap); BetterDisplay wiki (feature list, XDR methods, integration/HTTP/URL); blackoutd README (facts only, GPL); BrightXDR/BrightIntosh READMEs (facts only, GPL); nonstrict.eu (SCContentSharingPicker); 9to5mac (Sequoia monthly prompts); Lunar author's EDID notes.

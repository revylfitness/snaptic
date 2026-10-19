# Snaptic UI audit (feature/displays == main @ 871c10b)

Read-only audit of `Sources/Snaptic` (SwiftUI settings + AppKit menus). All paths are relative to
`/home/claude/snaptic/Sources/Snaptic/` unless they start with `SnapticKit/`.

---

## 1. Slider bug: root cause

### 1.1 How pages are wired

- Every Displays page gets `@ObservedObject var env: DisplaysPageEnvironment`.
- `DisplaysPageEnvironment` (`Displays/DisplaysRuntimeState.swift:62-81`) forwards
  `objectWillChange` from exactly **two** objects (lines 76-77):
  `ConfigStore<DisplaysConfig>` (`@Published var value`, `Core/ConfigStore.swift:11`) and
  `DisplaysRuntimeState` (its own `@Published` fields: `displays`, `effectiveFeatures`,
  `availability`, `moduleState`, panic flags).
- Per-display live values sit in a **separate** `ObservableObject`, `DisplayRuntime`
  (`DisplaysRuntimeState.swift:6-20`: `brightness`, `contrast`, `volume`, `muted`, `input`,
  `powerOn`, `xdrScale`, `statusText`). These objects are stored in
  `private var perDisplay: [DisplayKey: DisplayRuntime]` (line 32). That dictionary is not
  `@Published`, and nothing subscribes to the children's `objectWillChange`. **A change to any
  `DisplayRuntime` never reaches `env`, so no page that observes only `env` redraws.**
- Services and controllers (`BrightnessService`, `DDCController`, `ResolutionController`,
  `PanelPropsController`, `ProtectionController`, `LayoutsController`, `VirtualController`,
  `SmartHiDPIController`, `SystemColorsController`, …) are plain classes, not
  `ObservableObject`. The only observable service is `CaptureService`. A page that reads their
  state in a binding getter redraws only by chance, when some other change touches `env`.

### 1.2 Broken patterns, with locations and fixes

| # | Where | What is wrong | Symptom |
|---|---|---|---|
| A1 | `Displays/UI/BrightnessPage.swift:157-162` (Brightness page, main slider) | The getter reads `b.value(for:)`, which comes from `BrightnessService`'s private `states` dict (`Displays/Brightness/BrightnessService.swift:157-160`), with `live.brightness` as the fallback. `live` (`BrightnessPage.swift:157`) is a `DisplayRuntime` the view does not observe. The setter `b.set` (`BrightnessService.swift:233-247`) changes service state and `runtime(for:).brightness` (line 542), and neither invalidates the page. | The NSSlider knob follows the mouse, but the `CSlider` % readout, the accessibility value, Method/Snap marks/Nits "Now" and every other live row freeze. Changes from keys, menu, sync or auto-brightness don't show. About 1 s after the drag, `flushSave()` (`BrightnessService.swift:638-661`) writes `perDisplay.brightness.value` into config, so the readout jumps once. That only happens if the rounded value changed, and never for changes that skip the save (`source == .restore`). |
| A2 | `Displays/UI/DDCPage.swift:137-148` (Volume, Contrast) | The getter reads `live.volume` / `live.contrast` (`DisplayRuntime`, not observed). The setter `controller.setFraction` (`Displays/DDC/DDCController.swift:232-238`) changes `live.volume` synchronously and then writes DDC asynchronously. Nothing goes to config. | Readout never updates until the page is rebuilt (leave and come back). **This is the exact reported behaviour.** |
| A3 | `Displays/UI/DDCPage.swift:503-516` `CustomSliderRow` | `@State private var value = 0.5` is never seeded from `ddc.lastReading`. | Always opens at 50% whatever the monitor's value. Resets to 50% when you come back. |
| A4 | `Displays/UI/ColorPage.swift:12-13, 259-279` Night Shift toggle and Warmth | Local `@State`, loaded only in `.onAppear(loadNightShift)`. | Changes from the menu or a shortcut while the page is open aren't shown. |
| A5 | `Displays/UI/ColorPage.swift:213-225` auto-brightness toggle; `KeysPage.swift:63`; `DDCPage.swift:109,116` | Manual `env.objectWillChange.send()` pokes, used because the state isn't observable. | Proof the authors met this problem and patched individual places instead of the source. |
| A6 | `Displays/UI/ArrangementPage.swift:138,144,150-156` (Rotation, HDR, Underscan) | Getters read `PanelPropsController` state (`c.rotation(d)`, `c.hdrEnabled(d)`, `c.underscan(d)`). Underscan uses a draft with an "Apply" button. | A Picker or Toggle can snap back or show a stale value until a display reconfiguration changes `runtime.displays`. |
| A7 | `Displays/UI/ProtectionLayoutsPage.swift:28-32, 83, 103-104` | `c.isProtectingCurrent`, `c.layouts`, `c.matches`, `c.isTrusted` are controller state. | Toggle and list are stale after an edit. A trust change doesn't redraw. |
| A8 | `Displays/UI/VirtualScreensPage.swift:143-154, 306-314` | `c.isLive`, `c.isBusy`, `c.isActive`, `c.pairs` are controller state. | "Connected" and Smart HiDPI switches lag or bounce, and the busy state never shows. |
| A9 | `Displays/UI/ResolutionPage.swift:75-82` | `canUndo`/`canRedo`/favorites come from `ResolutionController`. | Correct only after the mode change goes through `runtime.displays`. Undo/Redo enablement can be stale. |
| A10 | `Displays/UI/PIPPage.swift:115` | Row "Start/Stop" reads `capture.sessions`, but `PIPPage` observes only `env`. (`PIPRunningSection` observes `capture` correctly, at line 302.) | The configuration row button label is stale. |
| A11 | `Displays/UI/SafetyPage.swift:9-10,124,134` | A 2 s `Timer` bumps `@State tick` to fake observation of `guardClient`. | Workaround. Values lag by up to 2 s. |
| B1 | `Switcher/SettingsView.swift:346-361, 438-445` `ShortcutEditor` | `@State local = State(initialValue: shortcut)` is copied once. `ForEach` keeps the identity because the id is stable. | After Reset, import, outside changes or sanitising, the editor shows old values until the page is re-entered. |
| B2 | `Displays/UI/AutomationPage.swift:135-138` (`CommandEditor.argumentsText`), `194-200` (`HookEditor`), `238-245` (`ActionEditor`) | Same `@State(initialValue:)` copy. `updateHook`/`updateAction` store `sanitized()` values (lines 63-66, 103-106) that never flow back. | Shows text the store has already truncated or changed. Outside edits are invisible. |
| B3 | `Displays/UI/DisplayIdentityPage.swift:233` `NameField` | The draft loads only `.onAppear`. | A rename from elsewhere (CLI, import) isn't shown. |
| C1 | All config-bound sliders (`CBind.global/display`, `BrightnessPage.swift:7-22`; `ManagementBindings`, `ManagementPageParts.swift:67-83`; PIP `field()`, `PIPPage.swift:606-616`) | These **do** redraw, because `ConfigStore.value` is `@Published` and forwarded. But every slider tick (a) copies and writes the whole `DisplaysConfig`, (b) runs a full `!=` in `ConfigStore.didSet`, (c) schedules a save, (d) queues a main-thread hop that runs `configDidChange` on every running controller (`Displays/DisplaysModule.swift:151-155, 263-276`), and (e) for Color, re-applies gamma tables (`Displays/Brightness/ColorController.swift:80-87`). `ManagementBindings.perDisplay` also runs `sanitized()` on each tick. | Works, but laggy or stuttering drags. On a slow path the knob can look unresponsive, which reinforces the user's impression. |
| C2 | `Switcher/SettingsView.swift:111` thumbnail size | Direct `$settings.config.thumbnailSize`. `AppSettings.didSet` saves to UserDefaults **synchronously on every tick** (`Switcher/Settings.swift:402-407`). There is no value readout. | No value is shown, and every tick does a disk write. |
| M1 | `Core/MenuSliderItem.swift` (the menu slider) | No value label at all. Only the brightness slider has an in-place update path (`BrightnessMenuItems.update`, `Displays/UI/BrightnessMenuItems.swift:100-108`, called from `BrightnessController.swift:306-307`). Volume, contrast and custom DDC sliders (`Displays/UI/DDCMenuItems.swift:48,57,92`) and the resolution slider (`Displays/UI/ResolutionMenuItems.swift:33`) are never refreshed while the menu is open. Custom range sliders default to 0.5 with no reading. The initial `value` goes into `NSSlider(value:minValue:0,maxValue:1)` before `range` is set (`MenuSliderItem.swift:25-27`), so a value above 1 is clamped. That only works today because `BrightnessMenuItems` calls `setValue` again afterwards. | In the menu: no numeric feedback, volume and contrast don't follow key presses or readback, and the custom slider is wrong. |

**The pattern that works today:** `DisplayControlsCard` (`Displays/UI/DisplaysOverviewPage.swift:169-193`)
holds `@ObservedObject private var live: DisplayRuntime`, and `DisplaySliderRow` (lines 370-407)
keeps a local `dragging` value cleared in `onEditingChanged`. On the Overview page and in the
floating panel, brightness and volume update live. It has its own flaws: the range is fixed at
0…1 (line 255, and `BrightnessService` stores `min(1, position)` in the runtime), so the XDR
range is invisible.

### 1.3 Fix pattern

1. **Make live state observable at the source.** Either:
   - (a) In `DisplaysRuntimeState.runtime(for:)`, subscribe to each new `DisplayRuntime.objectWillChange` and forward it to `self.objectWillChange` (simple, coarse, low-rate because readback writes only on change). Or:
   - (b) Better: move each per-display section into a subview with `@ObservedObject var live: DisplayRuntime`, as `DisplayControlsCard` does.

   Also publish the **full** brightness position (with XDR) in `DisplayRuntime` (for example `@Published var brightnessPosition`), so pages never read `BrightnessService.states`.
2. **Controllers whose state pages show** should either become `ObservableObject` with `@Published` (rotation/HDR/underscan, protection, layouts, virtual live/busy, Smart HiDPI pairs, undo/redo, Night Shift), or bump a published `revision` on `DisplaysRuntimeState`. Then delete the `objectWillChange.send()` pokes and the Safety timer.
3. **One shared `SettingSlider` component.** Local `@State editing: Double?` during the drag, clamped against `range`. Commit through the binding, throttled with `SnapticKit/RateLimiter.swift:79 LatestValueThrottle` or committed at `onEditingChanged(false)`. Shows `editing ?? binding`, an editable numeric field with a unit formatter (commit on Return or blur, clamped), a reset button or double-click reset to an explicit `defaultValue`, and an optional help line. Use it for every slider in Settings.
4. **Replace `@State(initialValue:)` copies** with direct bindings, or resync with `.onChange(of: source)` (`ShortcutEditor`, `HookEditor`, `ActionEditor`, `CommandEditor`, `NameField`).
5. **`MenuSliderItem`:** add a trailing value label (percent or unit), take `range` in `init`, and give it a `bind(to: Published<Double?>.Publisher)` (or a contributor-held weak ref plus an update hook) so volume, contrast and resolution follow live changes the way brightness already does.

---

## 2. Settings inventory

### 2.1 Sidebar (`Core/SettingsWindowHost.swift:92-133`, `Displays/DisplaysModule.swift:41-59`)

| Section | Pages (default visibility) |
|---|---|
| General (9) | Modules, Menu, Command-Line Control, Startup, Permissions, Backup & Reset, Safe Mode, Other Display Apps, About & Licenses |
| Window Switcher (6) | Switcher Features, Shortcuts, Behavior, Thumbnails, App Lists, Privacy |
| Displays (11 default → 16) | Displays (Overview), Display Features, Resolution, Brightness, DDC & Monitor Controls, Keys & Shortcuts, On-Screen Display, Arrangement, Display Names, Safety, Diagnostics. Opt-in pages appear when a feature is on: Color, Protection & Layouts, Virtual Screens & HiDPI, Picture in Picture, Automation |

**26 sidebar rows by default, 31 at most.** Problems:
- **Names don't match:** sidebar "DDC & Monitor Controls" vs Features-page group "Monitor Controls" (`SnapticKit/DisplaysUIModel.swift:23`); "Virtual Screens & HiDPI" vs "Virtual Screens"; "Displays" (sidebar) vs "Overview" (Features group) vs "Overview & display names" (feature title); "Picture in Picture" vs "Picture in picture".
- **Duplicate icons:** `switch.2` for both Features pages; `keyboard` for both Shortcuts pages; `slider.horizontal.3` for the DDC page and the "Show Displays Panel" menu item; "Safety" (Displays) and "Safe Mode" (General) sit near each other with similar names.
- **Pages appear and disappear as features change** (`DisplaysModule.settingsPages()` at line 201). Turning a feature on moves the sidebar.
- **Localisation:** Window Switcher strings in `Switcher/SettingsView.swift` don't go through `L()`, unlike everything else.

### 2.2 Per-page inventory

Legend: **Expl** = explanation (✓ per-control caption, § section footer or caption only, ✗ none).
**Adv** = advanced or expert. Counts are adjustable controls only, not action buttons or read-only
rows, for a 1 built-in + 1 external DDC monitor setup.

#### General

| Page | Controls (type) | Expl | Adv | Notes |
|---|---|---|---|---|
| Modules | Window Switcher (switch), Displays (switch). Card: Turn On Displays…, Not Now | ✓ summary | | OK. "Starting…" state text. |
| Menu | Per module (×2): **Show** picker (In Snaptic's menu / Own menu bar icon / Hidden), **Icon** picker (own icon), Displays: "Hide the icon when no external display is connected". Snaptic's menu: **Icon** picker, "Scroll on a slider to adjust". Then the whole `MenuCustomizationPage`: Display blocks (Expanded/Compact), Main display first, Status badges in display headers, Show the header row with only one display, Section order (2 rows of ▲▼), Display order (N rows of ▲▼, "Use the Default Order"), then **one Visible/In submenu/Hidden picker per registered menu item** (≈20 with default features: Display blocks 11, Display headers 1-2, Tools 6, Right-click 2), Reset Menu Settings | § footers only | mostly | **About 28 controls on one page.** Icon pickers label each choice with the raw SF Symbol name (`Core/GeneralPages.swift:216, 250`). The descriptor titles are developer-ish ("Volume slider (DDC)", "Standby switch (DDC)", "Header connect switch"). The order rows duplicate Display Names. |
| Command-Line Control | Allow command-line control, Let commands skip the confirmation panel (toggles), Copy install command | § | ✓ | Fine. Exit-code footer is developer detail. |
| Startup | Launch Snaptic at login | ✗ | | A whole page for one toggle. |
| Permissions | 2 permission rows (Open Settings), Relaunch | ✓ | | |
| Backup & Reset | Export…, Import…, Reset All Settings… | § (very long) | | Single long footer. |
| Safe Mode | Restart in Safe Mode / Leave | ✓ | | Lists of strings. |
| Other Display Apps | radio: Pause overlapping / Run both | § | | |
| About & Licenses | Check for Updates… | | | Full MIT text inline. |

General total: **about 34 controls on 9 pages.**

#### Window Switcher

| Page | Controls | Expl | Adv | Overlaps and confusing names |
|---|---|---|---|---|
| Switcher Features | 14 toggles in 4 groups (Thumbnails, Preview, Other Spaces, Windowless apps / Search, Close, Minimize, Fullscreen, Hide, Quit / Hover buttons, Hover select / ⌘⇥ takeover, Passthrough) + permission rows | ✓ each | | It's "the only place for on/off switches", yet aliased features (`preview`, `otherSpaces`, `hoverSelect`) are just other settings by another name (`Switcher/SwitcherPages.swift:104-130`). |
| Shortcuts | Per shortcut (2 by default): Modifier picker, Key picker, Show (scope), Style, Spaces pickers, 3 toggles (Include minimized and hidden, Include apps with no open windows, One entry per app), Delete; Add shortcut; Gather windows ShortcutRecorder | § | some | **16+ controls in a dense VStack** per shortcut. "Include apps with no open windows" (per shortcut) overlaps the global Features → windowless apps. "Spaces" picker overlaps Features → Other Spaces. Stale editor (B1). |
| Behavior | Switch when the modifier key is released, Show the switcher on (picker) | § "see Features" | | Its footer sends you to another page. |
| Thumbnails | Auto-size (toggle), Size (slider 100–300, **no readout**) | ✗ | | Slider has no value, unit or reset. |
| App Lists | Hidden from the switcher (list), Apps that keep the shortcut (list), Only while the app is full screen | § | ✓ | |
| Privacy | Never capture password managers… (toggle), Never capture these apps (list) | § (long) | | Separate from PIP → Privacy, a second capture-exclusion list. |

Switcher total: **about 40 controls on 6 pages.**

#### Displays

| Page (file) | Controls (type) | Expl | Adv | Duplicates, overlaps, confusing names |
|---|---|---|---|---|
| **Displays / Overview** (`DisplaysOverviewPage.swift`) | Per display card: power switch (DDC power), Brightness slider, Volume slider + mute, Resolution slider + Resolution picker, Input picker. Tools: Identify, Redetect, Show Displays Panel. **Displays panel shortcut** and **Identify shortcut** recorders. "Active features: n of 49" | ✗ (one caption) | | Brightness, volume and resolution also appear on their own pages, in the menu and in the panel (4 surfaces). The two shortcut recorders write `menu.showPanelShortcut` / `menu.identifyShortcut` (line 73-78), while Keys & Shortcuts lists the *same actions* writing `keys.shortcuts[f.showPanel]`. **Two separate stores for one shortcut, with no cross-check for conflicts.** Card slider range is fixed 0…1 (no XDR). About 10 controls. |
| **Display Features** (`FeaturesPage.swift`) | **47 switches** (49 features, 2 always on) in 13 groups, each with a summary caption, Beta (5) / Experimental (7) badges, status lines, permission rows | ✓ | mixed | Exposes implementation details as user features: "Apple native brightness", "DDC brightness", "Software dimming (gamma)", "Software dimming (overlay)", "OSD broadcast", "HDR virtual modes", "PIP filters". Feature groups are named by page, but some features sit in odd groups (auto-brightness and menu-bar overlays under Color, sleep prevention under Arrangement). Every other page also has "X is off · Turn On" rows, so feature toggles are effectively on two pages. |
| **Resolution** (`ResolutionPage.swift`) | Global: Confirm resolution changes (picker), Offer modes below 720p, Remember my choice… (toggles). Slider: Show values as (picker), Snap to favorites… (hold ⌥), Only native aspect ratio. Per display (×2): Mode picker, quick buttons (HiDPI, Native, Default, Native ÷ 2, Notch), Undo/Redo, Add to Favorites, Favorite rows (Apply/Remove), Show (DPI filter), Refresh rate, Width limit Min–Max text fields + Clear, Include in Match UI Size, Forget remembered. Show all modes (experimental): display picker + Try list. Match UI size: Reference display, Tolerance slider (no reset), Preview/Apply | § | ✓ (filters, width limits, 720p, aspect) | **"Confirm resolution changes" is duplicated in Safety, with a different option label** ("Never for public modes" here, line 21, vs "Never for listed modes" in `SafetyPage.swift:22`). "Include in Match UI Size" shows even when Match UI size is off. "Native ÷ 2", "Show: HiDPI and standard", "Width limit" and "Tolerance" have no explanation. About 20 controls plus about 20 buttons. |
| **Brightness** (`BrightnessPage.swift`) | Top: 5 feature-off rows (brightness + 4 methods). Display picker. **Brightness** slider (broken, A1), snap-marks caption, Method (read-only) + reason, **Use** (method picker), Custom software-dimming switchover (toggle + Switchover slider), Minimum hardware level (slider), Color-table dimming status + Ask Again. Nits (opt-in): Now, Custom range, Minimum / Maximum (SDR) / Peak (HDR) number fields, Show nits in the menu and OSD. XDR per display (beta): Extra brightness on this display, Custom maximum toggle + **Maximum** slider, Test. Sync per display: Follow the sync source, Offset slider. Global: Restore (picker), Smooth transitions. Dimming: dim-to-black note, Dim on lock to (slider). Brightness sync: Sync on, Source, Follow, Follow outside changes. Extra brightness (XDR): **Maximum** slider, **Method** picker ("Overlay (A)" / "Color table (B)"), Pause below battery slider, Pause in Low Power Mode, Stop at 100%… | § (captions after most sections) | ✓ (switchover, min HW, gamma check, nits, XDR method) | Default: about 7 controls plus 5 "is off" rows. All on: about 27. **Two sliders both titled "Maximum"** (per-display line 265, global line 363). Three different "Method"s (read-only Method, "Use", XDR Method). "Show nits in the menu and OSD" (`brightness.showNits`, line 246) overlaps OSD → "Show nits" (`keys.osdShowNits`), so two settings mean one thing. "Restore: Brightness and adjustments / Adjustments only" refers to Color-page adjustments. The page mixes per-display (top) and global (bottom) sections with no visual separation. |
| **Color** (opt-in, `ColorPage.swift`) | Display picker. Suspend adjustments on this display / on all displays. Contrast, Gamma, Gain, Temperature, Black level, White level (6 sliders), Invert colors. "Red, green and blue" disclosure: Red/Green/Blue gain, Red/Green/Blue gamma (6 sliders). Reset This Display. Color profile picker + Show in Finder / Open in ColorSync Utility / Restore Previous. Apple display preset picker. Auto-brightness toggle. Menu bar and corners: Black strip behind the menu bar, Top/Bottom corner radius (sliders, step 0.001). Custom color profiles: "Keep color-table dimming and adjustments with a custom profile". Night Shift: on toggle + Warmth slider | § | ✓ (gain, levels, per-channel gamma, safeguard) | About 25 controls, **14 sliders**, none with reset (only a page-level "Reset This Display"), field or explanation. "Contrast" here (software) and on DDC (hardware) share a name. Temperature overlaps Night Shift Warmth. Menu bar strip and corners have nothing to do with color. |
| **DDC & Monitor Controls** (`DDCPage.swift`) | 4 feature-off rows. All monitors: Read values back periodically, Every (slider 0.5–60 s), Re-send values after wake…. Display: picker (external only), Use DDC with this display, status rows (Status, Connection, **Framing**, Writes today, Model, **MCCS**, **Supported codes** hex dump), Read Capabilities, Check Connection. Controls: Volume and Contrast sliders (broken, A2), then **one disclosure per VCP code** (Brightness 0x10, Contrast 0x12, Volume 0x62, plus any listed) with: Use (Automatic/On/Off), **Raw value for 0%**, **Raw value for 100%** + Reported, Invert, Show in menu (Default/Yes/No), **Read back every (s, 0 = default)**. Inputs (opt-in): per input name field, Hide checkbox, ▲▼, Switch, Add Input menu (incl. "LG alternate: …"), Reset List. Power (opt-in): State, **Standby sends** (Standby (2) / Suspend (3) / Off (4)), Turn On, Standby…. Custom controls (opt-in): list + Name / Code (hex) / Kind / Value / Add. Raw VCP: Code, Value, Read, Send, "Manufacturer code to unlock (E0–FF)", Unlock, Lock All. Timing: **Reply delay** stepper, **Retries** stepper, Send every write twice, **Ignore reply checksums**, Forget Learned Framing. Allowed without asking | § | **almost everything** | **Worst page.** About 29 controls by default, about 45 with everything on. Protocol-level internals (framing, checksums, reply delay, raw VCP, MCCS, hex dumps) sit at the same level as Volume. "Allowed without asking" is duplicated in Safety. The volume slider is broken. |
| **Keys & Shortcuts** (`KeysPage.swift`) | Permission (pane, Media keys status, Grant, Try Again). Brightness keys (opt-in): **Use them** (picker), Also let macOS handle brightness keys, **Keys change** (picker), **Steps** stepper, **Fine steps (⌥⇧)** stepper, F14 and F15 change brightness. Volume keys (opt-in): Send volume to a monitor (picker), Also let macOS handle volume keys / the mute key. Per display: picker, Keys change this display, Show the volume OSD, **Sound output name** field. Modifiers: 7 read-only rows. Shortcuts: Filter field + **one ShortcutRecorder per registered action (about 35 with default features**: Brightness ±, ±fine; Volume/Contrast ±, ±fine; Mute; 9 resolution actions + 5 favourites; Set as Main, Toggle Mirroring; Identify, Redetect, Panel; Restore All, Resume; Diagnostics). Input slots (opt-in): per slot display / input / LG / delete, Add Slot | § | some | **Longest page by rows.** A flat alphabetical list of about 35 recorders with no grouping. Panel and Identify shortcuts are duplicated (see Overview). "Use them", "Keys change" (verb or noun?) and "Steps" (steps from 0–100%?) have no explanation. "Show the volume OSD" overlaps the OSD page. The Modifiers table is static reference text in a settings form. |
| **On-Screen Display** (`OSDPage.swift`) | Style (picker, Automatic (x)), Position (picker), Show on (picker), Show the value, **Show nits** (dup), Use the system OSD when possible (14/15), Preview. Broadcast (opt-in): notification name | § | | 6 controls. Fine apart from the nits duplicate. |
| **Arrangement** (`ArrangementPage.swift`) | Canvas (drag), Snap to edges while dragging, **Position/Align form** (Move picker, Placement picker with 16 options, Relative to, Move Display), Main display picker, Mirroring picker per display, then feature-off rows for Rotation, HDR switch, Underscan, Disconnect, Auto-disconnect, Prevent display sleep (6 rows). When on: Rotation picker, HDR toggle, Underscan slider + **Apply** (A6), Disconnect: per display **"Header switch"** picker + Connect/Disconnect, Connect All. Auto-disconnect: "My monitor has no DDC (allow without a power reading)", Never auto-disconnect <built-in>. Sleep: Prevent display sleep while X is connected | § | ✓ (header switch, auto-disconnect) | The Position/Align form duplicates the canvas (an accessibility path presented as a peer). "Header switch" refers to the menu header row and belongs in Menu settings. Sleep prevention has nothing to do with arrangement. Default: about 7 controls plus 6 off rows. |
| **Protection & Layouts** (opt-in) | Protect the current arrangement, Save Current State as Protected (disabled when *not* protecting, which is odd), 5 field toggles (Resolution, Position, Main, Mirroring, Rotation), Forget All. Layouts: name + Save Current Layout, Offer Undo after an automatic apply, per layout: name, status labels (Matches, No serial number, Trusted), Apply automatically (picker), **Priority** stepper (-100…100), Apply, Stop Trusting, Update to Current, Move Up/Down, Delete | § | ✓ (priority, trust) | 7 + 3 per layout. Jargon: Trusted, tier-2 match, Priority. Six text buttons on one row. |
| **Virtual Screens & HiDPI** (opt-in) | Per screen: Connected switch, Edit…, Delete. New: Shape picker (11 aspect presets) + Create, 4 recipes (Headless, Recording 16:9, Teleprompter + target picker, Portrait) + Create. All: Connect/Disconnect/Reconnect/Disassociate/Discard All. Behavior: 3 toggles. Editor sheet: Name, Aspect W:H fields, Fill Sizes, Diagonal (inches), HiDPI, Portrait, Reconnect at launch, HDR modes, Refresh rate (Hz), **Sizes in points, one per line** (TextEditor with "1920x1080" lines), Associations (Connect: Manually / While connected / While disconnected; Show: Nothing / Mirror / Stream / Flipped stream). Smart HiDPI per display: toggle, Size, HDR (PQ) | § | ✓ (sizes editor, associations, aspect) | About 22. A raw text-editor mode list is not Mac-like. Five bulk buttons. |
| **Picture in Picture** (opt-in) | Intro + "Got It". Screen Recording row. Running (Pause/Show/Crop/Stop, bulk). Per display: config rows (Start/Stop, Edit) + New PIP / New Full-Screen Stream. Windows section. **Editor:** Name, Show as, Stream onto, Offer to start…, Delete; Window: Level, Opacity slider, Click through, Lock position, Keep aspect, Sharp pixels, Title bar, Snap size to 25% steps, Shadow, Reset Window Position; Capture: Match refresh toggle, Frame rate slider, Show the pointer, ⌘-click moves the pointer…, Crop + Draw/Reset; Orientation: Rotate, Flip H, Flip V (teleprompter); Full Screen: Scaling, Size slider, native mode toggle; Filters: LUT picker, per filter toggle/▲▼/trash + parameter sliders, Add Filter menu. LUTs: Import .cube…. Privacy: bundle prefixes list + field + Restore Defaults. Options: Pause covered PIPs, ⌃⌥⌘P stops streams… | § | ✓ (LUTs, filters, prefixes) | About 30 per configuration. The editor opens *inline* below the list in the same Form, so the page grows very long. Second capture privacy list (see Switcher Privacy). |
| **Automation** (opt-in) | Per hook (disclosure): Name, Enabled, When, Display, Delay stepper, Program path + Choose…, Arguments TextEditor. Per action: Name, Show in the menu, Allow from the command line, Shortcut recorder, Program, Arguments, Run Now, Delete | § (long) | ✓ | Stale-copy editors (B2). The custom-action shortcut is a third place shortcuts live. |
| **Display Names** (`DisplayIdentityPage.swift`) | Per display: Name field, Use the System Name, **Icon** picker, **Show in the menu and the Displays panel**, **Menu order ▲▼**, Details disclosure, EDID disclosure (Copy Hex, Copy Base64, Export .bin…), Copy Settings From…. Remembered: Forget…, Forget All… | § footer | EDID | Show-in-menu and order **duplicate General → Menu → Display order** (`MenuCustomizationPage.swift:54-97`). The page name "Display Names" undersells it: it also covers identity, EDID, settings transfer and forgetting. |
| **Safety** (`SafetyPage.swift`) | Confirm resolution changes (**dup**), Revert automatically after N seconds (stepper), Tell me when displays were restored…, Restore All: Keyboard shortcut toggle (fixed ⌃⌥⌘⎋, not editable), Restore All Displays Now, Resume. Safety helper: Status, Can revert rotation and HDR, Pending confirmation, Undo journal (internals). Allowed without asking (**dup** with DDC). Remembered resolutions (Forget). **Unavailable on this Mac** | § | ✓ | `LabeledContent(feature.rawValue, …)` at **line 117 shows camelCase identifiers** ("hiddenModes"). The diagnostics rows belong on Diagnostics. 4 controls. |
| **Diagnostics** | Copy Report, Export…, Refresh. Report sections + last 60 events (monospace) | § | ✓ | Doesn't refresh live. OK. |

**Onboarding** (`Core/Onboarding.swift`, `Displays/UI/DisplaysOnboardingStep.swift`): Welcome → Choose your
tools (2 switches) → Displays chips (up to 7 multi-select chips: Basics, Brightness & volume keys, Sharper text,
Virtual screens, Picture in picture, Extra brightness, More), conditional "Hide the menu-bar icon" and "Turn on Smart
HiDPI (Beta)", Summary ("Turns on: <long list of feature titles>") → Permissions → Done.
Problems:
- The Displays step has its **own** default button, "Use These Features" (`.defaultAction`, line 144), *inside* the form, plus "Skip" in the window footer (`Onboarding.swift:176-180`). The other steps put "Continue" in the footer, so primary actions jump between two places.
- In the "New: Displays" sheet the same view sits beside "Keep Defaults" (`GeneralPages.swift:159-167`), which makes two competing primaries.
- The summary lists raw feature titles.
- The chips are buttons styled as rows, not toggles.

### 2.3 Totals

| Scope | Pages | Adjustable controls (approx.) |
|---|---|---|
| General | 9 | about 34 (28 of them on Menu) |
| Window Switcher | 6 | about 40 |
| Displays, default features | 11 | about 170 (Features 47, Keys about 36, DDC about 29, Resolution about 18, Overview about 10, Brightness about 7 + 5 off rows, Arrangement about 7 + 6 off rows, Names 6, OSD 6, Safety 4) |
| Displays, everything on (1 hook, 1 action, 1 layout, 1 PIP config, 1 virtual screen) | 16 | about 330 |
| **Default user sees** | **26** | **about 245** |
| **Power user sees** | **31** | **about 400+** |

About 116 inline `.font(.caption).foregroundStyle(.secondary)` captions, 25 section footers and only 9
`.help()` tooltips exist. Explanations are paragraph captions after a section, not tied to
individual controls. Most rows (DDC tuning, Keys steps, OSD pickers, Resolution filters, Color
sliders, PIP window toggles, menu-item pickers, Startup) have **no** explanation.

**Reset to default:** only 8 reset-style buttons exist, all page- or list-level ("Reset Menu
Settings", "Use the Default Order", DDC "Reset List", Color "Reset This Display", PIP "Restore
Defaults", "Reset Window Position", "Reset Crop", "Reset All Settings…"). **No slider or field
has a per-control reset.** The `CBind.optional` "Custom …" toggle (switchover, XDR max) is the only
"default vs custom" idiom.

**Typed values:** no slider has a companion number field. Numeric `TextField`s exist only where
there is *no* slider (nits, DDC raw, width limits, virtual screen). Steppers show the value but
can't be typed into.

### 2.4 Duplicates and overlaps (consolidated)

1. **Confirm resolution changes:** Resolution page (`ResolutionPage.swift:18`) and Safety page (`SafetyPage.swift:19`), with different labels for the same option.
2. **Allowed without asking:** DDC page (`DDCPage.swift:492`) and Safety page (`SafetyPage.swift:74`).
3. **Show nits:** `brightness.showNits` (Brightness, line 246) and `keys.osdShowNits` (OSD, line 35).
4. **Display order and visibility:** Display Names (`DisplayIdentityPage.swift:111-123`) and General → Menu (`MenuCustomizationPage.swift:54-97`).
5. **Show Displays Panel and Identify shortcuts:** Overview recorders (`menu.*Shortcut`) and the Keys & Shortcuts action list (`keys.shortcuts`), stored separately.
6. **Feature on/off:** the Display Features page plus a "X is off · Turn On" row on almost every page. There are four implementations: `CFeatureNote` (`BrightnessPage.swift:33`), `ManagementFeatureNotice` (`ManagementPageParts.swift:7`), `AutomationPage.featureOff` (line 108) and PIP "Turn On Filters" (`PIPPage.swift:174-176, 517-519`).
7. **Live controls on four surfaces:** brightness, volume and resolution appear on the Overview page, their own pages, the menu and the floating panel. Ranges differ (Overview 0…1, Brightness page `b.range` including XDR).
8. **Contrast:** software (Color) and hardware (DDC), same label.
9. **Warmth:** Color Temperature vs Night Shift Warmth.
10. **Capture privacy:** Switcher → Privacy vs PIP → Privacy.
11. **Switcher:** per-shortcut "Include apps with no open windows" and "Spaces" vs Features → Windowless apps / Other Spaces.
12. **Volume OSD:** Keys → "Show the volume OSD" (per display) vs the OSD page.
13. **Menu-related settings in Displays pages:** "Header switch" (Arrangement), "Show in the menu…" (Names); "Scroll on a slider to adjust" lives in General → Menu but is stored in `DisplaysConfig.menu`.
14. **Restore All Displays:** Safety, menu Tools, quick menu, floating panel (acceptable for a safety action, but its shortcut can't be edited anywhere).

### 2.5 Worst offenders (ranked)

1. **DDC & Monitor Controls.** Protocol internals mixed with everyday volume and contrast. 3+ disclosures of raw tuning. Broken live sliders.
2. **Keys & Shortcuts.** About 35-row flat recorder list, ambiguous labels, duplicated shortcuts, static modifier table.
3. **General → Menu.** About 28 controls, including about 20 identical Visible/In submenu/Hidden pickers with developer titles and raw SF Symbol names.
4. **Display Features.** 47 switches, many of them implementation details (4 brightness "methods", OSD broadcast, PIP filters, HDR virtual modes), and they reshape the sidebar.
5. **Brightness.** Per-display and global settings interleaved, three "Method"s, two "Maximum"s, five "is off" rows at the top, the main slider broken.
6. **Color.** 14 bare sliders, no per-slider reset, unrelated menu-bar strip and corners, a long safeguard label.
7. **PIP editor.** About 30 controls inline in the same page.
8. **Safety.** Duplicates, internals, camelCase feature ids.

---

## 3. Menu bar menus

### 3.1 Builders

- `Core/StatusMenu.swift`: the shared and own-icon status items. `build()` (lines 191-228) adds a sectionHeader per module when more than one shares the item, then each module's `menuSection()`, then the footer (lines 253-275): "More display features…" (upgrade card only), "Recent Notices ▸", "Settings… ⌘,", "Quit Snaptic ⌘Q". `buildQuick()` (lines 232-251) is the right-click / ⌃-click menu.
- Switcher section: `Switcher/WindowSwitcherModule.swift:100-129`.
- `Displays/UI/DisplaysMenuBuilder.swift`: banners, then display blocks and Tools (order from `MenuConfig.orderedSections`). Tools gets its own `sectionHeader("Tools")` plus "More Tools ▸" and "More Display Features…".
- `Displays/UI/DisplayMenuBlock.swift`: one block per display. A bold attributed header with an icon (lines 162-181), then `.header` slot items, `.display` visible items, and a "More ▸" submenu (`ellipsis.circle`) holding "in submenu" items and hints. Compact and collapsed variants exist.
- Contributors: `BrightnessMenuItems`, `DDCMenuItems`, `ResolutionMenuItems`, `ArrangementController`, `PowerController`, `PanelPropsController`, `SmartHiDPIController`, `SystemColorsController`, `ColorController`, `XDRController`, `SyncController`, `MenuBarOverlaysController`, `PIPMenuItems`, `VirtualMenuItems`, `LayoutsMenuItems`, `ProtectionController`, `AutomationController`, `PanicCoordinator`, `OverviewController`. That is **about 45 descriptors.**

### 3.2 Default menu: fresh install, both modules shared, 1 built-in (main) + 1 external DDC monitor with speakers, default features

```
WINDOW SWITCHER                               ← NSMenuItem.sectionHeader
  Enable Thumbnails (Screen Recording)…       ← only while not granted (thumbnail style is default)
  Press ⌥⇥ to switch windows                  ← disabled text row
  Gather Windows on This Display              ← no icon
─────────────
DISPLAYS                                      ← sectionHeader
  [laptop] Built-in Retina Display  Main      ← bold attributed title, enabled-looking, no action
  [sun]  ━━━━━━━━━━○━━━━                       ← MenuSliderItem, no value, no visible title
  [⋯] More ▸  { Resolution slider, Resolution ▸ (Toggle HiDPI / Native / Default /
               Native-Halved HiDPI / Toggle Notch / Undo / Redo / Favorites / ≤60 modes),
               Brightness Method ▸ (Automatic / Apple native / Color table (gamma) / Overlay),
               Mirroring ▸ }
  ─────────────
  [display] DELL U2720Q
  [sun]      ━━━━━━○━━━━━
  [speaker]  ━━━━○━━━━━━━                       ← volume, only if VCP 0x62
  [⋯] More ▸  { Resolution slider, Resolution ▸, Brightness Method ▸, Mute,
               Contrast slider, Set as Main Display, Mirroring ▸ }
─────────────
TOOLS                                         ← sectionHeader (third header style in one menu)
  [↺] Restore All Displays                    ← PanicCoordinator registers first
  [#] Identify Displays
  [⟳] Redetect Displays
  [≡] Show Displays Panel
      Arrange…                                ← ManagedMenuItem, no icon
  [switch] More Display Features…
─────────────
  Settings…            ⌘,
  Quit Snaptic         ⌘Q
```

That is **about 20 rows plus 4 separators (about 24 lines, 2 of them 30 pt-tall custom slider rows)**, and
**3 nested "More"-type entries per display** (More ▸, its Resolution ▸ / Brightness Method ▸ / Mirroring ▸
submenus), plus "More Display Features…". Opt-in features add header switches (Standby "Screen On",
connect switch), XDR, color, sync, Night Shift, PIP, virtual, layouts, protection, Connect All,
custom actions and more. A typical power user's menu grows past 35 rows.

**Quick menu (right-click):** Settings… ⌘, │ Restore All Displays, Redetect Displays (+ Connect All Displays if
Disconnect is on) │ Quit Snaptic ⌘Q.

**Floating Displays panel** (`OverviewController.swift:257-432`): a 360 pt non-activating titled panel,
"Displays", transparent title bar. Per display: a `DisplayControlsCard(compact: true)` with icon, name,
badges, DDC power switch and `ellipsis.circle`. The ellipsis pops up the *whole NSMenu block* at the
pointer, mixing a SwiftUI panel with an AppKit menu. Below that: Brightness row, Volume row + mute
button, Resolution **slider and** Resolution picker (twice), Input picker, "X is off" hints with Turn
On. Footer: Identify, Redetect, Restore All, gear (all `.small`). More than 3 displays get a fixed
480 pt ScrollView.

### 3.3 Visual inconsistencies in the menus

1. **Three header styles** in one menu: `NSMenuItem.sectionHeader` (WINDOW SWITCHER / DISPLAYS / TOOLS), a bold attributed display title with an icon and inline grey badges (`DisplayMenuBlock.swift:162-181`), and disabled info rows (banners, "Press ⌥⇥…").
2. **Icons on some rows, not others.** Displays action items have SF Symbols; Switcher items, Settings/Quit, `ManagedMenuItem` (Arrange…, resolution and mirroring items) and `CMenu.item` (Mute, method choices) don't. Titles don't line up. **Five item factories:** `ClosureMenuItem` (`StatusMenu.swift:5`), `CMenu.item` (`BrightnessMenuItems.swift:117`), `ManagedMenuItem` (`Displays/Management/ManagementSupport.swift:223`), `DisplayMenuBlock.actionItem` (line 249), `PanicMenuItem` (`PanicCoordinator.swift:226`).
3. **Slider rows** (`MenuSliderItem.swift`): fixed 270×30 pt. A 13 pt secondary-tinted icon at x = 16 with a 6 pt gap, or a 20 pt inset without an icon, so slider tracks start at different x. `.small` control size. **No value readout, no visible label** (the title is accessibility-only, e.g. "Brightness — DELL U2720Q"). Scroll-to-adjust exists. Nothing like Control Center's large rounded track with the icon inside.
4. **Sliders inside submenus** (Resolution slider and Contrast slider are "In submenu" by default), which is unusual on macOS.
5. **The display header looks clickable but does nothing.** Its action is nil, and with `autoenablesItems = false` it renders enabled. It gets a submenu only when collapsed or compact.
6. **"More" naming:** per-display "More ▸", Tools "More Tools ▸", "More Display Features…" in Tools, and in the footer "More display features…" in sentence case (`StatusMenu.swift:255`) vs Title Case (`DisplaysMenuBuilder.swift:138`).
7. **Resolution submenu** mixes actions (Toggle HiDPI, Undo…), a "Favorites" disabled header and up to 60 checkable modes in one flat list.
8. **Menu-item visibility titles** shown in Settings are developer titles ("Volume slider (DDC)", "Header connect switch", "Standby switch (DDC)").
9. **Live updates:** only brightness updates in place while the menu is open (M1). Volume and contrast move in readback but the menu doesn't.

---

## 4. Shared UI components

| Component | Exists? | Where | Gaps |
|---|---|---|---|
| Labeled slider row | Partly: `CSlider` | `BrightnessPage.swift:80-106` (used on Brightness, Color, DDC; *not* on Resolution, Arrangement, PIP, Switcher, which use raw `Slider` with ad-hoc `Text`) | Title width varies, so tracks don't line up across rows. No reset, no value field, no help, no default marker. Reads the binding directly (no drag-local state), so it inherits every observation bug. |
| Live slider row | `DisplaySliderRow` | `DisplaysOverviewPage.swift:370-407` | The correct drag pattern, but hard-coded 0…1 and percent only. Not reused on pages. |
| Menu slider | `MenuSliderItem` | `Core/MenuSliderItem.swift` | No label or value. Update path exists only for brightness. |
| "Feature is off" row | **4 variants** | `CFeatureNote`, `ManagementFeatureNotice`, `AutomationPage.featureOff`, PIP inline | Different layout, font (`.callout` vs body) and wording ("X is off" + Turn On vs "Hooks are off."). |
| Help and explanation text | **3 ad-hoc ways** | `ManagementNote` (25 uses), inline `.font(.caption).foregroundStyle(.secondary)` (about 116), Section `footer:` (25) | No per-row subtitle convention. `.help()` is used only 9 times. |
| Section header | SwiftUI `Section("…")` / `header:` | everywhere | No icon or help affordance. Some sections mix header text and a feature-off row as their first row. |
| Setting row (title + subtitle + trailing control) | Only ad hoc: `FeatureRow` (`FeaturesPage.swift:101`), Switcher `row()` (`SwitcherPages.swift:91`), `PermissionRow` (`SettingsView.swift:320`), `ModuleRow` (`GeneralPages.swift:100`) | — | Four similar but different implementations. |
| Reset to default | **Missing** as a component | — | Needed per row and per slider. |
| Numeric entry with unit | **Missing** | Ad-hoc `TextField(value:format:.number)` (nits, DDC, width limits, virtual) | No unit, no clamping feedback, commits only on Return. |
| Display selector | `CDisplayPicker` | `BrightnessPage.swift:57` (Brightness, Color, DDC, Keys) | Other pages list every display in sequence (Resolution, Arrangement, Names, PIP) or use ad-hoc pickers (`PositionAlignForm`, `HiddenModesSection`, slot and teleprompter pickers). There is no consistent "selected display" header. |
| Reorder controls (▲▼) | **5 implementations** | DDC inputs, Display Names, `MenuCustomizationPage.moveButtons`, PIP filters, Layout "Move Up/Down" text buttons | Should be one component, or List `.onMove`. |
| Binding helpers | **5+ variants** | `CBind`, `ManagementBindings` (sanitises), `PIPPage.global/field`, `MenuCustomizationPage.menuBinding`, `SafetyPage.safety` (sanitises), many inline `Binding(get:set:)` | Inconsistent sanitising. None throttle or coalesce. |
| Badge | `DisplaysBadge` | `DisplaysOverviewPage.swift:149` | OK. |
| Status banners | `DisplaysStatusSection` | `DisplaysOverviewPage.swift:83` | Repeated at the top of most pages, which is fine. The menu and the panel each have their own copy. |
| App list editor | `AppListSection` | `SettingsView.swift:222` | PIP's prefix list doesn't reuse it. |
| Shortcut recorder | `ShortcutRecorder` | `Core/ShortcutRecorder.swift` | OK. The places it's used are fragmented (Overview, Keys, Switcher, Automation). |
| Menu item factory | **5 variants** | see §3.3 | Needs one style (icon or no icon, title case, ellipsis rules). |
| "Advanced" disclosure convention | **Missing** | Only DDC per-code `DisclosureGroup`s and Color's RGB disclosure | Needed to hide expert settings (DDC timing, raw VCP, framing, switchover, min HW, XDR method, Resolution filters and width limits). |

---

## 5. Recommendations (handoff)

- **Slider fix first** (§1.3). Forward `DisplayRuntime` changes, make controller state observable, add one `SettingSlider` (drag-local value, editable value field with unit, reset to default, help, throttled commit), and give `MenuSliderItem` a value label and live updates.
- **Fold duplicates** (§2.4) into one owner each.
- **Regroup the Displays sidebar** by user task, not by implementation team. A possible grouping: Displays (overview + per-display identity) / Brightness & Color / Resolution & Arrangement / Monitor (DDC basic) / Keyboard & Shortcuts (all shortcuts in one grouped list) / Virtual & PIP / Automation / Safety & Diagnostics. Put DDC internals, raw VCP, timing, switchover, min HW, XDR method, Resolution filters and width limits, and protection field toggles behind "Advanced…" disclosures.
- **Turn Display Features into fewer, user-facing switches.** Hide the four brightness methods behind "Brightness control", hide OSD broadcast and HDR virtual modes, and keep the sidebar stable.
- **Menu:** one item factory, consistent icon policy, one header style, slider rows with a visible label and value, no sliders in submenus, and a shorter default (move Identify, Redetect, Panel and Arrange behind one "Display Tools ▸", or into the panel).

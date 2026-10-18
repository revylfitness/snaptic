# Review r2: feature parity and product (PLAN.md r2)

Counts: **1 Blocker, 6 Major, 12 Minor.**

## 1. Round-1 findings: are they resolved?

| r1 | Status | Where |
|---|---|---|
| B1 | Resolved with defects (Major 2, 3; Minor 6, 7) | §2.3, §2.5, §2.10, C10, §5.3 |
| B2 | **Partly resolved.** Settings side mapped and named placements landed; the 0.2 *menu* is mapped only for the default menu, and the test checks data, not reachability (Blocker 1, Major 1) | §4.3, §4.8, §5.2 |
| M1 | Resolved | §1.1, §2.14, §4.4 #16 |
| M2 | Resolved on paper; default can still be invisible (Major 5) | N11, C11, §5.2 |
| M3 | Resolved; wording conflict (Minor 8) | §5.2, §5.3 |
| M4 | Resolved | §5.3, §5.4, HW-15 |
| M5 | Resolved; idle menu toggle misleads (Minor 9) | §2.14 |
| M6 | Resolved | §4.3, §4.4 #4 |
| M7 | Resolved | N5, §4.3, §2.12 |
| m1–m5, m7–m9, m11–m14 | Resolved | §1.2, §1.3, §2.5, §4.1, §4.3, §5.1–5.5 |
| m6 | Model only; no UI sets a cap (Minor 6) | §2.3, §2.5 |
| m10 trigger rows | Resolved | §5.3 |
| Extras | Resolved | §1.1, §4.6, §5.2 |

## 2. Blocker

### B1. The 0.2 menu's opt-in items have no 0.3 home, and "Show in the menu" for custom actions stops doing anything (§4.8 "0.2 menu", §5.2, §4.3 Customize Displays Menu)
The §4.8 menu table covers only the default menu ([UA] §3.2). Of the 0.2 registry's ~45 `DisplayMenuItemDescriptor`s, these have no §5.2 location and no §4.8 row:
- **Per display:** Rotation, HDR, Underscan, Smart HiDPI, Extra brightness (XDR), Color adjustments, Color profile, Apple display preset, Auto-brightness, Menu-bar strip, Picture in Picture, Custom DDC controls (only sliders mapped), DDC Standby and connect header switches.
- **Tools:** Layouts, Apply matching layout, Protect Arrangement, Match UI Size…, Disconnect All But Main, Virtual Screens, Picture in Picture, Night Shift, Brightness sync, custom actions with "Show in the menu".

§5.2 excludes only color toggles and the brightness method. Customize Displays Menu would offer visibility for items with nowhere to render, and Automations › "Show in menu" becomes a setting with no effect.

**Fix.**
1. Extend the §4.8 menu table to every 0.2 `DisplayMenuItemID`, each with a 0.3 location or **X** and a reason.
2. One-level homes:
   - **Display submenu:** inline toggles for HDR, Extra Brightness, Sharper Text (Smart HiDPI) and Suspend Color Adjustments. Rotation as 4 inline checkable items under a "Rotation" header, or **X** → Settings.
   - **Displays section** (feature on and Visible in C): "Saved Layouts ›" (layouts, Apply Matching Layout, Protect Arrangement ✓), "Virtual Displays ›" (Connected toggles), "Picture in Picture ›" (saved PIPs Start/Stop, Stop All), "Actions ›" (custom actions with Show in menu).
   - **Display Tools ›:** add Disconnect All But Main, Match Text Size…, Brightness Sync ✓ and Night Shift ✓.
3. Add a Kit test that every 0.2 `DisplayMenuItemID` raw value appears in `ControlMap.menuItems` or `ControlMap.removedMenuItems` (with a reason).

## 3. Major

### M1. `ControlMapTests` can't prove reachability (§4.8, §6.5)
- It walks `Codable` key paths, but the Switcher `Config` lives in the app target (`Switcher/Settings.swift`), so a Kit test can't see it.
- Actions aren't key paths (Undo/Redo, Quick Changes, Read Capabilities, XDR Test, Save Current State as Protected, "Ask Again for Everything", ~35 shortcut actions).
- Menu ids aren't checked (B1); an entry id doesn't prove a control renders.

**Fix.** Kit tables checked against 0.2 lists stored as data: `configPaths` (with Switcher key names mirrored in Kit, plus an app test comparing `Config()`'s encoded keys), `actions` (every 0.2 action id and button) → entry/menu/K, and `menuItems` (B1). Add a debug assertion that every entry's anchor renders; gate the step-3 exit on it.

### M2. `untilIdle` ends during single-threaded work, and disk-only work is invisible to it (§2.3, §2.5, §2.8 CPUSampler, HW-23)
"CPU < 15%" is the system-wide share (`HOST_CPU_LOAD_INFO`). On an 8–12-core Mac one saturated core reads 8–12%: linking, a test runner, `xz`, a Python script, an agent process. With quiet network the session ends mid-task. Finder copies to external disks and archive extraction use little CPU and no network.

**Fix.**
- Measure **core-equivalents** (or the busiest core via `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`); quiet < 0.5 core (`cpuBelowCores: Double = 0.5`).
- Exclude `lo0`; don't double-count `utun*` over the physical interface.
- Add a TCC-free disk signal (`IOBlockStorageDriver` Statistics deltas, quiet < 1 MB/s).
- HW-23: single-threaded build phase on 10 cores; 20 GB copy to an external SSD.

### M3. `awake hold` (default `--parent`) binds to a throwaway shell in the common runners (§2.10, README recipe)
`make` recipe lines, `npm run` steps, CI step runners and agent tool calls run each command in a fresh `sh -c` that exits right after `snaptic awake hold`. The session ends `.processExited` within milliseconds while the user believes the Mac is held: the named journey fails.

**Fix.**
- `hold` replies "Holding while process <pid> runs (at most 12 h)"; if that process exits within 2 s, toast "Awake stopped: the process it was holding for already ended."
- README recipes: `make` → `snaptic awake hold --pid $$` in one recipe line, or `.ONESHELL`. npm → `--pid $PPID`. Agents and long sessions → `snaptic awake start 2h`. Shells → plain `hold`.
- `awake status --json` adds `"pid"` (not a name; N1/security M6 hold).

### M4. Mid-session "Keep Display On" is missing from the compact section and the Settings status row (§5.4, §5.2 mockup, §4.3 Awake status row)
Only the Awake item has "✓ Keep Display On" (§5.3). For In Snaptic Menu users the mid-session display toggle is reachable only by an unbound hotkey; the status row has only Extend ▾ / Turn Off, and whether the page toggle affects a running session is unstated. This is core Amphetamine behavior ([AP] 1.3).

**Fix.** Add "✓ Keep Display On" to §5.4 (always present); add it to the status row pull-down ("Options ▾") while active; state that the page toggle applies to a running session using default options.

### M5. The default presence can still hide a running session, and it reshuffles items (§5.2 truth table, N11, C11, §5.5)
`.ownIconWhenActive` creates the item at session start; on notched or crowded bars a new item lands far left, behind the notch or in 27's overflow, which §5.5 admits is undetectable. The active Snaptic glyph shows only when "no Awake icon is visible" (read as: item absent), so in the default config on laptops the session can be invisible.

Also, where the Snaptic item exists only for the idle compact section, each session swaps it for the Awake item.

**Fix.**
- `sharedActiveGlyph = awakeGoverning && showShared`, regardless of the Awake item.
- A session never removes an item that was due at rest.
- HW check: notched MacBook with 20 items; 27 overflow.

### M6. The per-display header switch maps to a menu element that doesn't exist (§4.8 Arrangement "Header switch" → C, §4.3 Customize Displays Menu, §5.2 device rows)
0.2 `management.powerSwitch` (None / Connect-Disconnect / DDC standby) was the per-display way to **reconnect** a display from the menu. 0.3 device rows are native items with no switch, and §5.2 doesn't say whether a disconnected display has a row; only "Connect All Displays" remains.

**Fix.** Mark the C control **X**; migrate `powerSwitch != none` to the Turn Off Display/Disconnect item Visible top-level; a disconnected display keeps a dimmed device row whose submenu offers "Connect".

## 4. Minor

1. **Overview banners** (§4.8, §4.3 root): 0.2's Resume Display Automation, Leave Safe Mode… and Restart Snaptic (helper) banners; Resume maps only to Root **Advanced**. Add root status rows and map rows.
2. **Brightness sub-page lacks a display picker** but has per-display rows (XDR maximum, sync offset); map says "Br/Root tiles". Add `PerDisplayPicker`.
3. **Map destinations missing from page specs:**
   - "Sw status row when Screen Recording is missing" isn't in the Window Switcher spec.
   - Onboarding "Hide the menu-bar icon" and "Turn on Smart HiDPI" aren't in §4.7.
   - General card "Turn On Awake…" has no target.
   - 0.2 footer items "More display features…" and "Recent Notices ▸" have no rows in the menu table.
4. **Displays Features permission rows** unmapped (Switcher's are). Map to Permissions + footer fix buttons.
5. **Trigger editor under-specified** (§4.3 TriggerEditorSheet vs §1.1/§1.4). Specify the criteria list (+/−, ≤ 8), "is / is not" (negation) and "After I turn it off: resume when the condition is next true / after N min" (`resumeAfterManualEndMinutes`, the Amphetamine re-activation parity row).
6. **No UI sets a task cap** (§1.1, §2.5, §2.14 `AwakePresetKind`), so "Add 1 Hour" never appears for UI task sessions. Add `maxSeconds` to the untilIdle preset ("At most" pop-up in the editor) and to the app-session panel, or drop the §1.1 claim.
7. **`awake preset` with an untilIdle preset is uncapped** (§2.10). This contradicts N1 ("never an unbounded session"). Apply `holdDefaultCapSeconds` as `start idle` does.
8. **Own-menu footer wording conflict.** §5.2 says own menus end with "Snaptic Settings…" + Quit. The §5.3 mockup ends with "Awake Settings…" + Quit. Say that "Awake Settings… ⌘," is the only Settings item in the Awake menu.
9. **Idle "✓ Keep Display On" misleads** (§5.3, `effectiveOptions`): task-bound kinds force `maySleep`, explicit presets ignore it. Title it "Keep Display On by Default" while idle; page help: "Download and app sessions let the display sleep unless set in Durations."
10. **Awake page over budget for upgraders** (§4.3): M1 trigger adds switch + list + Pause → 13–14 > 12. Move Pause into the section header.
11. **`.hidden` after the shortcut is unbound/fails** is missing from the §5.2 truth table: fall back to `.ownIconWhenActive` with a toast.
12. **History "Start Again"**: hide for `process` and `automatic` entries (§4.3).

## 5. Audit notes

All 49 `DisplayFeature` and 14 `SwitcherFeature` cases (`KitModules.swift`) have a switch or are always on. Every control label in `GeneralPages.swift`, `SettingsView.swift` and the 16 Displays `*Page.swift` files maps to a §4.8 row, except the items above; in-editor buttons are covered by their sheets.

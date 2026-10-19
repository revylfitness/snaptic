# Snaptic 0.3.1 plan (r1)

This release has two parts:

1. **Tabs in the Snaptic menu.** The shared menu shows a row of tabs at the top, one per module that lives in it, and only the selected module's items below.
2. **Keep awake with the lid closed.** This is an opt-in Awake mode that keeps a MacBook awake with its lid closed, including on battery without an external display. It asks for an administrator password each time you turn it on.

The owner chose both approaches on 2026-10-19:

- the tabs are a segmented control inside the native `NSMenu` (not a popover), and the menu remembers the last tab;
- lid-closed mode asks for a password each time; nothing is installed and nothing persistent is granted. The other options were a one-time helper install and a sudoers rule.

The inputs to this plan are the briefs in `docs/design/0.3.1/briefs/` (menu, awake, research). Section numbers like "0.3 §5.1" refer to `docs/design/0.3/PLAN.md`.

Ground rules carried over from 0.3:

- SnapticKit stays Foundation-only and tested on Linux, and all pure logic lives there;
- CI is the only compiler;
- `lint.sh --strict` stays green with no new ratchet rows;
- every control is in a `*Controls` table;
- every new file has a `stubs.tsv` row.

---

## Part A: Tabs in the Snaptic menu

### A1. What changes for the user

```
┌──────────────────────────────────────┐
│ [ Window Switcher | Displays | Awake ]│   tab bar: only when 2+ modules share the menu
├──────────────────────────────────────┤
│ …the selected module's items…         │   the full section, with no header (the tab names it)
├──────────────────────────────────────┤
│ More Display Features…   (when shown) │
│ Recent Notices         ›  (when any)  │
│ Snaptic Settings…               ⌘,    │
│ Quit Snaptic                    ⌘Q    │
└──────────────────────────────────────┘
```

**When the tab bar shows**
- Tabs appear only in the **shared** Snaptic item, and only when `plan.shared.count >= 2`.
- With one module in the shared menu there is no tab bar, and that module's section shows with no header (0.3 already shows a header there; drop it, because the icon names the menu).
- With none, the menu keeps today's "No Modules Are On" row.
- Own-icon menus (a module set to Own Icon) are unchanged.

**Order and labels**
- Tabs follow `plan.shared` order: Window Switcher, Displays, Awake.
- Labels are the module titles in Title Case (design-spec §4.1). If the three titles don't fit in the 272 pt control at small size, the labels fall back to short names ("Switcher", "Displays", "Awake"). That decision is made in Kit from measured widths passed in, so it can be tested.

**Awake in a tab**
- Awake's tab shows the **full** Awake rows (as in its own menu), minus "Awake Settings…" because the footer covers it.
- The compact section (0.3 §5.4) is used only when Awake is the single shared module. 0.3 used it there to keep a stacked menu short, and tabs remove that reason. Open question for review: keep compact in tabs too?

**Remembering the selection**
- The selected tab is remembered across opens and relaunches.
- If the remembered module isn't in `plan.shared` (it was turned off, moved to its own icon, or Awake's compact entry went away), the menu falls back to the first tab. The stored choice is kept, so it comes back when that module returns.

**Snaptic Settings… ⌘,**
- With tabs, it opens Settings at the selected module's page (Window Switcher, Displays or Awake).
- With no modules on, it opens General, as today.

**Unchanged**
- Recent Notices, the upgrade item, Quit and Safe Mode rows: Safe Mode rows stay above the tab bar, as the first group.

### A2. Building and switching

**The tab bar row** is a new custom-view item, `MenuTabBarRow`, in a new file `Core/MenuTabBar.swift`, which is added to the L6 exemption list next to `MenuSwitchHeader.swift`.
- Its view is a `MenuRowView` subclass hosting an `NSSegmentedControl` (`.selectOne`, `controlSize = .small`, `segmentDistribution = .fillEqually`), inset by `MenuKit.rowInset`.
- Row height is fixed at 28 pt.
- Its accessibility label is "Snaptic menu sections"; each segment carries its module title.

**`StatusMenu.build(shared)`**, when `plan.shared.count >= 2`:
1. Safe Mode group (if any).
2. Tab bar row, then a separator.
3. The selected module's section, with `header: false` and `compact: false` for Awake.
4. A separator, then the footer.

StatusMenu keeps two marker references, the tab bar item and the footer's first separator, so it knows which range of items belongs to the section.

**Switching tabs** (segmented control action) runs synchronously in the action:
1. Store the choice.
2. `menu.removeItem` for every item between the tab bar's separator and the footer separator.
3. Insert `section(newID, …)` items at that index.
4. Update `minimumWidth`.

The action runs in the menu's event-tracking mode. No timers and no `RunLoop.main.perform` (N15, L14). The removed items are never under the mouse, which is on the tab bar, so the R2C c12 slider glitch doesn't apply. The menu window resizes while open; HW-31 checks this on 14, 15, 26 and 27.

Some live state is affected by a switch:
- Awake's header refresh prunes headers whose `item.menu == nil`. A switch builds fresh items by calling `menuSection()`, so the new headers register themselves.
- Slider rows in removed items keep their Combine sinks until they are deallocated. StatusMenu drops its references to removed items, and MenuSliderRow's sinks are weak to the view.

If anything requests a rebuild while the menu is open, it still only marks the slot dirty. The tab switch builds from current state, which is fine because it is a fresh section.

**Height**
- Sections differ in height (Displays with sliders is the tallest), and the menu grows and shrinks downward from the status item.
- The menu does not try to keep a constant height: padding rows would be worse than a resize.

**Width**
- The tab bar is a view row, so a menu with tabs is always `MenuKit.width` (300 pt) wide. A single-module Switcher menu stays native width, as today.

### A3. Keyboard and VoiceOver (0.3 §5.1 C4, parity M4)

Every module section must be reachable without a mouse, as follows:

- **VoiceOver:** the segmented control is an accessibility element inside the row. VO users move to it and choose a segment with VO-Space, and its value changes announce the new section. HW-32 checks this.
- **Keyboard (native path):** each tab also has a native item, "Show Window Switcher" / "Show Displays" / "Show Awake", with key equivalents ⌘1/⌘2/⌘3.
  - These items are hidden (`isHidden = true`, `allowsKeyEquivalentWhenHidden = true`), so they take no space.
  - Pressing ⌘2 in the open menu switches the tab and keeps the menu open, if AppKit lets a hidden item's action run without ending tracking. If the menu closes (HW-33 decides), the next open shows the chosen tab, and the README says "⌘1–⌘3 choose a tab".
- **Arrow keys:** the tab row highlights like other view rows (`willHighlight`). Left and Right arrows on a highlighted tab row are not promised; NSMenu tracking owns them.
- **Type-select and key equivalents** reach only the visible tab, plus the footer (⌘, and ⌘Q). Displays' and Awake's own key equivalents work only on their tab or in their own icon's menu, and that is documented. Global shortcuts are unaffected.

### A4. Where the logic lives (Kit)

`SnapticKit/MenuLayout.swift` gains pure helpers:

- `MenuTabs.tabs(plan:) -> [ModuleID]`: `plan.shared` when its count is 2 or more, otherwise `[]`.
- `MenuTabs.selected(stored: String?, tabs: [ModuleID]) -> ModuleID?`: the stored id if it is in `tabs`, otherwise `tabs.first`. It decodes leniently: an unknown string counts as nil.
- `MenuTabs.labels(titles:short:widths:available:) -> [String]`: full titles when they fit, otherwise short names.
- `MenuTabs.settingsPage(selected:noModules:) -> String?`.

Tests:
- truth tables in `MenuLayoutTests`;
- one more fuzz invariant on the existing 5,000-case harness: "selected ∈ tabs whenever tabs is non-empty", and "tabs is empty or has at least 2 entries".

### A5. Persistence

The selection is a plain `UserDefaults.standard` string under `snapticMenuTab`, following the precedent of `settingsLastRoute`.
- It is not in `ModulesConfig`, so writing it doesn't trigger `scheduleApply` and a re-plan.
- It is not in backups and not in the ControlRegistry key cross-check.
- General › Reset doesn't clear it (like the last Settings route). Menu Bar › Restore Defaults does clear it.
- Reads are lenient.

### A6. Controls, lint, docs

**Controls**
- `StatusMenuControls` gains:
  - `menu.snaptic.tabs`, a new `ControlKind.menuTabBar`. `SettingsIndex.requiresSearch` returns false for it.
  - `menu.snaptic.showTab`, a `.menuItem` with `when: [.perItem("module")]`.
- `menu.snaptic.sectionHeader` stays, for own-icon menus and single-module menus where it still applies. If it ends up unused, it is removed with a `ControlRemovals` reason.

**Lint**
- L6 exemption gains `MenuTabBar.swift`.
- L13 and L14 already cover `Core/Menu*.swift`.

**Docs**
- README "Menu Bar" and "In the menu bar" sections; design-spec §3.3 (new sketch); 0.3 PLAN §5.2's row budget is restated for 0.3.1 as "the tallest single tab ≤ 24 lines in the default setup" (HW-15 updated).
- `MenuBarPage` summary line: "When two or more modules share the Snaptic menu, it shows a tab for each."

---

## Part B: Keep awake with the lid closed

### B1. What the user sees

**Settings › Awake, new group "Lid Closed"** (MacBooks only; the group is hidden when the Mac has no lid, `lidWillSleep == nil` at module start):

- **Toggle "Allow Keeping Awake with the Lid Closed"** (off by default). Footer: "Your MacBook keeps running when you close the lid, even on battery. You'll enter your administrator password each time you turn this on, because macOS only allows it with administrator rights. While it's on, macOS won't sleep for low battery or heat, so Snaptic turns it off at 10% battery or when your Mac gets hot. Keep your Mac on a hard surface with air around it, not in a bag."
- **Stepper "Turn Off After"**, 1–24 hours, default 8: a hard cap on lid-closed time per session, separate from the session's own length.
- **Battery floor** (picker): "Turn off at 10% / 20% / 30% battery", default 20%. It is never below 10%; that is the root side's fixed floor.
- If Snaptic's bundle is writable by the user, a warning row says: "Apps running as you can change Snaptic, and Snaptic will ask for your administrator password. Install Snaptic with `INSTALL=1 ./scripts/build-app.sh` or move it to Applications as an administrator." This warns but does not refuse (open question: refuse instead?).

**The Awake menu**, when allowed and the Mac has a lid:
- **"Keep Awake with Lid Closed…"**, a native item. The ellipsis means a password prompt follows.
  - If a session that you started in the menu or Settings is running, it adds lid-closed mode to that session.
  - Otherwise it starts the default session (preset) with lid-closed mode.
- While on, the item becomes **"Allow Sleep When Lid Closes"**. That turns lid-closed mode off and keeps the session going; it needs no password.
- The header detail line replaces "Closing the lid will put your Mac to sleep." with "Stays awake with the lid closed until 6:40 PM." (the earliest of the session end and the cap).
- The lid warning is computed from the actual `lidWillSleep` value, not just from the lid existing (brief §4 bug). It also refreshes on `$lidWillSleep` and on screen changes.

**Custom… panel:** a checkbox "Also keep awake with the lid closed (asks for your password)", shown when allowed.

**The password prompt** is macOS's own authorization dialog, through `/usr/bin/osascript`, with this prompt text:

> Snaptic wants to keep your Mac awake with the lid closed. Sleep turns back on when the session ends, when Snaptic quits, at <floor>% battery, or if your Mac gets hot.

Touch ID may be offered (osascript is Apple-signed); HW-35 checks this. Cancel leaves the session running without lid-closed mode and shows no error toast.

**Status everywhere**
- The Awake status row in Settings, the menu header, the indicator tooltip ("…, also with the lid closed"), `snaptic awake status` (new `lidClosed` field, true/false), and History (new lossy `lidClosed` flag on entries).

### B2. Who can turn it on: the lid gate (N10 extended as "N20")

Lid-closed mode turns on only through a **direct user action in Snaptic's UI in this process**:
- the menu item;
- the Custom… panel checkbox (menu or Settings);
- the Awake page's "Keep Awake with Lid Closed…" button in the status section, shown when allowed.

The rules:

- **Never** from the CLI, rules, holds, start-at-launch, restored or resumed sessions, History "Start Again", hotkeys (including preset slots), backups or presets.
- It is not part of `AwakeSessionOptions`, presets or `defaultOptions`, so no persisted path can carry it.
- It is a **runtime-only** property of the running manual session: `AwakeSession.lidClosed`, left out of CodingKeys exactly like `overrideGuards`, and reset in `init(from:)` and `sanitized(now:)`.
- Only `SessionController` may set it; lint L16 is extended to `lidClosed`.

What ends lid-closed mode:
- any end of its session;
- replacement by another session;
- a trigger or hold takeover (only possible after the manual session ends anyway);
- module stop, Safe Mode, or the feature turned off;
- a kill switch (`Awake.disable.lidClosed`, from N14);
- a guard end;
- "Allow Sleep When Lid Closes".

CLI restrictions:
- **`snaptic awake extend` is refused** while lid-closed mode is on, with the new refusal `.lidClosedSession`, exit 4, and the text "Can't extend a lid-closed session from the command line. Use Snaptic's menu."
- `awake stop` still works: anything may turn sleep back *on*.

A new Kit type, `AwakeLidGate` (pure, not Codable), holds the truth table: `(source, event) -> allowed`. It mirrors `AwakeActivityGate`, with Linux tests.

**Starting with guards in play**
- Lid-closed mode refuses to start if:
  - the battery is discharging and below `floor + 5`;
  - Low Power Mode is on;
  - the thermal state is `serious` or worse;
  - the session is in "Start Anyway" (`overrideGuards`).
- The refusal is a toast with the reason. Lid-closed mode never offers Start Anyway.

### B3. Mechanism

Components:

- **App (user):** `Awake/Core/LidClosedController.swift` owns the lifecycle.
- **Spawning:** a new `HelperKind.adminScript` in `HelperSpawner.swift`.
- **Kit:** `SnapticKit/LidWatchdog.swift` (script text, argument validation and state parsing); `AwakeLidGate.swift`; and presentation in `AwakePresentation.swift`.
- **Root side:** a `/bin/sh` script started by `do shell script … with administrator privileges`. It is short, fixed text with no interpolation of anything except validated arguments.

**Start sequence** (LidClosedController.turnOn, on the main actor; the osascript wait runs off-main):
1. **Preflight.** Check the gate, the feature, the guards (B2), and that the Mac has a lid. Read `SleepDisabled`:
   - read both the IORegistry `IOPMrootDomain` `SleepDisabled` property (kernel truth) and the preference (`OtherAssertionsReader`'s existing CFPreferences read);
   - if either is already on, Snaptic doesn't touch it and says "Sleep is already turned off for this Mac by another app or command, so your Mac stays awake with the lid closed." The session runs without lid-closed mode.
2. **Journal before any change.** Write `~/Library/Application Support/Snaptic/awake/lid.json` (0600, in the existing 0700 directory) with `{token, bootSessionUUID, startedAt (wall + continuous), pid, capSeconds, floor}`. `token` is 128 random bits as 32 lowercase hex characters.
3. **Beacon directory.** Create `<DARWIN_USER_TEMP_DIR>/snaptic-lid/` (0700), where `confstr(_CS_DARWIN_USER_TEMP_DIR)` is per user and outside the home folder.
   - Check that it is a real directory (not a symlink), owned by our uid and mode 0700. If any check fails, the start is refused.
   - Create `beat-<token>` (an empty regular file) and remove any old `stop-*` files.
4. **Spawn.** `HelperSpawner.spawnAdminScript(source: LidWatchdog.appleScript(args))` runs `/usr/bin/osascript -e <script>`.
   - It uses a fixed absolute path, argv only (no shell), not disclaimed (open question: does disclaiming change the dialog?), and its own process group.
   - The app waits up to 120 s for osascript to exit, on a background queue; exit 0 means launched. A nonzero exit (including −128, "User canceled.") means "not turned on". After 120 s the app SIGTERMs osascript.
5. **Verify.** Poll the IORegistry `SleepDisabled` every 0.5 s for up to 10 s.
   - On: mark `runtime.lidClosed = .on(until:)`, start the heartbeat (B3.2), and post VoiceOver "Lid closed mode on."
   - Not on within 10 s: write the stop file, show "Couldn't turn on lid-closed mode.", and log `awake.lid.failed.verify`.
6. **Re-check after 5 s.** If `SleepDisabled` flipped back to 0 (another tool resets it; awake-parity.md:124), end lid-closed mode with "Another app turned sleep back on." Insomnia does the same.

#### B3.1 The root watchdog (fixed text in `LidWatchdog.script`)

It is run as `/usr/bin/nohup /bin/sh -c "$SCRIPT" snaptic-lid <uid> <pid> <token> <capSeconds> <floor> <dir> </dev/null >/dev/null 2>&1 &`. The arguments are positional, so the script body never contains them.

```sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
umask 077; trap '' HUP
UID_="$1"; PID_="$2"; TOK="$3"; CAP="$4"; FLOOR="$5"; DIR="$6"
# Argument re-validation (defense in depth; the app validates too)
case "$UID_$PID_$CAP$FLOOR" in *[!0-9]*|'') exit 64;; esac
case "$TOK" in *[!0-9a-f]*|'') exit 64;; esac; [ ${#TOK} -eq 32 ] || exit 64
case "$DIR" in /private/var/folders/*|/var/folders/*) ;; *) exit 64;; esac
case "$DIR" in *..*|*[!A-Za-z0-9_/+.-]*) exit 64;; esac
[ "$FLOOR" -ge 10 ] && [ "$FLOOR" -le 50 ] || exit 64
[ "$CAP" -ge 60 ] && [ "$CAP" -le 86400 ] || exit 64

sd() { pmset -g | awk '$1=="SleepDisabled"{print $2; f=1} END{if(!f) print 0}'; }
owned() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(stat -f %u "$1")" = "$UID_" ]; }
restore() { [ "$(sd)" = 1 ] && pmset -a disablesleep 0; exit 0; }

[ "$(sd)" = 0 ] || exit 3                     # someone else holds it: never take ownership
trap restore TERM INT
pmset -a disablesleep 1
START=$(date +%s); LIDWAS=no; LOWBAT=0
while :; do
  sleep 5
  NOW=$(date +%s)
  [ $((NOW-START)) -ge "$CAP" ] && restore                           # hard cap
  kill -0 "$PID_" 2>/dev/null || restore                               # Snaptic gone
  owned "$DIR/stop-$TOK" && restore                                    # asked to stop
  owned "$DIR/beat-$TOK" || restore                                    # beacon gone
  [ $((NOW-$(stat -f %m "$DIR/beat-$TOK"))) -le 20 ] || restore        # Snaptic hung
  [ "$(sd)" = 1 ] || exit 0                                            # someone reset it: not ours anymore
  B=$(pmset -g batt)                                                   # battery floor, root-side
  case "$B" in *discharging*) P=$(printf '%s' "$B" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)%.*/\1/p' | head -1)
      if [ -z "$P" ]; then LOWBAT=$((LOWBAT+1)); [ $LOWBAT -ge 2 ] && restore
      else LOWBAT=0; [ "$P" -le "$FLOOR" ] && restore; fi;; esac
  T=$(notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null | awk '{print $2}')
  [ -n "$T" ] && [ "$T" -ge 2 ] && restore                             # heavy or worse
  L=$(ioreg -r -k AppleClamshellState -d 1 | awk '/AppleClamshellState/{print $NF; exit}')
  [ "$L" = Yes ] && [ "$LIDWAS" = no ] && pmset displaysleepnow       # dark panel in a closed lid
  LIDWAS=$( [ "$L" = Yes ] && echo yes || echo no )
done
```

Properties to review:

- **What root touches:**
  - It writes only through `pmset -a disablesleep 0|1` and `pmset displaysleepnow`.
  - It never writes, deletes, follows symlinks in, or parses the contents of user-controlled files. It only `stat`s them, checking owner, type and mtime.
  - The directory is per-user (`/var/folders/…`), and a symlinked beacon fails `owned`.
- **What a same-user attacker can do** (the Snaptic user, or any program running as them):
  - Create `stop-<tok>` or delete `beat-<tok>`, which **turns sleep on**. That is safe.
  - Keep touching `beat-<tok>` while Snaptic is hung. That keeps lid-closed mode alive, bounded by the cap, the root battery floor and the heat cutoff. That is acceptable.
  - Learn the token by reading `lid.json`. That only allows the same two actions.
  - They cannot start lid-closed mode without the user typing a password into a dialog the user asked for.
- **PID reuse after a crash:** `kill -0` could see a new process, but the beacon then goes stale within 20 s, so the watchdog restores.
- **The watchdog can't be killed by the user**: it runs as root. That's fine, because every stop path is a file the user can create.
- **Restore semantics:** it restores to 0 only if the value is still 1 and it set it. Starting from 0 is a precondition (`exit 3`). If someone else reset the value to 0 mid-session, the watchdog exits without touching it.
- **Heat:** `notifyutil` thermal pressure 2 ("heavy") or worse. Apple silicon and Intel both publish this key (HW-36 verifies). If the key is unreadable, the app-side heat guard still ends the session, through the stop file.
- **Battery:**
  - The floor is root-side (≥10%), because `SleepDisabled` blocks low-battery emergency sleep (research §1).
  - The parse fails safe: two unreadable reads restore.
  - On some Apple silicon Macs the kernel may still shut down at hardware cutoff (research §1). The floor makes that unreachable in practice.
- **Display:** `displaysleepnow` on lid close keeps the panel from staying lit inside a closed lid (research §1, Amphetamine 5.3). Display assertions don't stop `displaysleepnow`; HW-37 verifies.

#### B3.2 App-side lifecycle

- **Heartbeat:** while on, the app sets the beacon's mtime every 5 s from the main queue (`DispatchSourceTimer` on main, wrapped with `assumeIsolated`; not a `scheduledTimer`, per L14). If the main thread hangs for 20 s, the watchdog restores sleep (DisplayGuard's hang model).
- **Turning off** (any end path: session end, Allow Sleep, guard, module stop, Safe Mode, quit):
  - Create `stop-<token>` and stop the heartbeat.
  - Poll `SleepDisabled` for up to 15 s. Off means clear the journal. Still on means a notice: "Sleep is still turned off. Turn Sleep Back On…" (B3.3).
- **Quit:** `applicationWillTerminate` writes the stop file synchronously.
  - `EmergencyActions` (SIGTERM, SIGINT, SIGHUP) gets a "write stop file" action. It is async-signal-safe only in the sense that the dispatch signal source runs on the main queue; that is the existing path.
  - If none of these run (crash, `kill -9`), `kill -0` and the beacon cover it within 5–20 s.
- **Sleep/wake:** while lid-closed mode is on, the Mac doesn't sleep. If it does anyway (a forced sleep path we don't know about), `.didWake` re-reads `SleepDisabled`, keeps the mode if it is still on, and ends it otherwise. `endOnSystemSleep` doesn't apply, since sleep is blocked.
- **The lid-closed cap** is enforced by both sides. The app ends lid-closed mode at the cap, keeps the session, and shows the notice "Lid-closed mode turned off after 8 hours. Awake is still on, so your Mac will sleep when you close the lid." The watchdog's cap is the same value plus 60 s.

#### B3.3 Leftovers and recovery

- **At Awake start** (before restore), if `lid.json` exists:
  - **Other boot** (`bootSessionUUID` differs) and `SleepDisabled == 1`: the watchdog died with the old boot (a restart or power loss), and `SleepDisabled` survives a reboot. This is a leftover.
  - **Same boot:** an old watchdog may still be alive (the app crashed and relaunched within 20 s). Wait 30 s, then re-check. Still 1 and the journal's PID is not us: a leftover.
  - **`SleepDisabled == 0`:** clear the journal. Nothing to do.
- **A leftover** shows a persistent row in the Awake status section and the menu: "Sleep is still turned off from an earlier lid-closed session." With:
  - **"Turn Sleep Back On…"**: password prompt, then `/usr/bin/pmset -a disablesleep 0`, then verify, then clear the journal.
  - **"Leave It Off"**: clears the journal and stops showing the row. It is then reported as "another app or command", as today.
- The leftover row also shows in Awake › Advanced › Other Apps, instead of the generic "another app or command" text.
- **Journal-less `SleepDisabled == 1`** keeps today's behavior: it's someone else's, and Snaptic reports it but never changes it.

### B4. Ending, guards and interplay

- **Guards** keep ending the session as today, which also ends lid-closed mode. One change: while lid-closed mode is on, the app ends **lid-closed mode** (not the session) at `floor` and at `serious` heat, a step earlier than the session's own guards. The notice says why.
- **Adapter disconnect, Low Power Mode, user switch, lock:** unchanged session rules, which end lid-closed mode when they end the session. One more rule: lid-closed mode also ends when **Low Power Mode turns on** (a battery signal).
- **Fast user switching or the session going off console:** lid-closed mode keeps running if the session does (userSwitchEnd decides).
- **Pointer movement (`nudge`):** never with the lid closed. ActivityPolicy already requires an unlocked console session; the lid adds nothing.
- **Drive Alive:** unaffected.

### B5. Kit additions (all Linux-tested)

- **`LidWatchdog`:**
  - `script` (constant);
  - `Arguments` with `validated(uid:pid:token:cap:floor:dir:) -> Arguments?`, which checks the same charset and range rules as the script;
  - `appleScript(args:prompt:)`: AppleScript source with `do shell script "<quoted>" with prompt "<quoted>" with administrator privileges`, where quoting escapes `\` and `"` and the inputs are already restricted;
  - `parseSleepDisabled(pmsetOutput:)`, kept for tests and parity;
  - `promptText(floor:)`.
  - Tests:
    - golden script text;
    - a fuzz test that no argument outside the allowed set validates;
    - quoting round-trips;
    - `appleScript` output contains each argument exactly once, only after `sh -c "$SCRIPT"`.
- **`AwakeLidGate`**: the truth table and an exhaustive test.
- **`AwakeLidPolicy`**: start refusals (B2), turning off ahead of the guards (B4), the cap clock (continuous), and the leftover classification (B3.3) as a pure function of `(journal?, bootUUID, sleepDisabled, now)`.
- **Config:**
  - `AwakeLidConfig {allowed=false, capHours=8 (1…24), floor=20 (10/20/30)}` inside `AwakeConfig`;
  - lossy decoding;
  - `monotonic(over:)` for import, so an import can only make it stricter: allowed true→false only, cap down, floor up;
  - stripped from export like `pointerNudge`: `allowed` is never exported or imported.
- **Feature:** `AwakeFeature.lidClosed`, level `.optIn` (needs `allowed`), with a kill switch `Awake.disable.lidClosed`.
- **Text and logging:**
  - new `AwakeEndReason` values are not needed, because lid-closed mode isn't a session;
  - new `AwakeLogEvent` cases: `lidOn`, `lidOff(reason)`, `lidFailed(stage)` and `lidLeftover`, with fixed text and no payload;
  - `AwakeStatusFacts.lidClosed`;
  - presentation strings;
  - `AwakeRefusal.lidClosedSession`.

### B6. Lint and security rules

- **Rule 12 (spawning):**
  - The regex gains `NSAppleScript|NSUserScriptTask|OSAScript`, which closes the gap the brief found. AppleScript is allowed only through `HelperSpawner.spawnAdminScript`.
  - `spawnAdminScript` accepts only the `/usr/bin/osascript` path and an `-e` source produced by `LidWatchdog.appleScript` or `LidWatchdog.restoreScript`. Its argument type is a Kit `AdminScript` value that only those two functions can create, with a `fileprivate` init in the same Kit file.
- **New rule L17:** the literals `with administrator privileges`, `/usr/bin/pmset` and `disablesleep` may appear only in `SnapticKit/LidWatchdog.swift`. L4 (`"pmset"`, `"sudo"`) stays as is: `sudo` is never used.
- **No sudoers, no LaunchDaemon, no files outside the user's own folders:** nothing persistent at the system level except the `SleepDisabled` value itself while a session runs. This is stated in the README and the site.
- **Threat model** (new README section "Lid-closed mode and your password"):
  - what root does;
  - what a program running as you can and can't do (B3.1);
  - the leftover case after a power loss;
  - EDR products may flag "osascript with administrator privileges" from an ad-hoc-signed parent (research §4);
  - a user-writable bundle risk (B1).

### B7. Docs and copy to change

Every line in brief-awake §8's table is updated. In summary:

- **README:** l.19, 155, 252, 254–258 ("Why not…" becomes "Keeping awake with the lid closed"), 273, 275, 610–611, 639, 652, 686, 707 and 718.
  - The "never runs a program" claim becomes "Awake runs one program, only when you turn on lid-closed mode: macOS's own password prompt (`osascript`), which starts `pmset`".
- **site/index.html:** l.401, 600 and 637. The lid card becomes: "Lid closed? Turn on lid-closed mode with your password. It stops at low battery or heat."
- **Code comments:** OtherAssertionsReader:9, OtherAssertions:6, OtherAssertionsSection:17, AwakePresentation:319 and 621.
- **THIRD_PARTY_NOTICES:** Insomnia row. Add "re-read SleepDisabled 5 s after setting it; recovery journal before disabling sleep; displaysleepnow on lid close (Amphetamine)". These are ideas, not code, so no license text changes.
- **Release notes:** `docs/design/0.3.1/RELEASE-NOTES-0.3.1.md`.

---

## Part C: Hardware checks (added to PLAN §6.7's list; results decide Beta labels)

| ID | Check |
|---|---|
| HW-31 | Switching tabs in an open menu resizes it correctly on 14, 15, 26 and 27; no flicker, and the highlight is on the right row afterwards |
| HW-32 | VoiceOver reaches the tab segments and announces the change |
| HW-33 | Hidden ⌘1–⌘3 items fire in an open menu: does tracking end? |
| HW-34 | Sliders and switch headers in a newly shown tab work without reopening |
| HW-35 | osascript admin prompt from an ad-hoc hardened-runtime Snaptic: dialog text, Touch ID, Cancel exit code, no Automation consent |
| HW-36 | `notifyutil -g com.apple.system.thermalpressurelevel` and `pmset -g batt` output on Apple silicon and Intel, 14/15/26/27 |
| HW-37 | Lid close on battery with no external display: Mac stays awake, the panel goes dark (`displaysleepnow`), Apple menu Sleep greyed |
| HW-38 | The nohup'd watchdog survives osascript's exit; quit, crash (`kill -9`), hang (SIGSTOP Snaptic for 30 s), stop file and cap each restore sleep, verified with `pmset -g` |
| HW-39 | Reboot while on: `SleepDisabled` persists; Snaptic shows the leftover row; Turn Sleep Back On works |
| HW-40 | The battery floor triggers the restore with Snaptic SIGSTOPped (root-side floor) |

## Part D: Teams and order

1. **Step 0 (lead):** this plan's final revision, file stubs and `stubs.tsv` rows, the Kit type signatures, and the lint rule changes. Commit to `feature/v031`.
2. **Step 1, in parallel:**
   - **T-menu:** A1–A6, covering MenuTabBar, StatusMenu, MenuLayout helpers and tests, controls, and docs.
   - **T-lid-kit:** B5 (LidWatchdog, AwakeLidGate, AwakeLidPolicy, config and feature, presentation, log), with tests.
   - **T-lid-app:** B1–B4 app side (LidClosedController, HelperSpawner.adminScript, SessionController integration, UI rows and pages, OtherAssertions changes, recovery, diagnostics). This depends on T-lid-kit's signatures from Step 0.
   - **T-docs:** B6 threat model, B7 copy, release notes and site.
3. **Step 2:** merge, CI, and `lint --strict`. Then at least 4 adversarial review rounds on the code (security, Awake correctness, menu UX/accessibility, code and consistency), each followed by fixes.
4. Version 0.3.1 in Info.plist. Open a PR into main for the owner. No tags.

## Open questions for review

1. In tabs, should Awake show the full rows (proposed) or the compact section?
2. A user-writable bundle: warn (proposed) or refuse lid-closed mode?
3. Should osascript be disclaimed? What does the auth dialog name as the requester in each case?
4. Is the cap default of 8 hours right, and the default floor of 20%?
5. Is `nohup … &` enough, or should the watchdog be a `launchctl submit` job so launchd owns it? (`submit` is deprecated, and `bootstrap system` would need a plist file on disk.)
6. Should "Keep Awake with Lid Closed…" start the default preset, or the Custom… panel with the checkbox ticked?
7. Hidden ⌘1–⌘3 items: are they enough as the keyboard path for tabs?

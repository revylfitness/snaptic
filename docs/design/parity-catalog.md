# BetterDisplay / BetterDisplay Pro — Feature Catalog (parity target)

Compiled 2026-10-17 from public docs only. Reference version: **BetterDisplay 5.1.1** (released 06 Oct 2026). No code or assets were copied; this is a behavioral spec for a clean-room, MIT-licensed reimplementation.

---

## 0. How to read this

- **Tier**: `Free` = usable after the 14-day trial without a license; `Pro` = needs a license after the trial; `Mixed` = basic part free, advanced part Pro. Free use is limited to **non-business users** by BetterDisplay's license terms (businesses must buy a license even to use free features). Our clone has no tiers, but the split shows how the original prioritizes features.
- **HW** = hardware/connection scope. **AS** = Apple silicon, **Intel** = Intel Macs.
- **[Conflict]** = the current Guide, the legacy wiki, the homepage, or the CLI help disagree. **[Unclear]** = public docs don't say.
- The GitHub wiki now marks every page as *legacy, no longer maintained*. The current docs are the **BetterDisplay Guide** at betterdisplay.pro/guide (5.1.1, updated late Sep 2026). Where they disagree, the Guide is treated as the authority.

### Platform / version matrix

| BetterDisplay | macOS | Notes |
|---|---|---|
| 5.x (5.1.1) | macOS 26 Tahoe **26.3+**, macOS 27 "Golden Gate" | AS and Intel. Intel support for Tahoe was dropped in early 5.0 pre-releases and restored in 5.0.2. Liquid Glass UI. |
| 4.3.7 | Ventura 13.2+ / Sonoma / Sequoia (also Tahoe, 27) | Maintenance branch for older macOS |
| 3.5.6 | Ventura 13.2+ / Sonoma / Sequoia | |
| 2.3.9 | Monterey 12.4+ / Ventura / Sonoma | |
| 1.4.15 | Mojave / Catalina / Big Sur | |

Legacy note: "Native XDR brightness upscaling" (the `BetterDisplay XDR` preset hack) stopped working with macOS 26.3 preset-management changes. v5 replaces it with "Direct brightness control and XDR upscaling."

---

## 1. Licensing facts (for our legal file)

- **BetterDisplay is NOT open source.** Its license terms (GitHub Discussion #739) call it proprietary software that is "licensed, not sold" by Kodeon Software. The terms forbid modifying, patching, re-signing, or repackaging the app, making derivative versions, and bypassing trial or licensing. The public GitHub repo `waydabber/BetterDisplay` holds only the README, releases (DMGs), issues, discussions, and the wiki. The default branch contains no source code.
- **The predecessor BetterDummy was MIT-licensed.** The repo's first commit (2021-10-24) added an MIT `LICENSE` ("Copyright (c) 2021 Istvan T."). On 2021-12-14, commit `4dde9ba` ("Move source code to the new opensource branch") removed the source and LICENSE from the main branch. The `opensource` branch still holds "BetterDummy OpenSource Edition" under MIT, last code ~v1.0.13 (Dec 2021, with a CI tweak in Feb 2022). It covered only virtual "dummy" displays for HiDPI mirroring.
- Pricing: Pro costs $21.99 / €19.99, sold through Paddle. The license is perpetual and includes at least one year of updates, including major upgrades. v5 is free for licenses bought on or after 2025-01-01. There's a 14-day full trial.
- Related open-source projects by the same developer: **MonitorControl** and **m1ddc**. The developer contributes to both, which are open source per the comparison table (check each repo's license before reusing anything). `betterdisplaycli` (github.com/waydabber/betterdisplaycli) is a companion CLI; its license wasn't checked.
- Branding: we must not use the name "BetterDisplay", its icon, or the `pro.betterdisplay.*` / `BetterDisplay://` identifiers.

---

## 2. Resolution & scaling

**2.1 Display Mode menu** — Lists every mode as width×height, a HiDPI sparkle marker, an aspect or notch tag, refresh rate, and bit depth. Selecting a row applies it immediately. Free.
- Options: filter tags (aspect/notch, refresh, bit depth, HiDPI/LoDPI; Shift/Ctrl/Opt-click to multi-select), "Show All" (adds unsafe/invalid modes), "Show Custom Scaled Resolutions", "Reset Default". Markers for current, default, native 1:1, unsafe, and invalid. A right-click shows details and favorite actions. Filter state is saved per display. Shift-select skips UI-scale matching.
- Global prefs: always show both LoDPI and HiDPI; show unsafe/invalid modes; allow mode changes on mirror targets.
- HW: AS and Intel. Modes under 720p are hidden unless "Enable lower than 720p" is on.

**2.2 Resolution slider** — Picks a logical desktop size from a filtered list and applies it on release. Free.
- Options: show as a **percentage** of the default resolution (needs ≥12 suitable modes and the native-aspect filter); **magnification mode** (reversed direction, % of UI size vs native); only native-aspect modes (default on); allow "invalid" modes; show W×H values. Snaps to favorite, current, default, and native markers (Option bypasses snapping). Keeps the current refresh rate, bit depth, and HiDPI class.
- Not shown for mirror targets or when fewer than two suitable modes exist.

**2.3 HiDPI toggle** — Switches to the nearest mode of the opposite HiDPI/LoDPI class. Free in the menu; the keyboard shortcut is Pro. CLI `hiDPI`.

**2.4 Flexible HiDPI scaling ("fully scalable desktop")** — Writes a system display override for the display model that generates many scaled HiDPI modes at the panel's native aspect ratio, so the slider scales smoothly. **Pro.**
- Options: enable per display model; custom min/max width/height range. "Enable resolutions over 8K (4K HiDPI)" raises the limit to 16K×16K (8K×8K HiDPI); the generator makes up to 15,360 px.
- HW: built-in displays and natively connected external displays (USB-C/DP/HDMI). **Not DisplayLink, Sidecar, or AirPlay**, because those use driver-managed or virtual paths; the workaround there is virtual-screen mirroring or streaming. Supports notched displays, HDR, HDCP, and high refresh rates (README).
- Limits (legacy wiki): max horizontal framebuffer is 6K (6144 px / 3072 HiDPI) on base M1/M2 and 8K (7680 px / 3840 HiDPI) on M1/M2 Pro/Max/Ultra; Intel depends on the GPU. HiDPI size can't exceed the native panel resolution (use virtual-screen mirroring for supersampling). Framebuffers over 8K can crash Catalyst apps.
- Requires: the "Edit the system configuration of this display model" master switch, then **Apply**. Applying needs privileged-helper or admin authorization (Touch ID supported in v5). After applying, a reboot or an "Activate" step is needed (Activate is AS only and briefly blanks displays). The change affects **every display with the same vendor and model IDs**.
- Caveats: needs a correct "native panel pixel resolution" (editable). A macOS Sonoma bug sometimes failed to load the custom configuration on connect or wake; the fix is the "Reinitialize external displays with flexible scaling enabled if needed" option, manual reinitialize, or reinitialize on wake/unlock. macOS 12.4+ for the original feature.

**2.5 Custom scaled resolutions** — Adds specific W×H sizes to the model override; the app requests both LoDPI and HiDPI variants. Free.
- Row status labels: invalid (skipped), duplicate, currently available as HiDPI/LoDPI, currently not available. Same Apply/admin/reboot flow as 2.4. macOS may reject a mode.

**2.6 Other model overrides** (System Configuration sheet; all Free; Apply + admin needed):
- **Native panel pixel resolution** override (only affects scaling math).
- **Default resolution** (W/H/refresh). AS requests HiDPI. Intel is approximate and has an "Aim for a HiDPI default resolution" option.
- **System display name** override (macOS-level, separate from the app's display name).
- **Display role**: Computer monitor or Television. Television disables Night Shift and True Tone, so "Night Shift for TVs" works by setting the role to Monitor.
- **Mark System Configuration As Unapplied**; **Undo**. Turning model editing off also needs an Apply.
- **Intel only: Display EDID override** (Pro) is stored as a model override and takes effect on reconnect or restart.

**2.7 Resolution favorites** — Five slots per display, saved from the Display Mode menu (right-click or Manage…). Apply from the menu, shortcuts, or CLI `favoriteMode` / `saveFavoriteMode`. Matches on size + HiDPI + refresh; shows "Unavailable" if the mode disappears. **Pro.**

**2.8 Resolution shortcuts** (Pro): increase/decrease resolution or magnification, set default, set native, set native-halved HiDPI, toggle HiDPI, toggle HDR, toggle notch, undo/redo the last mode change.

**2.9 Notch toggle** — Switches between notched and notch-free modes on notched MacBooks. This changes the desktop shape only. Free in the menu (Pro per the CLI help and the shortcut). [Conflict]

**2.10 Per-display resolution range limit** — Limits the slider and shortcuts to a min/max width/height. Free.

**2.11 Global resolution limits** — Enable modes under 720p; enable modes over 8K. Both affect virtual screens and flexible scaling. Free.

---

## 3. Virtual screens (dummy displays)

**3.1 Create virtual screen** — Creates a software display that macOS treats as a real monitor (a "dummy"). It starts disconnected; connecting it makes the desktop available.
- **Pre-configured presets — Free**: 16:9 HD/4K/5K/6K (default), 16:10, 4:3, 17:9 DCI, ultrawides (21.3:9, 21.5:9, 24:10, 32:10, 32:9), 1:1, 3:2, 5:4, and iPad ratios (4:3, 15.2:10 mini, 14.4:10 Air, 14.3:10 Pro 11").
- **Match aspect ratio of a display and associate — Pro** [Conflict: the legacy wiki/homepage list "association" as free]. Options at creation: auto-associate; configure a full-screen stream to the display; configure virtual-screen mirroring; rotation (landscape, portrait 90° with the Sidecar port down, portrait 270° with the port up). Streaming needs Screen Recording permission.
- **Custom aspect ratio — Pro** (each component 1–16384).
- HW: AS and Intel. Available modes depend on the GPU and macOS.

**3.2 Virtual screen settings** (most are Pro):
- Connect/disconnect switch (Free); name (Pro); identity fields (serial, vendor, and model hex). Changing identity makes macOS assign a new UUID.
- Aspect ratio; "Rotated orientation" (swaps W/H); **custom resolution list** (W×H rows, mixed ratios allowed); resolution step multiplier; limit resolution range (min/max W/H); **Enable HiDPI** (default on); reported diagonal size (0.1–1000 in, default 24"); >8K per screen (Free local switch).
- **HDR support** (Pro): adds 16-bit extended-luminance modes; "HDR modes only" option; Display P3 profile recommended. "HDR and high-refresh virtual screens on compatible Macs" [Unclear: which Macs].
- **Custom refresh-rate list** (Pro): 24–240 Hz, default 60 Hz. Some older Macs can't exceed 60 Hz.
- Mode list is capped at about 100 entries with HiDPI or about 200 without. The app may trim it.
- Menu presentation: show in menu, SF Symbol icon, ordering string.
- Discard: optionally also remove the generated ColorSync factory profile (needs admin).

**3.3 Associations** (all Pro to edit) — Link a virtual screen to physical display(s):
- Auto-connect while an associated display is connected (default on); inverse "connect when all associated displays are offline" (KVM use case).
- Presentation (choose one): enforce mirroring virtual→physical; or auto-start a full-screen stream to the physical display.
- "Follow display orientation" (switches landscape/portrait automatically).
- Caveats: with multiple associations, mirroring, streaming, and orientation use a single unordered target. Associations override manual connect and bulk actions. Safe Mode suppresses them. Extra mirroring auto-configuration is AS only.

**3.4 Advanced virtual screen settings** (Free):
- Restore display layout after connecting a virtual screen (AS, default on).
- Mirrored-virtual-screen sleep workaround: creates a temporary display during sleep (AS, off).
- Reconnect virtual screens after wake (helps color-space flicker).
- Reconnect the remaining screens after one disconnects.
- Disconnect on lock or screensaver and reconnect on return.
- Bulk actions: Connect All, Disconnect All, Reconnect All, Discard All (with optional profile removal), Disassociate All.
- Shortcuts (Pro): disconnect, reconnect, and connect/disconnect all disassociated screens.

**3.5 Documented use cases** (implement as recipes or tutorials):
- HiDPI on displays that can't use flexible scaling (Sidecar, DisplayLink) via a mirrored or streamed virtual screen.
- Larger-than-native desktop (supersampling).
- **Headless Mac** remote desktop at any resolution.
- Portrait Sidecar; iPad teleprompter (flip).
- Salvaging a damaged screen with a partial stream plus a custom resolution list.
- Persistent desktop through a KVM.
- Dedicated 16:9 recording desktop.
- Two virtual desktops on one ultrawide via positioned PIPs.
- Temporal-dithering workaround (virtual screens are always 8-bit).
- Caveats: mirroring workarounds have sleep issues, color flicker, and mouse-cursor issues (Monterey 12.5+). With streaming, the cursor lives on the source; the target shows a halo, and optional auto-warp moves the pointer.

**3.6 CLI**: `create -type=VirtualScreen` with `virtualScreenName`, serial, vendor, model, `aspectWidth`/`aspectHeight`, `sizeInch`, `multiplierStep`, `limitMultiplierSize` + min/max, `flipped`, `virtualScreenHiDPI`, `useResolutionList` + `resolutionList`; `discard` (no identifiers = discard ALL).

---

## 4. Brightness

**4.1 Brightness control methods** (Free) — The app picks the best available controller per display:
- **Apple native** hardware brightness (Apple displays).
- **DDC** hardware brightness (third-party monitors).
- **Software via color table** (gamma table / EOTF; default when available).
- **Software via overlay** (dark overlay window), with an optional **Metal** path (off by default; extra processing cost; some Intel iGPUs warn about performance).
- **Compositor filter** layer (on by default; provides extra effects and basic adjustments when color tables can't be used).
- Settings: "Software-based video adjustments" master switch; color-table control (global and per display; "force support" for some system-virtual displays); "Prevent overlays from affecting screenshots/recordings" (off; may hide effects on DisplayLink, raise CPU use, and exclude effects from streams/PIP); "Elevated dimming/overlay priority" so overlays cover the lock screen and all Spaces.
- The UI shows the current method and why color-table control is unavailable (v5.0.6+).

**4.2 Combined brightness** (Free, default on) — One slider spans software dimming → hardware range → upscaling. Snap markers show "Min HW" and "Max HW". Optional hardware and software sub-sliders.
- Options: software-dimming switchover point (1–99%; default 25% for Apple, 50% for third-party, 20% while upscaling); **minimum allowed hardware brightness** (0–99%, **Pro**; used to avoid **PWM flicker** by keeping the backlight above its PWM threshold); "redefine 0% software level"; software-dimming gamma strength; smooth transitions (on).
- **Dimming to black** is supported (Free).

**4.3 Nits** — Per-display brightness nits ranges (manual overrides: hardware min/max, HDR peak SDR (capped at 500), HDR peak HDR; fallback estimates 25–350 nits). Nits can show on the slider and OSD (Free per the current Guide; [Conflict]: the homepage and legacy wiki list "nits on OSD" as Pro). Nits-based ranges for built-in Apple displays arrived in v5. CLI `brightnessNits`, `softwareBrightnessNits`, `hardwareBrightnessNits`.

**4.4 XDR/HDR brightness upscaling ("extra brightness")** — **Pro.** Pushes SDR desktop brightness above 100%, into the display's HDR headroom (up to 1600 nits on a Pro Display XDR or MacBook Pro XDR, ~2000 on some supported displays).
- Methods:
  1. **Direct brightness control & XDR upscaling** — hardware; **built-in Apple XDR displays only** (not the external Pro Display XDR / Studio Display XDR); **macOS 26.3+**, AS. Turn on "Allow direct control and XDR upscaling" (experimental). Options: direct scale minimum (0 nits) and maximum (defaults to the reported HDR limit); "Force EDR mode during direct control" (on; may also force other external Apple displays into EDR). Disables auto-brightness (state is saved and restored) and is incompatible with native brightness keys (the app must capture the keys). No HDR clipping and no extra GPU load.
  2. **Native XDR upscaling (legacy, macOS ≤26.2)** — selected the custom "BetterDisplay XDR" Apple preset; min/max nits (default 1600; suggests 1000–1400 to avoid thermal dimming). Uses undocumented APIs. Removed in v5.
  3. **Color-table upscaling** — software, **AS only**, any XDR display or third-party HDR display **in HDR mode**. Clips HDR video at SDR peak while active.
  4. **Metal/overlay upscaling** — software, AS and Intel, needs color-table adjustments **disabled**. May overblow HDR content.
- Toggle "Brightness Upscaling" per display (off by default since v3.3.0). Keys, slider, and shortcuts extend into the upscale range. Max scale value is 101–999% (default 160%, Pro).
- **HDR upscaling calibration** (Pro): a visual test (near-white face on white) sets the max headroom. XDR displays get "Set Default – Auto Calibrate", with dynamic recalculation from EDR headroom as panel brightness changes.
- Global options: "Continuous XDR upscaling readiness" (keeps EDR on for smooth transitions, Pro, on); "Insert intermediate OSD step at neutral 100%" (Pro, on); "Reset colors on neutral settings for HDR screens" (on); "Show warnings about color-table anomalies" (detects other apps fighting over gamma); optional chevron OSD icon for dim/upscale state [legacy].
- Ambient light sensor: the app disables the ALS while software upscaling is above 100% and restores it afterward (macOS sends EDR headroom notifications to all apps, causing CPU spikes).
- Recommended minimum for third-party HDR is DisplayHDR 600 or mini-LED.
- Risks: more battery drain; theoretical LED/LCD wear; software methods use public EDR APIs. Third-party displays in HDR mode get DDC brightness disabled by default (overridable).
- CLI: `brightnessUpscaling`, `directBrightnessUpscaling`. Shortcut: toggle upscaling (Pro).

**4.5 Brightness restore on startup/wake** (Free): restore combined + software brightness (default), don't restore, or restore non-brightness adjustments only. Protections against restoring full black ("allow restore to full dimming", off; the default floor is 15%) and against bad values saved during a dark wake on Apple displays. Safe Mode suppresses restoration.

**4.6 Dim on lock / screensaver** (Pro): default target 50%; floors of 30% (software) or 10% (Apple HW); DDC can reach 0%. Restores on return.

**4.7 Brightness sync** — see §7.3 (groups). Basic brightness sync in the Default Group is Free; nits-normalized sync is Pro. A tutorial shows "external monitors follow the MacBook's auto brightness" via "Synchronize changes triggered externally."

**4.8 Auto Brightness toggle** (Apple displays; Free) and **ambient light readings** (lux per display from a hardware sensor; Free in the feature table [Conflict: CLI help marks `ambientLight` get as Pro]).

---

## 5. Color & image adjustments

**5.1 Software adjustments** (per display; via color table and/or compositor filter):
- Free: software **brightness**, **contrast**; on/off effects (**Invert Colors**, Monochrome, Thermal, X-Ray, Median, Comic); **Suspend adjustments** (except brightness); **Reset**.
- Pro: **gamma**, **R/G/B gamma**, **gain**, **R/G/B gain**, **color temperature**, highlight, shadow, saturation. Hue, vibrance, sepia, and quantization are not explicitly classified in the Guide; the CLI marks them Pro.
- v5 "advanced compositor filters" (Pro): sharpening (Sharpness 0–10, Unsharp Mask 0–25), blur (gaussian, motion), noise reduction, bloom/gloom, vignette, pixellate/hex pixellate/crystallize/pointillize, edges/edge work, halftones (CMYK, dot, hatched, line), and "geometry" [Unclear what "geometry" covers in display adjustments; the stream side has flip/rotate/zoom/underscan].
- Group syncing of filters (Pro), plus CLI and Shortcuts access.
- Caveat: color-table adjustments clip HDR content ("Some adjustments may clip HDR content!").

**5.2 Custom 3D LUTs** (Pro; v5) — Import `.cube` 3D LUTs (size 2–128, ≤256 MiB; 1D or mixed LUTs rejected). Interpretation settings: SDR space (sRGB / Rec.709 / Display P3) or HDR (Rec.2100 PQ, 203-nit reference white, 1000-nit peak; experimental), reference white, input range. Apply to a display's image adjustments, PIP, streams, or Video Filter Windows; multiple LUTs stack in list order. Export and delete are free.

**5.3 Framebuffer appearance remap** (AS; Free): Standard / Inverted / Grayscale / Inverted Grayscale. Not persisted. CLI `standardFramebuffer` etc.

**5.4 GPU dithering toggle** (AS; Free) — disables temporal dithering (eye-care). Intel alternative: choose 8-bit color depth.

**5.5 Uniformity correction toggle** (built-in displays; Free).

**5.6 Underscan** — native underscan slider (Free; normally Intel; "force-enable underscan slider" on AS is risky and not guaranteed).

**5.7 Rounded corner overlays** (v5.0.6; Free): top and bottom corner radius 0–3% of the shorter side, as black overlays.

**5.8 Color profiles** (Free): pick an installed ColorSync profile per display; context actions (Activate, Show in Finder, Open in ColorSync Utility, Remove); "Remove All Factory Profiles"; "Unlock color profile management for Apple displays" (advanced).
- **Automatic SDR↔HDR profile switching** (Pro): implemented as separate SDR-profile and HDR-profile protection entries (§7.6).
- Safeguard (v5.0.6): color-table control is disabled on ALL displays when any display uses a custom profile, to avoid a macOS black-screen bug (overridable, with a warning).

**5.9 Apple Display Presets ("XDR presets")** (Free): select factory, reference, or custom presets on displays that expose them (built-in XDR, Pro Display XDR, etc.). Can't create presets. A fixed-brightness preset disables hardware brightness. CLI `xdrPreset`, `xdrPresetList`, `xdrPresetReset`.

**5.10 System colors** (Tools menu): Dark Mode, Night Shift, and True Tone toggles (Free in the menu; Pro per the CLI help [Conflict]); **Night Shift strength** slider −10…+10 (Pro); "Turn off Night Shift & True Tone in HDR mode" (Pro); Apple keyboard backlight shortcuts (Pro).

**5.11 Night Shift for TVs** (Free) — set display role to "Computer monitor" (§2.6). Natively connected displays only; DisplayLink and Sidecar can't use Night Shift (use the software color-temperature slider instead).

**5.12 E-book look**: quantization filter + grayscale framebuffer.

---

## 6. DDC & hardware/device control

**6.1 DDC/CI controller** (Free) — Controls monitor hardware over I²C. Supported features: brightness (luminance), contrast, volume, mute, RGB gain, RGB black level, saturation, input select, power off, screen/backlight on/off, factory reset, and any VCP code via custom features or raw commands. A full named VCP list is in the CLI help.
- **Detect DDC Capabilities** (parses the capabilities string and test-reads features); **Auto-Configure** (enables supported features, sets ranges); "use current values as neutral"; detailed report including unmapped VCPs.
- Per feature: enable; VCP code override (comma-separated hex, multiple allowed); min/max raw range (100/200/255); mapping skew (−10…10); invert; neutral value; ON/OFF data values; backlight on/off data (1/4) with a 2000 ms wait; power-off value (5); **periodic readback** (default 5 s, 0.5–3600 s).
- Advanced: startup policy (assume last / write last / read from display); reapply on wake (+delay); **dedicated per-display command queue** (default on for AS, off for Intel); timing (send count 2, delay 10 ms, retries 4, fail wait 5 ms, read wait 10 ms); ignore read checksum errors.
- **Input source list** customization (value, "LG alt" alternate addressing, icon, label, visibility Hidden/Block 1–4).
- **Custom DDC features** (Pro; user-defined VCP controls).
- **Raw DDC via CLI/HTTP/Shortcuts** (`ddc`, `ddcAlt` with `vcp` and `value`; set/get with min/max). This is an m1ddc alternative that works on all connections the app supports.
- HW: AS and Intel over compatible connections. The comparison table explicitly lists **built-in HDMI on M1 Macs and the entry-level M2 Mac mini** and the **2018 Intel Mac mini's HDMI** as supported. Docks, hubs, and adapters may block DDC even when video works. TVs and smart monitors often lack DDC. Apple displays are normally excluded (older Apple Cinema/LED displays need a 0–255 range to avoid permanent dimming). DisplayLink DDC works through DisplayLink Manager where supported.
- [Unclear] An exact per-port compatibility matrix for M1 Pro/Max/M2+/M3/M4 built-in HDMI, USB-C, and Thunderbolt isn't public in the Guide pages fetched.
- Risks: input switching can strand you (you may not be able to switch back over the same link); repeated power or backlight commands can lock some monitors' OSD; "Unable to enable DDC due to display or connection issues."

**6.2 HDMI-CEC** (Free; v5) — Sends CEC commands for TV volume up/down, mute, standby/wake (power), input selection (including "switch to this Mac"), and remote navigation (select, arrows, menus, exit). Also a virtual CEC remote, a configurable HDMI input count (1–15, default 4), destination logical address (tv, audioSystem, …), and auto-power options [Unclear details].
- HW: **AS only**, through **DisplayPort AUX DPCD CEC tunneling** (i.e., DP→HDMI converters, including some built-in HDMI ports and adapters). The device must support CEC. CLI `sendCEC`, `CECAddress`, `CECReport`.

**6.3 Network device controllers** (Free):
- **LG webOS TV**: IP + pairing, Wake-on-LAN (MAC), virtual remote, inputs (TV-reported with status), volume/mute, service menus (Option key).
- **Samsung Tizen**: remote, power, source, WOL, MAC override (v5), service/hospitality menus.
- **Philips Android TV**: remote, power, volume, inputs.
- **Yamaha AVR**: volume, input list (opt-in), amplifier zone.
- [Unclear] Full settings pages; the fetch failed for these.

**6.4 DisplayLink controller** (Free): DDC and color control where supported; "DisplayLink auto-discovery" through DisplayLink Manager (Pro, on by default); manual configuration mode.

**6.5 Volume control & native audio**: DDC volume and mute; fallback to the matched macOS audio device ("handle devices with native volume control"). v5.1.1 improved native USB audio. Volume feedback sound plays when enabled in macOS. Mute-fix tutorial.

**6.6 Control Integration (custom controllers)** — Maps BetterDisplay sliders, toggles, or commands to user-defined actions: **shell script** (bash), **URL** (HTTP/HTTPS GET or a custom scheme), or **DistributedNotification**.
- Placeholders: `[*:Identifier:*]`, `VALUE`, `EVENT_HOOK`, `DEVICE_NAME`, `DEVICE_DESCRIPTION`, `DISPLAY_ID`.
- Readback (pull) with a regex, a multiplier, and periodic polling. Redundancy filter (default 1 s). No escaping of inserted values (a security caveat).
- Custom control definitions (ranged / toggle / command, CLI designation, icon, sync-eligible) are **Pro**. Predefined controls are free.

**6.7 Device header power switch modes** (per display): Connect/Disconnect (default), Screen Control (backlight), DDC Power Off, or Disabled.

---

## 7. Display management

**7.1 Connect/disconnect displays ("soft disconnect")** — **Pro** (reconnecting a display the app disconnected stays free). Removes a display from the layout without unplugging it. On AS, compatible displays go to standby. On Intel, the display is dimmed instead (not fully off).
- Options: require another suitable display to stay connected (on); allow disconnecting all displays (off); disconnect reconnected displays on wake; Intel "fully dim on disconnect"; keep Sidecar displays in the list after disconnect; allow disconnecting non-native displays (off).
- Built-in display rules: **auto-disconnect the built-in display when an external display connects** (AS only, Pro); per-display exception "ignore for built-in auto-disconnect"; iMac and **base-M3** safety overrides (reconnecting may need a restart; disabled by default since v5.0.6).
- Auto-connect all displays on startup, on quit, and when no displays are left (all on). Optional "preserve soft-disconnected state on startup." "Aggressive disconnect" (Pro).
- Shift-click in a header disconnects all other displays (connect one, disconnect the rest) or reconnects them.
- Tools: Connect All Displays (recovery; free), **Disconnect All But Main** (Pro). Shortcuts: disconnect display, connect all, disconnect all except main, toggle built-in (all Pro).
- Risks: on Intel, unplugging or powering off a soft-disconnected display or closing the lid can leave no usable display until restart. Exclusive system virtual-display sessions block reconnection. The lid-closed built-in can't be forced on.

**7.2 Mirroring** — Set or clear mirror targets per source; Stop Mirroring. **Pro** (non-Pro users must use System Settings). Changes persist in macOS. Virtual-screen auto-mirroring is AS only. Command + brightness-down toggles mirroring.

**7.3 Display groups** — Named sets of displays with activation rules and features.
- Default Group (free) vs custom groups (Pro).
- Activation: all members present / any / any two / feature-participants present; "only group members can be present"; exclusive groups; priority ordering; auto or explicit membership.
- **Synchronization**: brightness (auto, or combined/HW/SW explicitly — Pro), **nits-normalized brightness** (Pro), volume, mute, hardware contrast, saturation, RGB gain, black level, any or individual software image adjustments and filters, custom controls. Modes: delta (default) vs absolute; consider range differences; sync externally triggered changes (ALS, Control Center); source filters (external, Apple, main, list) and target filters (exclude virtual screens or HDR/reference-preset displays). Shift bypasses sync for one change.
- **UI scale matching** (Pro): matches the physical UI size across displays using physical dimensions (mm, editable). Watched and affected lists; tolerance (default 10%); can update resolution protections; enforce on connect. A manual "Match Group UI Scales" action exists.
- **Resolution syncing** (Pro per the comparison table) [Unclear: it may be the same thing as UI-scale matching].
- **Layout protection** (Pro): per-display rules ("place X left/right/above/below Y") with anchor-point offsets (adaptive layout anchors for natural pointer movement), orientation-specific rules (portrait/landscape), protected main display, Apply All Protections, apply on startup (off). Higher-priority groups win conflicts.
- CLI: `enabled`, `active`, `activationPolicy`, `synchronization`, `layoutProtection`, `uiScaleMatching`. The Tools > Groups menu toggles groups quickly.

**7.4 Visual arrangement / Move Display**:
- **Arrange** (drag rectangles with snapping, seam insertion, Shift to bypass snapping, a main-display bar, stacked mirrors) — **Free** (v5). Some advanced grid-snap options are Pro.
- **Align** (16 placements relative to a reference display: edges ×3 alignments + 4 corners) — **Pro**.
- CLI `placement` (XxY) and `moveTo` (Pro).

**7.5 Main display** — "Set as Main Display" (Free in the menu; the shortcut is Pro); CLI `main`.

**7.6 Configuration protection** (all Pro) — Per display, captures and re-enforces resolution (incl. HiDPI), refresh rate (incl. VRR and unexposed rates), color mode (SDR) and HDR color mode (AS), rotation, SDR color profile, HDR color profile, HDR on/off, mirroring set, and main status. Enable All / Disable All. In-app changes update the stored values; external changes get reverted. Loop protection is included. Optional notifications. CLI `protect*`.

**7.7 Rotation** — 0/90/180/270 on displays macOS reports as rotatable. Ordinary rotation is Free [Conflict: the CLI help marks `rotation` as Pro]. Rotation shortcuts are Pro, with options to treat them as toggles or skip the internal display.

**7.8 Refresh rate** — Ordinary rates for the current mode (Free), including "(Variable)" VRR entries and ProMotion. **AS: connection-level extra rates, including NTSC fractional rates and unexposed timings** (Free; Shift opens them; Option-Shift disables matching). A refresh-rate **reporter** shows measured, actual, and nominal rates.

**7.9 Color Mode** (AS only) — Pick the connection format: bit depth, RGB/YCbCr, chroma 4:4:4/4:2:2/4:2:0, full/limited range, SDR/HDR10/Dolby; preferred mode starred.
- Free when SDR/HDR encoding stays the same. Switching encodings, "Show Mixed Modes", and "Allow **Forced HDR**" are Pro.
- Risks: forced HDR or mixed modes can cause green, corrupted, or blank screens.
- CLI `connectionMode` (e.g., `bpc:8+range:full+encoding:rgb+chroma:444+hdrmode:sdr`; flagged risky).

**7.10 Color Depth** (Intel only; Free) — Framebuffer 8- vs 10-bit.

**7.11 HDR toggle** — "Enable HDR Mode" for third-party HDR displays (**Pro**), plus "Forced HDR" (Pro, AS). Optionally turns off Night Shift and True Tone in HDR.

**7.12 Redetect / Reinitialize** — Redetect displays (Free; global). **Reinitialize** external displays (AS; Free; reloads custom configuration and EDID; can blank screens; options for on wake and on unlock). Reset VMM7100 HDMI adapter (AS; for that chipset only).

**7.13 Swap identical displays** (Pro) — Exchanges position, mode, orientation, HDR, and the identity mapping of two indistinguishable displays.

**7.14 Display identification & memory** — Identification method per display (system UUID; vendor/model/serial; …; +port (AS); +location; full EDID). Forget displays after 90 days. Transfer settings from a disconnected record. Forget/reset display. Show offline displays in Settings. Free.

**7.15 Prevent sleep while a display is connected** (Pro) — Per display; optional menu-bar cup icon.

**7.16 Sidecar** — List and connect Sidecar devices (CLI `sidecarList` / `sidecarConnected`); "always show in app menu when available" (needs connection management). Portrait Sidecar via virtual screen + rotated stream (Pro).

**7.17 Model-specific "adaptations"** — One-click setups for Monduo tri-screen, SOTSU, and FlipGo portable monitors (mostly Pro).

**7.18 Reset display system settings** (Free; admin needed) — Removes macOS display configuration, factory profiles, and installed overrides, optionally with an NVRAM clear, then reboots. Forget All Displays.

---

## 8. PIP, streaming & capture (all Pro to start or change; stopping is free)

**8.1 Picture in Picture** — A live window showing a physical or virtual display.
- Multiple configurations per source; window tabs and merge.
- Window level: normal / keep above (default) / above menu, Dock, and Spaces (+ show on lock screen).
- Title bar on/off with a minimal controls strip; lock position; prohibit resizing; free aspect; integer (nearest-neighbor) scaling; snap to 25% steps.
- Show the cursor; exclude the PIP window from its own capture; shadow; **click-through**; warp the cursor to the source (Cmd-click); auto-warp (defaults key).
- Crop (draw on screen, boundary color); flip H/V; rotate; alignment; zoom (full screen); magnification 100–200%; alpha; **target FPS** 1–200 or unlimited; video filters; HDR filter pipeline (AS).
- Start automatically when the source connects; pause; bring to the mouse's screen.
- Needs Screen Recording permission. CLI `pip` plus many sub-parameters.

**8.2 Full-screen streaming (Stream Display / Stream Virtual Screen)** — Shows one display's content full screen on another.
- Overlay vs Full Screen Window Mode; show on lock screen; 1:1 pixel mapping; free aspect; integer scaling; alignment; flip; rotate; zoom 10–300%; underscan 10–200%; alpha; target FPS; video filters; HDR pipeline.
- Show cursor; **"Prevent cursor entering"** (experimental cursor exclusion from stream targets; needs input-monitoring permission); warp mouse.
- Crop; multiple configurations; pause/hide; resume stream on connect; "switch target to native mode while streaming"; swaps main status if the target was main.
- **Self-stream with filters**: applies filters to a display via a compositor filter (no capture needed).
- CLI `stream`, `targetSelf`.

**8.3 Teleprompter / portrait Sidecar / damaged screen** — Recipes built on 8.2 (flip, rotate, partial stream).

**8.4 Video Filter Window** (v5) — A movable window that applies filters to whatever is behind it. Uses compositor rendering (default; no Screen Recording needed) or the capture path (FPS and HDR options). Priority, click-through, lock, alpha, multiple configurations, auto-start. Also full-screen video filters.

**8.5 Stream Selected Content / selected-window PIP** (v5) — Uses the macOS content-sharing picker for one or more windows; the output window can hide its background to show content only (with a source shadow option). Priority, alpha, magnification, free aspect, integer scaling, snap, zoom, flip/rotate, filters, FPS, auto-start (restores the source by window match). Missing sources are marked. CLI `contentStreamWindow`. [Unclear: the Guide doesn't name ScreenCaptureKit, but the picker implies macOS's content-sharing picker / ScreenCaptureKit.]

**8.6 Shared video-filter set** (for 8.1–8.5):
- Brightness, contrast, exposure, gamma, highlight, shadow, saturation, vibrance, hue, temperature (2000–20000 K), sepia, posterize.
- Vignette, pixellate, crystallize, hex pixellate, pointillize, edges, edge work, CMYK halftone, dot/hatched/line screen, noise reduction, gaussian/motion blur, unsharp mask, sharpness, bloom, gloom.
- Photo effects (Noir, Chrome, Instant, Fade, Transfer, Process); invert, monochrome, thermal, X-ray, comic, median.
- Blend modes (12) with opacity; custom LUTs; reset.
- The CLI `videoFilter` supports batch syntax.

**8.7 Stream/PIP shortcuts** (Pro): stop all, hide all, pause all, start/stop PIP, warp cursor, crop toggle, and crop size/origin adjustments.

---

## 9. Keyboard, media keys, shortcuts & OSD

**9.1 Native brightness keys** (Free; needs Accessibility, or "Device Control and Data Access" on macOS 27):
- Policies: engage when a controllable display is present, or only when a display isn't natively controllable.
- F14/F15 as alternative brightness keys (on); fine scale as default (off).
- Modifiers: **Shift+Option = fine step**; Shift = skip group sync; Ctrl = built-in only; Ctrl+Cmd = externals only; Shift+Cmd = other displays; Option = open System Settings pane; Cmd + brightness-down = toggle mirroring.

**9.2 Native volume and mute keys** (Free): policies (audio device name matches a display (default), device lacks native volume, any controllable display, always); fallback to the macOS device; leave mute to the OS; fine scale; feedback sound (Shift inverts it). v5.1.1 sped up key handling and reduced Control Center interference.

**9.3 Target displays** (Free) — Brightness and video targets: screen with the pointer (default), screen with the focused window, or all suitable screens (mirrors and stream targets included). Audio targets: display matching the audio device name (default, with a per-display override), pointer, focus, or all.

**9.4 Step sizes** — Standard and fine steps configurable for range controls [Unclear: exact defaults; v5.1.1 uses a 16-segment OSD bar].

**9.5 Custom keyboard shortcuts**:
- Free (basic): brightness ±, contrast ±, gamma ±, volume ± (with fine variants), mute toggle/set, invert, reset adjustments, suspend adjustments, redetect, reinitialize, VMM7100 reset, show app menu, show console, quit, restart.
- Pro (advanced): color temperature ±, upscaling toggle, all resolution/favorite/HiDPI/HDR/notch/undo shortcuts, set main, swap identical, rotation, connection and DDC power, virtual screen management, stream/PIP, **10 input-source slots** (display + input + key), Night Shift ±/toggle, True Tone, Dark Mode, keyboard backlight ±.

**9.6 OSD** (Free):
- Styles/placements: under the menu-bar icon (default), Classic (big square), top corner, top center, bottom center, under the menu bar, System OSD (macOS 26 only), Traditional OSD.
- Rounded style and 16-segment bar (default on from macOS 27.2); adaptive background; shadow; show value; show nits.
- Which display shows it: affected (default), active, or main.
- Interactive: hover-drag the OSD slider; endpoint clicks move ±10%.
- Per-display "show volume OSD."
- Third-party OSD dispatch (§10.6).

---

## 10. Automation & integration (access is free; actions inherit their Pro gating)

**10.1 CLI** — Run the app binary (`…/Contents/MacOS/BetterDisplay <op> -param=value`), which talks to the running instance. Operations: `perform`, `set`, `get`, `toggle`, `feed`, `create`, `discard`, `help` (plus console-only `exit`/`clear`).
- Device selectors: `tagID`, `UUID`, `displayID`, `name`, `nameLike`, `originalName[Like]`, `productName[Like]`, vendor, model, serial, alphanumericSerial, year/week, `registryLocation`, `type`, `displayWithMouse`/`Focus`/`MainStatus`/`NonMainStatus`. Value modifiers: `value`, `offset`, `min`, `max` (min/max for normalization).
- Roughly 150 feature parameters cover everything in this document. See the wiki "Integration features, CLI" page for the full list. Also verbose logging (`-v`, `-v2e`).
- **betterdisplaycli** is a Homebrew wrapper using DistributedNotifications.

**10.2 Console** (Free; v5) — An in-app window that runs integration commands, with history (1000 entries), optional live app logs, and clear.

**10.3 Custom URL scheme** (`BetterDisplay://set?name=X&brightness=0.8`; off by default) — Optional token; **x-callback-url** for success, error, and results.

**10.4 HTTP server** (off by default; port **55777**, configurable) — `http://host:55777/set?...`. Optional token in the query string. Plain HTTP, listening on all interfaces, so remote access is possible. Used for Home Assistant and Stream Deck recipes. Caveat: the token appears in logs and exports.

**10.5 Distributed notifications**:
- Request `pro.betterdisplay.BetterDisplay.request` (JSON `{uuid, commands[], parameters{}}`) and response `….response` (`{uuid, result, payload}`).
- Lifecycle `….launched` / `….terminated`. The legacy `com.betterdisplay.*` prefix is still accepted.

**10.6 OSD integration API** — The app broadcasts `….osd` with JSON fields displayID, systemIconID, customSymbol, text, lock, controlTarget, value, maxValue, fade timings, and symbol size. Integrated apps: MediaMate, DynamicLake, Alcove, Atoll (BoringNotch in progress). CLI toggles `osdShowBasic`, `osdShowCustom`, `osdIntegrationNotification`.

**10.7 macOS Shortcuts (App Intents; macOS 13+)** — 41 actions:
- Dim/brighten all; set brightness (all or one, with an upscaling-range option); set DDC volume.
- Image adjustment set/get/offset/all-displays; toggle filter, get filter state, toggle/reset adjustments; invert.
- Send/get DDC (named or custom VCP); toggle DDC mute.
- Rotation; color profile; Apple preset; display mode; input source; color mode; move screen; set main.
- Toggle HDR, upscaling, direct upscaling, connect/disconnect, auto brightness; reinitialize.
- Mirror / unmirror; framebuffer mode.
- Configure, apply, or restore EDID.
- Toggle PIP; toggle screen stream.
- Anything else goes through "Run Shell Script" + CLI.

**10.8 AppleScript** — **Not documented** anywhere in the current Guide or wiki [Unclear / likely unsupported beyond `open` URL or shell].

**10.9 Per-display events** (Free event editor) — Hooks for soft disconnect, soft reconnect, hard disconnect, hard reconnect, system sleep, wake (immediate), and wake (after delay). Each can run a shell script, URL, or DNC action. The README says per-display command integration requires Pro [Conflict with the Guide, which says the event editor has no separate Pro requirement].

**10.10 Raycast extension** (third-party) and Stream Deck / Home Assistant (via HTTP) recipes.

**10.11 License management CLI** — `manageLicense -status | -activate -email= -key= | -deactivate | -activationsJSON | -hideui | -showui`. Supports MDM. Firewall: `*.paddle.com`, `*.paddleapi.com`.

**10.12 Hidden `defaults` keys** — `pipShowResizePercent`, `pipAutoWarp`, `screenStreamAutoWarp`, `screenStreamMouseHalo`, `disallowActivationWithOutdatedLicense`, `disablePreventSystemSleep` (sleep prevention during EDID operations).

---

## 11. EDID & diagnostics

**11.1 EDID retrieval and export** (Free) — OS-managed or direct I²C read (length auto or 1–4096). Decoded summary; show as Base64, hex, C array, or hex blocks; export binary. Load or paste custom EDID data.

**11.2 EDID override — Apple silicon** (Pro) — **Volatile**: applies the custom EDID now and restores factory (unapply); auto-apply on detection (suppressed in Safe Mode). Options: preserve continuity on identity change; restore factory EDID on quit. Not available for built-in Apple displays. Risks: flicker, mode changes, new display identity; recover by replugging. Also used during reinitialize.

**11.3 EDID override — Intel** (Pro) — A persistent model override via system configuration (Apply + admin + reconnect/restart).

**11.4 Write EDID to device** (Pro; mostly Intel UI) — Writes the monitor's or emulator's EEPROM (≤256 bytes). Requires an explicit "Unlock EDID write — I understand the risks" checkbox. Tunable chunk size, delay, and retries. **Can permanently brick the device.**

**11.5 Diagnostics & reports** (Free; v5):
- Display Information report and export (identifiers, capabilities, HDR/EDR values, current and preferred connection modes, XDR/profile/Sidecar config, link info: transport, link rate, lanes, bandwidth, DSC, HDCP versions, DPCD).
- CLI reports: `EDIDReport`, `DPCDReport`, `rawDPCD`, `DSCReport`, `CECReport`, `appleBrightnessReport`, `displayInformation`, `ddcCapabilities[String]`, `connectionModeList[All]`, `refreshRateList`, `displayModeList`, `identifiers`.
- DisplayID extension blocks are supported.

---

## 12. Menu-bar UI

- **App menu**: per-display blocks (collapsible header with power switch, status badges M/SOURCE/TARGET/VIRTUAL/mirror/stream/association/sleep-prevention), first-level sliders, a "more options" chevron, and inline or floating submenus. A Tools section holds displays and virtual screens, groups, Move Displays, Video Filter Window, Stream Selected Content, System Colors, updates/settings/quit, and the console. A button bar (gear, ellipsis, optional quit) shows notices (update, permissions, licensing).
- **Presentation**: Standard (default), **Sidebar** (Control Center-style glass; macOS 26+), **detachable window** with alpha 10–100% (Pro).
- **Right-click quick menu** (v5): Settings, Connect All, Redetect, Reinitialize, Swap identical, Dark Mode / Night Shift / True Tone toggles, Check for Updates, Console, Restart, Quit. Option-click opens Settings.
- **Menu contents**: each item can be Hidden, When Expanded, or Visible. Sliders: brightness, contrast, volume, resolution. Display submenus: about 22 items. Tools items. Reset Menu Layout.
- **Appearance and behavior**: slider labels/values/nits, scroll/swipe on sliders, inline expansion, auto-tidy, hide siblings, auto-close, main display first, header for a single display, power switch in headers, PIP menu with a single display, button bar at the top, icons on/off, icon bounce.
- **Menu-bar icon**: show/hide (hidden when all displays request it); custom SF Symbol (also CLI `appMenuIcon`); match the main display's icon; cup icon while preventing sleep; centered alignment.
- **Per-display presentation**: custom display name, SF Symbol icon, ordering string, hide from menu, "hide menu icon when no other displays present."
- **Settings window**: panes for Displays, Groups, Application, Menu, Keyboard, Pro, About; help-text toggle; Guide link; per-pane help buttons; language picker (38–39 locales, RTL); Pro and Experimental badges; pending-override Apply/Undo notice; activation notice.

---

## 13. App-level settings

- **Launch at login** (login item). **Safe Mode**: hold Shift at launch to skip virtual-screen connection, brightness/color restore, protections, DDC writes, EDID auto-apply, and associations.
- Crash reporting (Sentry; on by default). "Licensing & Pro Features" toggle (off = free mode only).
- Configuration delay (0.2 s), wake delay (1.5 s), UI animation speed.
- **Export / Import settings** as a plist (`defaults export pro.betterdisplay.BetterDisplay`). Display settings are tied to UUIDs, so use "Transfer settings from" or the "Match basic identifiers" method when moving between Macs. Settings formats across major versions are incompatible.
- **Reset app settings** (keeps the license); reset warning dismissals; restart and quit.
- **Exhaustive manual reset**: `defaults delete`; remove `/Library/Preferences/com.apple.windowserver.displays.plist`, `~/Library/Preferences/ByHost/com.apple.windowserver*`, `/Library/ColorSync/Profiles/Displays/*`, `/Library/Displays/Contents/Resources/Overrides/*`, and `~/Library/Application Support/BetterDisplay`; on AS, `nvram -c`.
- **Updates**: Sparkle, with auto-check (on), auto-download (off), pre-release channel, and internal pre-release channel.
- **Notifications**: Notification Center, traditional popups, or disabled; configuration-protection notices. **Dock icon**: when Settings is open (default), when any window is open, always, or never; optionally show briefly at startup.
- **Permissions used**: Accessibility (or Device Control & Data Access on macOS 27) for keys; Screen Recording for streams, PIP, and capture filters; input-event listening for cursor exclusion; a privileged helper or admin for system overrides, profile deletion, and resets.
- **Profiles/presets**: no first-class "profile" object. The equivalents are display groups (activation-based presets per location), resolution favorites, Apple presets, and Shortcuts or CLI scripts (the "Work/Evening presets" tutorial). Per-display rules live in per-display settings, associations, protections, and events. No per-app rules are documented [Unclear / absent].

---

## 14. Free-vs-Pro comparison table (current Guide, v5)

Free:
- Expanded features: HDMI-CEC; console; per-display event actions; diagnostics; ambient light readings; visual arrangement (basic); sidebar and right-click menu; OSD styles.
- Core UI and brightness: GUI; multiple brightness methods; native keys; basic shortcuts; OSD; nits on OSD [conflict]; color-table, overlay, and combined dimming; dim to black.
- Device control: LG, Samsung, Philips, Yamaha; DDC on AS and Intel (incl. M1 / base-M2-mini / 2018-mini HDMI); DDC brightness, contrast, volume, color gain, input, input customization, power; DDC auto-config; DisplayLink DDC; standard script/URL/notification integration.
- Display configuration: custom scaled-resolution editing; Night Shift for TVs; name overrides; native/default resolution overrides; virtual screens from presets; display mode, refresh rate, NTSC rates, and color mode selectors; resolution slider; software contrast.
- Data, profiles, automation: EDID retrieval/export; color profile and XDR preset selection; CLI; Shortcuts; HTTP and URL scheme; external HUD integration; basic brightness sync.

Pro:
- v5 filters and capture: compositor filters (sharpening, geometry, color); 3D LUTs; window/selected-content streaming; FPS targets; compositor Video Filter Windows; expanded filter sync and manual UI-scale matching; cursor exclusion.
- Brightness: color-table, Metal, and direct XDR upscaling; third-party HDR upscaling; HDR calibration; advanced shortcuts; custom integration and DDC controls.
- Scaling and connections: flexible HiDPI; connect/disconnect; virtual-screen matching and association; custom virtual-screen configs; HDR and high-refresh virtual screens.
- PIP and streaming: PIP; Video Filter Windows; full-screen streaming; stretch, rotate, crop; teleprompter flip; mirroring configuration and protection.
- Color: advanced software color; color temperature; configuration protection; EDID overrides; automatic SDR/HDR profile switching; forced HDR.
- System and groups: prevent sleep while connected; custom groups; advanced and nits sync; resolution sync and UI-scale matching; adaptive layout protection.

Not open source: BetterDisplay. Open source: MonitorControl, m1ddc.

---

## 15. Conflicts & unclear items (resolve during design)

1. **Nits on the OSD**: Free per the current Guide (OSD and feature table) vs Pro per the homepage and legacy wiki.
2. **Virtual screen association**: Pro per the current Guide (create sheet, Associated Displays) vs Free per the legacy wiki table.
3. **Rotation, Night Shift, True Tone, Dark Mode, notch, ambient light via CLI** are marked "Pro feature" in the generated CLI help, while the menu equivalents are Free.
4. **Per-display event commands**: the README says integration via shell scripts and URLs requires Pro; the Guide's event editor lists no Pro requirement.
5. Exact **DDC port compatibility matrix** (built-in HDMI on M1 Pro/Max, M2 Pro, M3, M4; TB docks) isn't in the fetched pages.
6. **HDMI-CEC** settings details (auto-power options, which built-in ports or adapters support DPCD CEC tunneling): the Guide page failed to load.
7. **Network controller settings** (LG, Samsung, Philips, Yamaha pairing details) and the **DisplayLink controller** page weren't retrievable.
8. **Which Macs** support HDR and high-refresh virtual screens.
9. **"Geometry"** in v5 advanced image adjustments isn't defined for display adjustments.
10. **AppleScript**: no mention; treat as unsupported.
11. **Resolution syncing** vs UI-scale matching: possibly the same feature.
12. Keyboard **step-size defaults** and full "Configure Steps for Range-Based Controls" options weren't fetched.
13. "Picture-by-Picture" appears in the technical-reference glossary; no feature page was found.
14. Internal mechanisms (private CoreGraphics/SkyLight APIs for virtual displays, IOAVService for DDC on AS, DCP/IOMobileFramebuffer properties, etc.) aren't documented publicly. Hints from the CLI help include `framebufferBoolProperty`/`NumericProperty` (AS), "DisplayPort AUX DPCD CEC tunneling", "I/O registry location", the overrides folder `/Library/Displays/Contents/Resources/Overrides`, and EDR for upscaling.

---

## 16. Sources used

- https://betterdisplay.pro/ (homepage, pricing, feature list)
- https://github.com/waydabber/BetterDisplay (README, cloned) + repo history (`opensource` branch, commits 1e39ece / 4dde9ba)
- GitHub wiki (cloned `BetterDisplay.wiki.git`): Home, List-of-free-and-Pro-features, Fully-scalable-HiDPI-desktop, MacOS-scaling-HiDPI-LoDPI-explanation, XDR-and-HDR-brightness-upscaling, Integration-features-CLI (full generated CLI help), Enable-Night-Shift-for-televisions, Eye-care (PWM/dithering), DIY-teleprompter, Rotated-Sidecar, Salvage damaged screen, Safe-mode/app-reset, Export/import settings, Console logging, License-management-scripted, Getting-a-Pro-License
- https://github.com/waydabber/BetterDisplay/releases (v4.3.6–v5.1.1 notes)
- https://github.com/waydabber/BetterDisplay/discussions/739 (license terms)
- BetterDisplay Guide pages under https://betterdisplay.pro/guide/:
  - licensing/free-and-pro-features
  - interface-reference (app-menu; device-menu and its display-mode, sliders, refresh-rate, color-mode, color-depth, mirroring, streaming, picture-in-picture, move-display, video-filters, rotation, device-control, image-adjustments, input-source, color-profile, apple-display-preset, configuration-protection, management-and-toggles, header-and-connection pages; tools and its displays-and-virtual-screens, stream-selected-content, video-filter-window, system-colors, console pages)
  - settings (displays/overview and its connections, create-virtual-screen, advanced-virtual-screen-settings, brightness-upscaling-and-dimming, custom-controls, custom-lut-filters pages; displays/display and its general-settings, additional-settings, device-control, device-control/ddc, image-adjustments, system-configuration, edid pages; displays/virtual-screen and its associated-displays page; groups, groups/group and its synchronization, ui-scale-matching, layout-protection pages; application and its startup-and-privacy, integration, notifications-and-dock, updates pages; menu and its resolution-controls, appearance-and-behavior, menu-contents, menu-bar-icon pages; keyboard and its shortcuts, native-keyboard-control, osd, target-displays pages)
  - integration (shortcuts, controls-and-events, third-party-apps, terminal-preferences)
  - faq (index pages: ddc, remote-displays, scaling, edid)
  - tutorials (index)
  - technical-reference (index, ddc, synchronization, display-association, hdmi-cec, displaylink, virtual-screen, sidecar)

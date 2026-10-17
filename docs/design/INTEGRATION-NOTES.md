# Integration notes (lead)

Collected from team reports for the README, docs and the final review.

## CLI exit codes
- `pip`: 2 usage or ambiguous name, 3 not found, 4 refused, 5 unavailable.

## Hardware checks (Appendix D additions)
- A: helper disclaim + code-signature checks (ad-hoc and Developer ID); Accessibility/relaunch flow on 27; Carbon hotkeys under Secure Input; menu choice with deferred rebuilds; `.regular` ↔ `.accessory` on Settings.
- B: `.forSession` trial + Keep persistence; MonitorPanel in the guard; permanent-ops revert after reboot; `kill -9` with armed trial; auth-window process paths (`AuthProcesses.paths`); MPDisplay encodings and underscan/preset selectors (guesses; wrong guesses disable features).
- E: SCContentFilter including/excepting; window crop orientation; queue depth; content-sharing picker on 14/15/26; session dictionary keys; native-mode flag 0x02000000.
- F: non-activating panel focus as accessory app; 0xD6=4 standby wake via 0xD6=1; Identify labels over full-screen apps and AirPlay.

## Known limitations to document
- B: "captured" = shielding-level window; EDID names on Intel only; panic HUD is a toast.
- E: Safari private windows aren't marked (add Safari to protected apps); window sources can't auto-start or start from CLI; imported LUTs aren't in Backup; cursor exclusion and self-stream filters deferred.

## Integration fixes queued
- F: floating panel and Overview resolution controls should use `ctx.connectPlanner.resolution` (`modes(for:)`, `label(_:)`, `sliderModes`, `sliderValueText`, `snappedStop`, `currentMode`, `apply(_:to:)`, `step(_:by:)`) instead of raw CGDisplayCopyAllDisplayModes + `.mode` transactions (keeps undo, persisted choice, planner coordination, OSD).
- D hardware checks: single-mode HiDPI creation + 2× fallback; applySettings on a live virtual; virtuals after lock/sleep/FUS; EDID chromaticity on Apple silicon; AppleClamshellState; base-M3/iMac hazard list; host footprint.
- D limitations: lid state read at plan time; no ICC fallback for primaries; "Disconnect on lock" ignores the screen saver; "Stream onto" associations only prompt.

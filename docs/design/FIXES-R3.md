# Review round 3 (cross-process audit) — fixes (lead)

Audit of feature/displays @b511bdb: no blocker; the guard protocol fix holds. One fix agent owns all
items below and may edit any team's files (not lead files except where noted).

1. **Major: `--yes` does nothing.** Add `skipConfirmation` to `TransactionRequest` (B's TransactionTypes),
   set it from the CLI request in every trial handler (ResolutionController, ArrangementController,
   PanelPropsController, PowerController, LayoutsController, PIP native-mode if applicable), and only when
   the user setting "Let commands skip confirmation" is on. `runTrial` then keeps right after settle; the
   guard is still armed and journaled exactly as for a panel trial. Kit test for the decision.
2. Off-only verbs refuse display number 1: `requestsTurningOn` checks only the first argument.
3. VirtualHostsService callbacks keyed by host object/serial, not spec id; clear `retiring` only in
   `hostExited`.
4. HelperSpawner: on exit, drain the stdout descriptor to EOF/EAGAIN and deliver those lines before `onExit`.
5. Exit status 65 (protocol mismatch) → "Restart Snaptic to finish updating", no respawn (guard and
   virtual hosts).
6. Don't pass `--journal-dir ""`; omit the flag when there's no directory (and the guard must cope).
7. Guard message size: parent refuses to encode a message over `LineSplitter.maxLine` (and/or lower
   `maxUndoOps`); worst-case encoding test.
8. Backup import merges arrays of objects element-wise by `id`, keeping current values of stripped fields
   (layout trust etc.). Kit test round-trip: export → import of your own backup changes nothing.
9. OSD broadcast immediate path clears `pendingBroadcast` and cancels `broadcastWork`; ≤10/s holds.
10. Docs/CLI consistency: `mode favorite N [display]` (handler matches README), README client wait = 90 s,
    `--json` output for mode/layout/virtual/pip list/ddc/set verbs and the client's own errors, and `mode …`
    trial verbs await the outcome and exit 0 / 6 accordingly. Update README.md (lead file — allowed).

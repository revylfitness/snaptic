import AppKit
import SnapticKit

// Lid-closed mode, app side (owner: T-lid-app; PLAN 0.3.1 B3.0, B3.1, B3.3): the single-flight state machine (the only
// writer of `AwakeRuntimeState.lidMode`, lint L16), the journal and beacon, the osascript spawn (one of the two callers
// of `HelperSpawner.spawnAdminScript`, lint L18), verification, the heartbeat and liveness checks, display sleep while
// the lid is shut, and every way the mode ends.
//
// Step 0 stub: never turns on.

@MainActor final class LidClosedController {
    /// Weak: controllers never keep the context strongly.
    weak var context: AwakeContext?

    init() {}
}

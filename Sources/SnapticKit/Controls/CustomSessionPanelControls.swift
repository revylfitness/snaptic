import Foundation

// CustomSessionPanel's controls (owner: G; PLAN 0.3 §5.3, R5-9): the "Custom…" and "Add Time…" panel.

package enum CustomSessionPanelControls: ControlTable {
    package static let surface = "awake.custom"

    package static let controls: [ControlSpec] = [
        ControlSpec("awake.custom.start", .button, keys: ["sessions.lastCustomSeconds"]),
        ControlSpec("awake.custom.cancel", .button),
    ]
}

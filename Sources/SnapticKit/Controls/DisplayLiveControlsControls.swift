import Foundation

// The floating Displays panel (owner F; PLAN 0.3 §5.6): its own buttons. Its live rows are the root page's shared
// rows (`DisplayLiveControls`); on the root page they carry the root page's ids.

package enum DisplayLiveControlsControls: ControlTable {
    package static let surface = "displays.panel"

    package static let controls: [ControlSpec] = [
        // One group per display: Brightness, Volume + Mute, Resolution, Input (the 0.2 Overview card's live rows,
        // whose homes are the root page and Hardware Controls).
        ControlSpec("displays.panel.display", .list, when: [.module(.displays)]),
        // "⋯" pops the display's menu content.
        ControlSpec("displays.panel.more", .button, when: [.module(.displays), .perItem("display")]),
        ControlSpec("displays.panel.resume", .statusAction, when: [.state(.automationPaused)]),
        ControlSpec("displays.panel.identify", .button, when: [.module(.displays)]),
        ControlSpec("displays.panel.restoreAll", .button, when: [.module(.displays)]),
        ControlSpec("displays.panel.settings", .button, when: [.module(.displays)]),
    ]
}

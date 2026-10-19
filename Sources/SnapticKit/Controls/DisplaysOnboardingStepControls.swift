import Foundation

// Onboarding's Displays step (owner F; PLAN 0.3 §4.7): the feature chips, with "Hide the menu bar icon" (keys chip)
// and "Turn on Sharper Text" (sharper-text chip) under them. Applied by Onboarding's primary button.

package enum DisplaysOnboardingStepControls: ControlTable {
    package static let surface = "onboarding.displays"

    package static let controls: [ControlSpec] = [
        ControlSpec("onboarding.displays.chips", .list, when: [.module(.displays)],
                    replaces: ["l.onboarding.displayChips", "l.onboarding.hideMenuIcon", "l.onboarding.smartHiDPI"],
                    keys: ["features"]),
    ]
}

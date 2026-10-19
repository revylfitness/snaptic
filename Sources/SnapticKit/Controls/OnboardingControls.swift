import Foundation

/// Onboarding (H; PLAN 0.3 §4.7): Choose modules. The Displays chips are F's (`onboarding.displays`). 0.3.1 E1a: the
/// "Keep Snaptic Up to Date" step's two buttons (either one advances).
package enum OnboardingControls: ControlTable {
    package static let surface = "onboarding"
    package static let controls: [ControlSpec] = [
        ControlSpec("onboarding.modules", .list, when: [.perItem("module")], replaces: ["l.onboarding.modules"],
                    keys: ["modules.*.enabled"]),
        ControlSpec("onboarding.updates.check", .button),
        ControlSpec("onboarding.updates.notNow", .button),
    ]
}

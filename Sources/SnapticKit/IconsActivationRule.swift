import Foundation

// The activation-policy rule (lead; PLAN 0.4 H9, §4.7). `Core/ActivationPolicyController` (A4) owns
// `setActivationPolicy` and `NSApp.activate`; this is the pure part it asks:
//
//   regular ⇔ settingsOpen ∨ onboardingOpen ∨ (fullBarOnExpand ∧ expanded ∧ expandCause ≠ hover ∧ ¬switcherPanelOpen)
//
// Leaving `.regular` waits until no reason is held and no Snaptic window is visible or key, so a confirm panel or a
// save panel never loses its menu bar under the user.

package enum IconsAppPolicy: String, CaseIterable, Sendable {
    case regular
    case accessory
}

/// What expanded the bar. Only a click, the shortcut, the menu or the CLI takes the full menu bar (§4.7).
package enum IconsExpandCause: String, CaseIterable, Sendable {
    case click
    case shortcut
    case menu
    case cli
    case hiddenList
    case hover
    /// Launch, the timer, a monitor, a fail-safe: nothing a person asked for in that moment.
    case other

    package init(_ source: IconsIntentSource?) {
        switch source {
        case .click: self = .click
        case .shortcut: self = .shortcut
        case .menu: self = .menu
        case .cli: self = .cli
        case .hiddenList: self = .hiddenList
        case .hover: self = .hover
        case .timer, .launch, .settings, .monitor, nil: self = .other
        }
    }

    package var takesFullBar: Bool {
        switch self {
        case .click, .shortcut, .menu, .cli: true
        case .hiddenList, .hover, .other: false
        }
    }
}

package struct IconsActivationFacts: Equatable, Sendable {
    package var settingsOpen = false
    package var onboardingOpen = false
    package var fullBarOnExpand = false
    /// Icons are shown: expanded, or calibrating on the way to a collapse, so a collapse that fails keeps the reason.
    package var expanded = false
    package var expandCause: IconsExpandCause = .other
    /// The Window Switcher panel is open (a `ModuleHost` query, P-24).
    package var switcherPanelOpen = false
    /// Any Snaptic window is on screen: a confirm or save panel, Sparkle, the PIP editor and the like.
    package var snapticWindowVisible = false
    package var snapticWindowKey = false
    /// A transient `activate(reason:)` the controller still holds.
    package var otherReasonHeld = false

    package init() {}
}

package enum IconsActivationRule {
    /// The full-menu-bar reason (§4.7).
    package static func fullBar(_ f: IconsActivationFacts) -> Bool {
        f.fullBarOnExpand && f.expanded && f.expandCause.takesFullBar && !f.switcherPanelOpen
    }

    /// The right-hand side of H9.
    package static func wantsRegular(_ f: IconsActivationFacts) -> Bool {
        f.settingsOpen || f.onboardingOpen || fullBar(f)
    }

    /// The policy to set. Promotion is immediate; demotion waits for every reason and every Snaptic window.
    package static func next(current: IconsAppPolicy, _ f: IconsActivationFacts) -> IconsAppPolicy {
        if wantsRegular(f) { return .regular }
        guard current == .regular else { return .accessory }
        let holding = f.otherReasonHeld || f.snapticWindowVisible || f.snapticWindowKey
        return holding ? .regular : .accessory
    }

    /// Activation is skipped while the Window Switcher panel is open.
    package static func mayActivate(_ f: IconsActivationFacts) -> Bool { !f.switcherPanelOpen }

    /// When the full-bar reason ends, give focus back to the app that had it, unless another app took focus since
    /// the expand or Snaptic still shows a window.
    package static func reactivateRemembered(hadRemembered: Bool, otherAppActivatedSinceExpand: Bool,
                                             _ f: IconsActivationFacts) -> Bool {
        hadRemembered && !otherAppActivatedSinceExpand && !f.snapticWindowVisible && !f.snapticWindowKey
            && !f.settingsOpen && !f.onboardingOpen
    }
}

import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import SnapticKit

// Activity simulation (owner: J; PLAN 0.3 §2.9, §3.3, N10, security L1/M2). The only file allowed to declare user
// activity, to release that declaration's id, and to post CGEvents (lint L1/L2). ActivityController decides
// (ActivityPolicy, in Kit) and calls `perform` once per interval; this file only acts:
// - `declare`: IOPMAssertionDeclareUserActivity("Snaptic: activity", kIOPMUserActiveLocal), reusing one id, released by
//   `stop()`. It turns the display on, so the policy never asks for it while the displays are asleep.
// - `nudge`: one mouseMoved of +1 pt and one back to the current location, from a private-state source via the HID
//   tap, tagged 'SNPT' in eventSourceUserData so Snaptic's own taps ignore it; CGPreflightPostEventAccess() before every
//   post. Never a key, click or scroll event. A nudge that can't post degrades to a declaration.
// The last 10 action instants (continuous clock) feed IdleMath so our own actions never count as real input.

@MainActor final class ActivitySimulator: AwakeServiceLifecycle {
    /// 'SNPT' (eventSourceUserData of every posted event).
    static let eventTag: Int64 = 0x534E_5054
    static let declarationName = "Snaptic: activity"

    weak var context: AwakeContext?
    /// Continuous times, last 10, for IdleMath.
    private(set) var recentNudges: [Double] = []
    /// Continuous times, last 10, for IdleMath.
    private(set) var recentDeclarations: [Double] = []
    /// What the last `perform` did (`.skip` after `stop()`): the controller's "Appearing active" / "Moving the pointer".
    private(set) var lastAction: ActivityDecision = .skip

    private var active = false
    private var declarationID: IOPMAssertionID = 0
    private var holdsDeclaration = false

    init() {}

    /// Accessibility preflight for posting events (no prompt).
    var canPostEvents: Bool { CGPreflightPostEventAccess() }

    /// ActivityController calls it once per interval. `.skip` releases a held declaration, so nothing "user active"
    /// outlives the conditions that allowed it.
    func perform(_ decision: ActivityDecision) {
        guard active else { return }
        switch decision {
        case .skip:
            stop()
        case .declare:
            lastAction = declare() ? .declare : .skip
        case .nudge:
            if nudge() {
                // A nudge already resets the idle timers; drop a declaration left from an earlier interval.
                releaseDeclaration()
                lastAction = .nudge
            } else {
                lastAction = declare() ? .declare : .skip
            }
        }
    }

    /// Releases the DeclareUserActivity id. Idempotent.
    func stop() {
        releaseDeclaration()
        lastAction = .skip
    }

    /// Points from the pointer to the nearest edge of the display it is on (the policy keeps nudges > 2 pt away from
    /// hot corners, the Dock and a full-screen menu bar); nil when no display contains the pointer.
    func pointerEdgeDistance() -> Double? {
        let p = NSEvent.mouseLocation
        guard let frame = NSScreen.screens.map(\.frame).first(where: { NSPointInRect(p, $0) }) else { return nil }
        let d = min(p.x - frame.minX, frame.maxX - p.x, p.y - frame.minY, frame.maxY - p.y)
        return d.isFinite ? Double(max(0, d)) : nil
    }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
    }

    func deactivate() {
        guard active else { return }
        stop()
        active = false
        recentNudges = []
        recentDeclarations = []
        context = nil
    }

    // MARK: Acting

    private func declare() -> Bool {
        var id = holdsDeclaration ? declarationID : IOPMAssertionID(0)
        let result = IOPMAssertionDeclareUserActivity(Self.declarationName as CFString, kIOPMUserActiveLocal, &id)
        guard result == 0 else {
            // A stale id (released by powerd) is retried once with a fresh one.
            guard holdsDeclaration else { return false }
            holdsDeclaration = false
            declarationID = 0
            return declare()
        }
        declarationID = id
        holdsDeclaration = true
        recentDeclarations = IdleMath.remembering(AwakeSourceClock.now(), in: recentDeclarations)
        return true
    }

    private func releaseDeclaration() {
        guard holdsDeclaration else { return }
        IOPMAssertionRelease(declarationID)
        holdsDeclaration = false
        declarationID = 0
    }

    /// +1 pt, then back. False when posting isn't allowed or the events can't be built.
    private func nudge() -> Bool {
        guard CGPreflightPostEventAccess(), let source = CGEventSource(stateID: .privateState),
              let here = CGEvent(source: nil)?.location else { return false }
        source.userData = Self.eventTag
        let there = CGPoint(x: here.x + 1, y: here.y)
        guard let out = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: there,
                                mouseButton: .left),
              let back = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: here,
                                 mouseButton: .left) else { return false }
        out.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        back.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        // Re-checked right before posting: the grant can be revoked at any time.
        guard CGPreflightPostEventAccess() else { return false }
        out.post(tap: .cghidEventTap)
        back.post(tap: .cghidEventTap)
        recentNudges = IdleMath.remembering(AwakeSourceClock.now(), in: recentNudges)
        return true
    }
}

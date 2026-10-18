import AppKit
import IOKit.pwr_mgt
import notify
import SnapticKit

// The only IOPMAssertionCreate*/Release caller for sleep assertions (owner: G; PLAN 0.3 §2.4, lint L1). At most one
// sleep assertion exists at any time, named with fixed vocabulary ("Snaptic: keeping your Mac awake", Details
// "manual"/"automatic"; security M6). A change of type, details or deadline creates the new assertion first and then
// releases the old one, so there is never a gap and IOPMAssertionSetProperty is never needed. A deadline becomes
// TimeoutSeconds + TimeoutAction "TimeoutActionRelease" at create: a backstop only, the app ends sessions itself.
// The PreventDiskIdle assertion (Drive Alive writing) is separate, has no timeout and is never swapped.

@MainActor final class AssertionManager: AwakeServiceLifecycle {
    private(set) var current: AwakeAssertionPlan = .inactive
    private(set) var lastError: Int32?
    weak var context: AwakeContext?

    /// Debug counters (§6.5): every create and release, and creates that failed.
    private(set) var createdCount = 0
    private(set) var releasedCount = 0
    private(set) var failureCount = 0
    /// Sleep assertions alive now: 0 or 1.
    var liveCount: Int { sleepID == 0 ? 0 : 1 }

    /// Runs when powerd reports an assertion timeout (`com.apple.system.powermanagement.assertions.timeout`): the
    /// session controller checks expiry first, then arbitrates, then verifies.
    var onTimeout: (@MainActor () -> Void)?

    private var sleepID: IOPMAssertionID = 0
    private var diskID: IOPMAssertionID = 0
    private var timeoutToken: Int32 = 0
    private var timeoutRegistered = false

    private static let timeoutNotification = "com.apple.system.powermanagement.assertions.timeout"

    init() {}

    // MARK: Plans

    /// Idempotent. Swaps only when `AwakeArbiter.needsSwap` (or the assertion vanished). Returns false when a needed
    /// create failed (the old assertion, if any, stays until the caller turns it off) or when the deadline already
    /// passed (nothing is created; the caller ends the session `.timeUp`).
    @discardableResult func apply(_ plan: AwakeAssertionPlan, now: ClockNow) -> Bool {
        setDiskIdle(plan.preventDiskIdle)
        guard plan.type != .off else {
            releaseSleep()
            current = AwakeAssertionPlan(type: .off, details: plan.details, deadline: nil,
                                         preventDiskIdle: plan.preventDiskIdle)
            return true
        }
        if let d = plan.deadline, !(d.isFinite && d > now.continuous) {
            releaseSleep()
            current = AwakeAssertionPlan(type: .off, details: plan.details, deadline: nil,
                                         preventDiskIdle: plan.preventDiskIdle)
            return false
        }
        guard sleepID == 0 || AwakeArbiter.needsSwap(current: current, next: plan) else {
            current.preventDiskIdle = plan.preventDiskIdle
            return true
        }
        guard let created = create(plan, now: now) else { return false }
        let old = sleepID
        sleepID = created
        if old != 0 { release(old) }
        current = plan
        assert(liveCount <= 1, "Awake holds at most one sleep assertion")
        return true
    }

    func releaseAll() {
        releaseSleep()
        setDiskIdle(false)
        current = .inactive
    }

    /// Checks our assertion still exists (IOPMAssertionCopyProperties): on wake, on powerd's timeout notification
    /// and every 5 minutes while active. A vanished assertion is re-created once for an active plan whose deadline is
    /// nil or in the future; only a failed re-create returns false.
    func verify(now: ClockNow) -> Bool {
        guard current.type != .off, sleepID != 0 else { return true }
        if exists(sleepID) { return true }
        sleepID = 0
        if let d = current.deadline, !(d.isFinite && d > now.continuous) {
            current = AwakeAssertionPlan(type: .off, details: current.details, deadline: nil,
                                         preventDiskIdle: current.preventDiskIdle)
            return true
        }
        guard let created = create(current, now: now) else {
            current = AwakeAssertionPlan(type: .off, details: current.details, deadline: nil,
                                         preventDiskIdle: current.preventDiskIdle)
            return false
        }
        sleepID = created
        return true
    }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        self.context = context
        guard !timeoutRegistered else { return }
        var token: Int32 = 0
        let status = notify_register_dispatch(Self.timeoutNotification, &token, DispatchQueue.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTimeout?() }
        }
        if status == 0 {
            timeoutToken = token
            timeoutRegistered = true
        }
    }

    func deactivate() {
        releaseAll()
        if timeoutRegistered {
            notify_cancel(timeoutToken)
            timeoutRegistered = false
        }
        context = nil
    }

    // MARK: IOKit

    private func create(_ plan: AwakeAssertionPlan, now: ClockNow) -> IOPMAssertionID? {
        var properties: [String: Any] = [
            "AssertType": plan.type == .display ? "PreventUserIdleDisplaySleep" : "PreventUserIdleSystemSleep",
            "AssertName": AwakeAssertionPlan.name,
            "Details": plan.details.rawValue,
            "AssertLevel": 255,
        ]
        if let d = plan.deadline {
            // 0 would mean "no timeout".
            properties["TimeoutSeconds"] = max(1, Int((d - now.continuous).rounded(.up)))
            properties["TimeoutAction"] = "TimeoutActionRelease"
        }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
        guard result == kIOReturnSuccess, id != 0 else {
            lastError = result
            failureCount += 1
            EventLog.shared.record(AwakeLogEvent.assertionFailed)
            return nil
        }
        lastError = nil
        createdCount += 1
        return id
    }

    private func release(_ id: IOPMAssertionID) {
        IOPMAssertionRelease(id)
        releasedCount += 1
    }

    private func releaseSleep() {
        guard sleepID != 0 else { return }
        release(sleepID)
        sleepID = 0
    }

    private func setDiskIdle(_ on: Bool) {
        if on, diskID == 0 {
            let properties: [String: Any] = [
                "AssertType": "PreventDiskIdle",
                "AssertName": AwakeAssertionPlan.name,
                "Details": AwakeAssertionDetails.manual.rawValue,
                "AssertLevel": 255,
            ]
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithProperties(properties as CFDictionary, &id) == kIOReturnSuccess, id != 0 {
                diskID = id
            }
        } else if !on, diskID != 0 {
            IOPMAssertionRelease(diskID)
            diskID = 0
        }
    }

    private func exists(_ id: IOPMAssertionID) -> Bool {
        guard let properties = IOPMAssertionCopyProperties(id) else { return false }
        _ = properties.takeRetainedValue()
        return true
    }
}

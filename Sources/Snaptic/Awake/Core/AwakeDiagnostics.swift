import AppKit
import SnapticKit

// The Awake section of the shared diagnostics report (owner: G; PLAN 0.3 §3.6): effective features, what governs,
// the assertion and its errors, the guard state, the services the current state needs, counts of holds, rules and
// conditions by kind, Drive Alive's volume count, the `Awake.disable.*` keys that are set and the Awake event counts
// from EventLog; since 0.3.1 lid-closed mode's state and whether sleep was left off (states only). Never names, bundle
// ids, pids, volume names, addresses or times (Kit's AwakeDiagnosticsReport formats it).

@MainActor final class AwakeDiagnostics {
    init() {}

    /// `recovery`: the host's (B3.4), so a leftover is reported while Awake is stopped too.
    func lines(_ context: AwakeContext?, recovery: LidRecoveryState? = nil) -> [String] {
        AwakeDiagnosticsReport.lines(facts(context, recovery: recovery))
    }

    func facts(_ context: AwakeContext?, recovery: LidRecoveryState? = nil) -> AwakeDiagnosticsFacts {
        let leftover = (recovery ?? context?.host.lidRecovery)?.recovery == .leftover
        guard let ctx = context else {
            return AwakeDiagnosticsFacts(effective: [], governing: nil, kind: nil, assertion: .off, assertionErrors: 0,
                                         guardHolding: nil, activeServices: [], holds: 0, rules: 0, conditionsByKind: [:],
                                         eventCounts: EventLog.shared.awakeCounts, drives: 0,
                                         killSwitches: AwakeModule.readKillSwitches(), lid: nil, lidLeftover: leftover)
        }
        let rt = ctx.runtime
        let status = AwakeStatusFacts(governing: rt.governing, holds: rt.holds, now: AwakeModule.clockNow())
        let triggers = ctx.config.value.triggers.triggers
        var kinds: [AwakeCriterionKind: Int] = [:]
        for t in triggers { for e in t.criteria { kinds[e.criterion.kind, default: 0] += 1 } }
        let needed = AwakeFeatureGraph.requiredServices(effective: rt.effectiveFeatures,
                                                        criteria: TriggerEngine.requiredKinds(triggers),
                                                        dynamic: ctx.sessions.dynamicNeeds)
        let services = AwakeFeatureGraph.activationOrder.filter { needed.contains($0) }
        // The lid row's state, as the menus show it (nil while the feature isn't effective).
        let lid = AwakeLidMenuFacts.make(available: rt.isEffective(.lidClosed), mode: rt.lidMode,
                                         recovery: ctx.host.lidRecovery?.recovery ?? .nothing, sessionTakesMode: false,
                                         presets: [])?.state
        return AwakeDiagnosticsFacts(effective: rt.effectiveFeatures, governing: status.source, kind: status.kind,
                                     assertion: ctx.assertions.current.type, assertionErrors: ctx.assertions.failureCount,
                                     guardHolding: ctx.sessions.guardMemory.holding, activeServices: services,
                                     holds: rt.holds.count, rules: triggers.count, conditionsByKind: kinds,
                                     eventCounts: EventLog.shared.awakeCounts,
                                     drives: ctx.config.value.drives.enabledVolumes.count,
                                     killSwitches: AwakeModule.readKillSwitches(), lid: lid, lidLeftover: leftover)
    }
}

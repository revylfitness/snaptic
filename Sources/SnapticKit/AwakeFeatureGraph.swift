import Foundation

// Awake ids and feature graph (lead; 0.3 §2.2). Data plus pure resolution logic, unit-tested on Linux.

/// User-facing Awake features. Raw values are persisted.
package enum AwakeFeature: String, Codable, CaseIterable, Sendable {
    case sessions, presets, batteryGuard, thermalGuard, indicator
    case triggers, activity, pointerNudge, driveAlive, history, shortcuts, commandLine
    /// 0.3.1 B5: keep awake with the lid closed (opt-in; asks for an administrator password each time).
    case lidClosed
}

/// One controller class per id.
package enum AwakeControllerID: String, Codable, CaseIterable, Sendable {
    case sessions, guards, triggers, activity, driveAlive, indicator, history, automation
}

/// Awake services, activated by need (features, trigger criteria, dynamic needs).
package enum AwakeServiceID: String, Codable, CaseIterable, Sendable {
    case assertions, power, system, apps, displays, usb, volumes, audio, cpu, disk, idle, network, bluetooth
    case activity, driveAlive, process
}

/// Services a running session or open UI needs beyond features and trigger criteria (code M7).
package struct AwakeDynamicNeeds: OptionSet, Hashable, Sendable {
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue }
    /// whileApp session, app picker open.
    package static let apps = AwakeDynamicNeeds(rawValue: 1 << 0)
    /// keepOnWhileActive governs.
    package static let idle = AwakeDynamicNeeds(rawValue: 1 << 1)
    /// untilIdle session: cpu + disk + network.
    package static let taskQuiet = AwakeDynamicNeeds(rawValue: 1 << 2)
    /// Any hold exists: ProcessWatch.
    package static let process = AwakeDynamicNeeds(rawValue: 1 << 3)
}

/// Static description of one Awake feature.
package struct AwakeFeatureSpec: Sendable {
    package let defaultState: FeatureDefault
    package let beta: Bool
    /// Turned on together with this feature.
    package let requiresAll: [AwakeFeature]
    package let uses: Set<AwakeServiceID>
    package let controller: AwakeControllerID
    package let permissions: Set<Permission>

    package init(_ d: FeatureDefault, beta: Bool = false, all: [AwakeFeature] = [], uses: Set<AwakeServiceID> = [],
                 controller: AwakeControllerID, permissions: Set<Permission> = []) {
        defaultState = d
        self.beta = beta
        requiresAll = all
        self.uses = uses
        self.controller = controller
        self.permissions = permissions
    }
}

package enum AwakeFeatureGraph {
    /// The §2.2 table; total (tested). Computed (code sig).
    package static var specs: [AwakeFeature: AwakeFeatureSpec] {
        [
            .sessions: AwakeFeatureSpec(.always, uses: [.assertions, .power, .system], controller: .sessions),
            .presets: AwakeFeatureSpec(.always, all: [.sessions], controller: .sessions),
            .batteryGuard: AwakeFeatureSpec(.always, uses: [.power], controller: .guards),
            .thermalGuard: AwakeFeatureSpec(.always, uses: [.power], controller: .guards),
            .indicator: AwakeFeatureSpec(.always, controller: .indicator),
            .triggers: AwakeFeatureSpec(.optIn, all: [.sessions], controller: .triggers),
            .activity: AwakeFeatureSpec(.optIn, all: [.sessions], uses: [.activity, .idle, .system], controller: .activity),
            .pointerNudge: AwakeFeatureSpec(.experimental, all: [.activity], uses: [.activity], controller: .activity,
                                            permissions: [.accessibility]),
            .driveAlive: AwakeFeatureSpec(.optIn, uses: [.volumes, .driveAlive, .power], controller: .driveAlive),
            .history: AwakeFeatureSpec(.standard, all: [.sessions], controller: .history),
            .shortcuts: AwakeFeatureSpec(.standard, all: [.sessions], controller: .automation),
            .commandLine: AwakeFeatureSpec(.standard, all: [.sessions], uses: [.process], controller: .automation),
            .lidClosed: AwakeFeatureSpec(.optIn, all: [.sessions], uses: [.power, .system], controller: .sessions),
        ]
    }

    package static func spec(_ f: AwakeFeature) -> AwakeFeatureSpec {
        specs[f] ?? AwakeFeatureSpec(.optIn, controller: .sessions)
    }

    /// The saved choice, or the default when there is none (`always` is always on).
    package static func rawState(_ f: AwakeFeature, in raw: [AwakeFeature: Bool]) -> Bool {
        let d = spec(f).defaultState
        if d == .always { return true }
        return raw[f] ?? (d == .standard)
    }

    /// Per-feature kill switches never remove these (tested with every kill switch set); `Modules.disable.awake`
    /// stops the whole module instead (N14). `.indicator`: R5 (N11).
    package static let unkillable: Set<AwakeFeature> = [.sessions, .batteryGuard, .thermalGuard, .indicator]

    package static let safeModeRemoves: Set<AwakeFeature> = [.triggers, .pointerNudge, .driveAlive, .activity, .lidClosed]

    /// raw − (kill switches − unkillable) − unavailable − Safe Mode removals, closed over requirements: a feature
    /// whose requirement is missing is removed too.
    package static func resolve(raw: [AwakeFeature: Bool], killSwitches: Set<AwakeFeature>, safeMode: Bool,
                                unavailable: Set<AwakeFeature>) -> Set<AwakeFeature> {
        var on = Set(AwakeFeature.allCases.filter { rawState($0, in: raw) })
        on.subtract(killSwitches.subtracting(unkillable))
        on.subtract(unavailable)
        if safeMode { on.subtract(safeModeRemoves) }
        var changed = true
        while changed {
            changed = false
            for f in on where !spec(f).requiresAll.allSatisfy({ on.contains($0) }) {
                on.remove(f)
                changed = true
            }
        }
        return on
    }

    /// The raw choices with `f` and its requirements turned on; nil when `f` or one of its requirements is not
    /// available (or killed, which callers pass as unavailable; code minor 9).
    package static func enabling(_ f: AwakeFeature, raw: [AwakeFeature: Bool],
                                 available: Set<AwakeFeature>) -> [AwakeFeature: Bool]? {
        var result = raw
        var pending = [f]
        var seen = Set<AwakeFeature>()
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            guard available.contains(next) else { return nil }
            result[next] = true
            pending.append(contentsOf: spec(next).requiresAll)
        }
        return result
    }

    /// The source a trigger criterion needs; `schedule` has none (TriggerController's Ticker; consistency M5).
    package static func services(of kind: AwakeCriterionKind) -> Set<AwakeServiceID> {
        switch kind {
        case .app: return [.apps]
        case .display: return [.displays]
        case .power: return [.power]
        case .schedule: return []
        case .cpu: return [.cpu]
        case .audio: return [.audio]
        case .idle: return [.idle]
        case .volume: return [.volumes]
        case .usb: return [.usb]
        case .network, .networkActivity: return [.network]
        case .bluetooth: return [.bluetooth]
        }
    }

    package static func services(of needs: AwakeDynamicNeeds) -> Set<AwakeServiceID> {
        var s = Set<AwakeServiceID>()
        if needs.contains(.apps) { s.insert(.apps) }
        if needs.contains(.idle) { s.insert(.idle) }
        if needs.contains(.taskQuiet) { s.formUnion([.cpu, .disk, .network]) }
        if needs.contains(.process) { s.insert(.process) }
        return s
    }

    /// Features' services ∪ the enabled triggers' criterion sources (only while `triggers` is effective) ∪ dynamic
    /// needs. Nothing runs while no feature is effective.
    package static func requiredServices(effective: Set<AwakeFeature>, criteria: Set<AwakeCriterionKind>,
                                         dynamic: AwakeDynamicNeeds) -> Set<AwakeServiceID> {
        guard !effective.isEmpty else { return [] }
        var s = Set<AwakeServiceID>()
        for f in effective { s.formUnion(spec(f).uses) }
        if effective.contains(.triggers) {
            for kind in criteria { s.formUnion(services(of: kind)) }
        }
        s.formUnion(services(of: dynamic))
        return s
    }

    /// assertions, power, system, then the sources (apps … bluetooth, process), activity, driveAlive.
    package static var activationOrder: [AwakeServiceID] {
        [.assertions, .power, .system, .apps, .displays, .usb, .volumes, .audio, .cpu, .disk, .idle, .network,
         .bluetooth, .process, .activity, .driveAlive]
    }

    /// Permissions a feature needs.
    package static func permissions(_ f: AwakeFeature) -> Set<Permission> { spec(f).permissions }

    /// Controller of a feature.
    package static func controller(of f: AwakeFeature) -> AwakeControllerID { spec(f).controller }
}

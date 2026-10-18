import Foundation

// The Drives page as data (owner: J; PLAN 0.3 §2.9, §3.4, §4.3 Drives). Which mounted volumes the page lists, what
// each row says and whether its switch can be used, from the live mounts, the Drive Alive config, the service's
// per-volume results and the page's own in-flight first writes. Pure and tested; DrivesPage only renders it.

/// One mounted volume as VolumeMonitor saw it (nil `uuid`: the volume has no volume UUID).
package struct DriveCandidate: Equatable, Sendable {
    package var uuid: VolumeUUIDKey?
    package var name: String
    package var facts: DriveAlivePolicy.VolumeFacts

    package init(uuid: VolumeUUIDKey?, name: String, facts: DriveAlivePolicy.VolumeFacts) {
        self.uuid = uuid
        self.name = name
        self.facts = facts
    }
}

/// DriveAliveService's last result for a volume (this run).
package struct DriveWriteResult: Equatable, Sendable {
    package var lastWrite: Date?
    package var lastError: DriveAliveError?

    package init(lastWrite: Date?, lastError: DriveAliveError?) {
        self.lastWrite = lastWrite
        self.lastError = lastError
    }
}

/// Why a listed drive can't be kept awake (its switch is disabled).
package enum DriveUnsupportedReason: Equatable, Sendable {
    case readOnly
    /// The f_fstypename shown to the user ("NTFS"), already cleaned.
    case fileSystem(String)
    case timeMachine
    case noIdentifier
    case other
}

package enum DriveRowStatus: Equatable, Sendable {
    /// Can be turned on.
    case off
    /// The UI-confirmed first write is running (the Removable Volumes prompt may be up).
    case firstWriteRunning
    /// On, but the first write hasn't happened (turned on outside Settings, or it was interrupted).
    case needsFirstWrite
    case failed(DriveAliveError)
    /// On and written whenever Drive Alive runs.
    case active(lastWrite: Date?)
    /// On; nothing governs (and "Also when no session is running" is off), or only command-line holds govern.
    case waitingForSession
    /// On; the battery or heat guards stop background work.
    case paused
    /// On, but not mounted now.
    case notConnected
    case unsupported(DriveUnsupportedReason)
}

package struct DriveRow: Equatable, Identifiable, Sendable {
    /// The volume UUID, or "path:<name>" for a listed volume without one.
    package var id: String
    package var uuid: VolumeUUIDKey?
    package var name: String
    package var isOn: Bool
    /// The switch works: eligible, or on (so it can always be turned off).
    package var canToggle: Bool
    package var status: DriveRowStatus

    package init(id: String, uuid: VolumeUUIDKey?, name: String, isOn: Bool, canToggle: Bool, status: DriveRowStatus) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.isOn = isOn
        self.canToggle = canToggle
        self.status = status
    }

    /// The row offers Try Again / Write Now (a UI-confirmed first write).
    package var offersWrite: Bool {
        switch status {
        case .needsFirstWrite, .failed: return isOn && uuid != nil
        default: return false
        }
    }
}

package enum DrivesPageModel {
    /// Everything the rows depend on.
    package struct Inputs: Equatable, Sendable {
        /// nil while the volume list isn't known (Drive Alive or Awake off, first scan running).
        package var mounted: [DriveCandidate]?
        package var config: DriveAliveConfig
        package var results: [VolumeUUIDKey: DriveWriteResult]
        package var firstWriteRunning: Set<VolumeUUIDKey>
        /// The page's own first-write failures (the service reports them only for tracked volumes).
        package var firstWriteFailures: [VolumeUUIDKey: DriveAliveError]
        /// `DriveAlivePolicy.shouldWrite` for a confirmed volume with background work allowed: a session governs
        /// that isn't from the command line, or "Also when no session is running" is on.
        package var sessionAllowsWrites: Bool
        /// `AwakeGuards.allowsBackgroundWork` (false while unknown).
        package var backgroundWorkAllowed: Bool

        package init(mounted: [DriveCandidate]?, config: DriveAliveConfig, results: [VolumeUUIDKey: DriveWriteResult] = [:],
                     firstWriteRunning: Set<VolumeUUIDKey> = [], firstWriteFailures: [VolumeUUIDKey: DriveAliveError] = [:],
                     sessionAllowsWrites: Bool, backgroundWorkAllowed: Bool) {
            self.mounted = mounted
            self.config = config
            self.results = results
            self.firstWriteRunning = firstWriteRunning
            self.firstWriteFailures = firstWriteFailures
            self.sessionAllowsWrites = sessionAllowsWrites
            self.backgroundWorkAllowed = backgroundWorkAllowed
        }
    }

    /// A mounted volume the page shows: a local, browsable volume on an external physical disk, outside the boot
    /// container. Internal, system, network, hidden and disk-image volumes are never listed (hardware can't do it →
    /// the row is omitted, §4.2); listed ones that still aren't eligible show why.
    package static func isListed(_ v: DriveAlivePolicy.VolumeFacts) -> Bool {
        !v.isInternal && !v.isRootFileSystem && v.isLocal && !v.isDiskImage && v.isBrowsable && !v.inBootContainer
    }

    /// nil when the volume is eligible.
    package static func unsupportedReason(_ c: DriveCandidate) -> DriveUnsupportedReason? {
        if c.uuid == nil { return .noIdentifier }
        if DriveAlivePolicy.isEligible(c.facts) { return nil }
        if c.facts.isTimeMachine { return .timeMachine }
        if c.facts.isReadOnly { return .readOnly }
        if !DriveAlivePolicy.allowedFileSystems.contains(c.facts.fileSystem) {
            let shown = TextSanitizer.clean(c.facts.fileSystem, maxScalars: 16).uppercased()
            return shown.isEmpty ? .other : .fileSystem(shown)
        }
        return .other
    }

    /// Listed mounts first (by name), then volumes that are on but not connected (by name). A mount that is on is
    /// always listed. Duplicate UUIDs (two mounts reporting one UUID) keep the first.
    package static func rows(_ i: Inputs) -> [DriveRow] {
        let config = i.config
        var rows: [DriveRow] = []
        var seen = Set<VolumeUUIDKey>()
        var seenIDs = Set<String>()
        for c in byName(i.mounted ?? [], name: { $0.name }) {
            let volume = c.uuid.flatMap { config.volumes[$0] }
            let isOn = volume?.enabled == true
            // A volume that is on stays listed even when it no longer qualifies, so it can be turned off.
            guard isListed(c.facts) || isOn else { continue }
            if let uuid = c.uuid, !seen.insert(uuid).inserted { continue }
            let id = c.uuid?.rawValue ?? "path:" + c.name
            guard seenIDs.insert(id).inserted else { continue }
            let reason = unsupportedReason(c)
            let status: DriveRowStatus
            if let reason {
                status = .unsupported(reason)
            } else if let uuid = c.uuid, isOn {
                status = onStatus(uuid, volume: volume, i)
            } else {
                status = .off
            }
            rows.append(DriveRow(id: id, uuid: c.uuid, name: c.name, isOn: isOn, canToggle: reason == nil || isOn,
                                 status: status))
        }
        // Volumes that are on but not mounted stay visible, so they can be turned off (only once the list is known).
        if i.mounted != nil {
            let away = Array(config.volumes.values.filter { $0.value.enabled && !seen.contains($0.key) })
            for (uuid, volume) in byName(away, name: { $0.value.name }) {
                let name = volume.name.isEmpty ? L("Unnamed drive") : volume.name
                rows.append(DriveRow(id: uuid.rawValue, uuid: uuid, name: name, isOn: true, canToggle: true,
                                     status: .notConnected))
            }
        }
        return rows
    }

    private static func onStatus(_ uuid: VolumeUUIDKey, volume: DriveAliveVolume?, _ i: Inputs) -> DriveRowStatus {
        if i.firstWriteRunning.contains(uuid) { return .firstWriteRunning }
        if let error = i.firstWriteFailures[uuid] ?? i.results[uuid]?.lastError { return .failed(error) }
        guard volume?.firstWriteDone == true else { return .needsFirstWrite }
        guard i.backgroundWorkAllowed else { return .paused }
        guard i.sessionAllowsWrites else { return .waitingForSession }
        return .active(lastWrite: i.results[uuid]?.lastWrite)
    }

    private static func byName<T>(_ items: [T], name: (T) -> String) -> [T] {
        items.enumerated().sorted { a, b in
            let order = name(a.element).compare(name(b.element), options: [.caseInsensitive, .numeric])
            return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
        }.map(\.element)
    }

    // MARK: Text

    /// The row's subtitle; `time` formats a write instant ("3:12 PM"). nil = no subtitle.
    package static func statusText(_ status: DriveRowStatus, time: (Date) -> String) -> String? {
        switch status {
        case .off: return nil
        case .firstWriteRunning: return L("Writing to the drive for the first time…")
        case .needsFirstWrite: return L("Waiting for the first write. Click Write Now to start.")
        case .failed(let error): return L("Can’t keep this drive awake: \(reason(error))")
        case .active(let last?): return L("Kept awake. Last write at \(time(last)).")
        case .active(nil): return L("Kept awake.")
        case .waitingForSession: return L("Kept awake while a session runs.")
        case .paused: return L("Paused while the battery is low or your Mac is very hot.")
        case .notConnected: return L("Not connected.")
        case .unsupported(let r): return unsupportedText(r)
        }
    }

    /// The end of "Can't keep this drive awake: …" (one sentence that says what to do).
    package static func reason(_ error: DriveAliveError) -> String {
        switch error {
        case .notEligible: return L("this kind of drive isn’t supported.")
        case .mountChanged: return L("the drive changed since it was connected. Eject it, connect it again, then try again.")
        case .notOurFile: return L("an item named .snaptic-keepalive that Snaptic didn’t create is in the way.")
        case .ioError: return L("writing to it failed. Check the drive, then try again.")
        case .denied: return L("macOS denied access. Allow removable volumes for Snaptic in Privacy & Security, then try again.")
        }
    }

    package static func unsupportedText(_ r: DriveUnsupportedReason) -> String {
        switch r {
        case .readOnly: return L("Can’t keep this drive awake: it’s read-only.")
        case .fileSystem(let fs): return L("Can’t keep this drive awake: its format (\(fs)) isn’t supported.")
        case .timeMachine: return L("Time Machine keeps this drive awake while it backs up.")
        case .noIdentifier: return L("Can’t keep this drive awake: it has no volume identifier.")
        case .other: return L("Can’t keep this drive awake: this kind of drive isn’t supported.")
        }
    }

    /// The Awake page's "Drives ›" value: "Off", "On", "1 drive", "3 drives".
    package static func navigationValue(featureOn: Bool, config: DriveAliveConfig) -> String {
        guard featureOn else { return L("Off") }
        let n = config.enabledVolumes.count
        switch n {
        case 0: return L("On")
        case 1: return L("1 drive")
        default: return L("\(n) drives")
        }
    }

    /// Turning a volume on in the UI: enabled, first write not yet done (the page performs it right away), name kept
    /// fresh. Refused (unchanged) when the 16-volume limit is reached by other enabled volumes.
    package static func turningOn(_ uuid: VolumeUUIDKey, name: String, in config: DriveAliveConfig) -> DriveAliveConfig {
        var c = config
        let others = c.enabledVolumes.subtracting([uuid]).count
        guard others < DriveAliveConfig.maxVolumes else { return config }
        if c.volumes[uuid] == nil && c.volumes.values.count >= DriveAliveConfig.maxVolumes {
            // Make room by forgetting a volume that is off.
            if let spare = c.volumes.values.keys.sorted(by: { $0.rawValue < $1.rawValue })
                .first(where: { c.volumes[$0]?.enabled != true }) {
                c.volumes[spare] = nil
            }
        }
        let clean = TextSanitizer.clean(name, maxScalars: DriveAliveConfig.maxNameScalars)
        c.volumes[uuid] = DriveAliveVolume(name: clean, enabled: true, firstWriteDone: false)
        return c
    }

    /// Turning a volume off in the UI: disabled, so the next turn-on asks for a new UI-confirmed first write.
    package static func turningOff(_ uuid: VolumeUUIDKey, in config: DriveAliveConfig) -> DriveAliveConfig {
        guard var v = config.volumes[uuid] else { return config }
        var c = config
        v.enabled = false
        v.firstWriteDone = false
        c.volumes[uuid] = v
        return c
    }
}

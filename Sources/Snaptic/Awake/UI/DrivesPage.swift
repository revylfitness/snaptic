import SwiftUI
import SnapticKit

// Awake › Drives (owner: J; PLAN 0.3 §4.3 Drives, §2.9, §3.4, security M3). Drive Alive opt-in per volume by UUID:
// - the header switch is `features.driveAlive`;
// - each eligible external volume has a switch; turning one on stores it by UUID and performs the first write right
//   away through `DriveAliveService.firstWrite`, so the Removable Volumes prompt follows the click (never a config
//   write alone; `firstWriteDone` is set only by that write);
// - turning one off removes Snaptic's file from it (`removeKeepAliveFile`);
// - every row says what happens to that drive, and the page says what is written and why.
// The rows come from Kit's DrivesPageModel; this file only renders them and runs the UI actions.
// Route: "awake.drives" (`DrivesPage.route`, the Awake page's "Drives ›" row; `DrivesPage.navigationValue` is that
// row's value). Shown by `AwakeModule.settingsDestination` with the module's stores and its live context.

struct DrivesPage: View, ControlDeclaring {
    typealias Controls = DrivesPageControls

    /// The Awake page's navigation row pushes this route.
    static let route = SettingsRoute(DrivesPageControls.surface)

    /// "Off", "On", "2 drives": the value of the Awake page's "Drives ›" row.
    @MainActor static func navigationValue(config: AwakeConfig) -> String {
        DrivesPageModel.navigationValue(featureOn: AwakeFeatureGraph.rawState(.driveAlive, in: config.rawFeatures),
                                        config: config.drives)
    }

    @ObservedObject var config: ConfigStore<AwakeConfig>
    @ObservedObject var runtime: AwakeRuntimeState
    /// The running module's context (nil while Awake is stopped).
    let live: @MainActor () -> AwakeContext?
    @StateObject private var model = DrivesPageLive()

    init(config: ConfigStore<AwakeConfig>, runtime: AwakeRuntimeState, live: @escaping @MainActor () -> AwakeContext?) {
        self.config = config
        self.runtime = runtime
        self.live = live
    }

    var body: some View {
        SettingsPageScaffold(route: Self.route) {
            SettingsPageHeader(L("Drives"), summary: L("Keeps external drives from spinning down while Awake runs."),
                               symbol: "externaldrive.fill", tint: .orange, isOn: featureBinding,
                               switchLabel: L("Keep drives awake"), control: ControlID("awake.drives.header"))
                .disabled(!awakeRunning)
            if !awakeRunning {
                Section {
                    StatusRow(L("Turn on Awake to keep drives awake."))
                }
                FeatureHighlights(Self.highlights)
            } else if !featureOn {
                FeatureHighlights(Self.highlights)
            } else if !runtime.isEffective(.driveAlive) {
                Section {
                    notEffectiveRow
                }
            } else {
                volumesSection
                optionsSection
            }
            PageFooterButtons(advanced: nil, help: Self.route)
        }
        .onAppear { model.attach(live()) }
        .onDisappear { model.detach() }
        .onChange(of: runtime.moduleState) { _, _ in model.attach(live()) }
        .onChange(of: runtime.effectiveFeatures) { _, _ in model.refresh() }
    }

    // MARK: State

    private var awakeRunning: Bool { runtime.moduleState != .stopped }
    private var featureOn: Bool { AwakeFeatureGraph.rawState(.driveAlive, in: config.value.rawFeatures) }

    private var featureBinding: Binding<Bool> {
        Binding(get: { featureOn },
                set: { on in
                    guard on != featureOn else { return }
                    config.value.features[.driveAlive] = on
                })
    }

    /// Safe Mode, or the `Awake.disable.driveAlive` kill switch (ux m9: plain words, the lock symbol, and the
    /// command that turns it back on).
    @ViewBuilder private var notEffectiveRow: some View {
        if SettingsShell.shared.host?.safeMode.isActive == true {
            StatusRow(L("Drives aren’t kept awake in Safe Mode."))
        } else {
            HStack(spacing: 6) {
                StatusRow(L("Turned off for this Mac by an administrator or a Terminal command."), symbol: "lock.fill")
                InfoButton(L("Turn Drive Alive Back On"),
                           message: L("In Terminal, run “defaults delete \(ConfigStore<AwakeConfig>.persistentDomainName) Awake.disable.driveAlive”, then quit and reopen Snaptic. On a managed Mac, ask your administrator."))
            }
        }
    }

    private static var highlights: [FeatureHighlight] {
        [
            FeatureHighlight(id: "drives.ready", symbol: "externaldrive",
                             title: L("No waiting for drives to spin up"),
                             text: L("Drives you choose stay ready, so opening and saving files doesn’t pause.")),
            FeatureHighlight(id: "drives.file", symbol: "doc",
                             title: L("One tiny hidden file"),
                             text: L("Snaptic rewrites an 8-byte file named .snaptic-keepalive at the top of each drive. Nothing else is read or changed.")),
            FeatureHighlight(id: "drives.sessions", symbol: "cup.and.saucer",
                             title: L("Only while Awake runs"),
                             text: L("Drives stay awake during your Awake sessions, or always if you choose.")),
        ]
    }

    private var inputs: DrivesPageModel.Inputs {
        let drives = config.value.drives.sanitized()
        let governing = runtime.governing
        var results: [VolumeUUIDKey: DriveWriteResult] = [:]
        for state in runtime.drives {
            results[state.uuid] = DriveWriteResult(lastWrite: state.lastWrite, lastError: state.lastError)
        }
        let sessionAllows = DriveAlivePolicy.shouldWrite(sessionActive: governing.isActive,
                                                         sessionSource: governing.source,
                                                         evenWithoutSession: drives.evenWithoutSession,
                                                         backgroundWorkAllowed: true, uiConfirmedFirstWrite: true)
        return DrivesPageModel.Inputs(mounted: model.mounted, config: drives, results: results,
                                      firstWriteRunning: model.firstWriteRunning, firstWriteFailures: model.failures,
                                      sessionAllowsWrites: sessionAllows,
                                      backgroundWorkAllowed: model.backgroundWorkAllowed(config.value))
    }

    // MARK: Sections

    @ViewBuilder private var volumesSection: some View {
        let rows = DrivesPageModel.rows(inputs)
        Section {
            if model.mounted == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Looking for drives…")).foregroundStyle(.secondary)
                }
            } else if rows.isEmpty {
                EmptyListView(L("No External Drives"), symbol: "externaldrive",
                              text: L("Connect an external drive to keep it from spinning down."), action: nil)
            } else {
                ForEach(rows) { row in
                    DriveRowView(row: row, isOn: rowBinding(row), busy: row.uuid.map(model.firstWriteRunning.contains) ?? false,
                                 write: { write(row) })
                }
            }
            if model.limitReached {
                SettingsRowNote(L("Snaptic keeps at most 16 drives awake. Turn one off first."))
            }
        } header: {
            Text(L("Drives"))
        } footer: {
            Text(L("Snaptic rewrites a hidden 8-byte file named .snaptic-keepalive at the top of each drive that is on, so the drive doesn’t spin down. Nothing else on the drive is read or changed, and turning a drive off removes the file. macOS asks once for access to removable volumes, the first time Snaptic writes to a drive."))
                .foregroundStyle(.secondary)
        }
        .modifier(OptionalSettingsAnchor(ControlID("awake.drives.volumes")))
    }

    private var optionsSection: some View {
        Section {
            SliderSetting(L("Check drives every"),
                          help: L("How often each drive is written to. Most drives spin down after about 10 minutes."),
                          value: SettingsBinding.double(SettingsBinding.store(config, \.drives.intervalSeconds),
                                                        in: DriveAlivePolicy.intervalRange),
                          in: Double(DriveAlivePolicy.intervalRange.lowerBound)...Double(DriveAlivePolicy.intervalRange.upperBound),
                          step: 30, defaultValue: Double(DriveAliveConfig().intervalSeconds), format: .seconds,
                          anchor: ControlID("awake.drives.interval"))
            ToggleSetting(L("Also when no session is running"),
                          help: L("Keeps drives awake even while Awake isn’t keeping your Mac awake."),
                          isOn: SettingsBinding.store(config, \.drives.evenWithoutSession),
                          anchor: ControlID("awake.drives.evenWithoutSession"))
        } footer: {
            Text(L("Sessions started from the command line don’t keep drives awake."))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func rowBinding(_ row: DriveRow) -> Binding<Bool> {
        Binding(get: { row.isOn },
                set: { on in
                    guard on != row.isOn else { return }
                    if on { turnOn(row) } else { model.turnOff(row, store: config) }
                })
    }

    /// The first write must follow a real click (security M3, R5-8): not right after another app opened Settings,
    /// and not from a key press while that open is pending.
    private func turnOn(_ row: DriveRow) {
        guard SettingsShell.shared.mayStart() else { return }
        model.turnOn(row, store: config)
    }

    private func write(_ row: DriveRow) {
        guard SettingsShell.shared.mayStart(), let uuid = row.uuid else { return }
        model.firstWrite(uuid)
    }
}

/// One volume: its switch, what happens to it, and Write Now / Try Again when the first write is still needed.
private struct DriveRowView: View {
    let row: DriveRow
    let isOn: Binding<Bool>
    let busy: Bool
    let write: () -> Void

    var body: some View {
        let text = DrivesPageModel.statusText(row.status, time: { $0.formatted(date: .omitted, time: .shortened) })
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                Text(row.name)
                if let text, !row.offersWrite { Text(text) }
            }
            .disabled(!row.canToggle || busy)
            .accessibilityLabel(row.name)
            .accessibilityValue(text ?? "")
            if row.offersWrite, let text {
                SettingsRowNote(text, fix: StatusAction(title: writeTitle, control: ControlID("awake.drives.write")) {
                    write()
                })
            }
        }
    }

    private var writeTitle: String {
        if case .failed = row.status { return L("Try Again") }
        return L("Write Now")
    }
}

/// The page's live half: the mounted volumes (VolumeMonitor, while Drive Alive runs), the first writes in flight
/// and their failures. Attached to the running module's context while the page is shown.
@MainActor final class DrivesPageLive: ObservableObject {
    @Published private(set) var mounted: [DriveCandidate]?
    @Published private(set) var firstWriteRunning: Set<VolumeUUIDKey> = []
    @Published private(set) var failures: [VolumeUUIDKey: DriveAliveError] = [:]
    @Published private(set) var limitReached = false

    private weak var context: AwakeContext?
    private var lifetime: Lifetime?

    init() {}

    func attach(_ context: AwakeContext?) {
        if let context, context === self.context, lifetime != nil {
            refresh()
            return
        }
        detach()
        self.context = context
        if let context {
            let life = Lifetime()
            lifetime = life
            context.volumes.observe(life) { [weak self] in self?.refresh() }
        }
        refresh()
    }

    func detach() {
        lifetime?.end()
        lifetime = nil
        context = nil
    }

    /// Re-reads the mounts (nil while the volume monitor isn't running).
    func refresh() {
        let list = context?.volumes.volumes?.map { DriveCandidate(uuid: $0.uuid, name: $0.name, facts: $0.facts) }
        if list != mounted { mounted = list }
    }

    /// Security M1: the guards' verdict for background work (false while unknown), with SessionController's
    /// in-memory guard memory, never the outside-writable snapshot store (security S-1).
    func backgroundWorkAllowed(_ config: AwakeConfig) -> Bool {
        guard let context, let facts = context.power.facts else { return false }
        return AwakeGuards.allowsBackgroundWork(facts, config: config.guards, memory: context.sessions.guardMemory)
    }

    /// The switch was turned on: store the volume (first write not done), then write to it right away.
    func turnOn(_ row: DriveRow, store: ConfigStore<AwakeConfig>) {
        guard let uuid = row.uuid, context != nil else { return }
        let next = DrivesPageModel.turningOn(uuid, name: row.name, in: store.value.drives)
        guard next.volumes[uuid]?.enabled == true else {
            limitReached = true
            return
        }
        limitReached = false
        if store.value.drives != next { store.value.drives = next }
        firstWrite(uuid)
    }

    /// The switch was turned off: stop writing and remove Snaptic's file (only if it is still ours).
    func turnOff(_ row: DriveRow, store: ConfigStore<AwakeConfig>) {
        guard let uuid = row.uuid else { return }
        let next = DrivesPageModel.turningOff(uuid, in: store.value.drives)
        if store.value.drives != next { store.value.drives = next }
        failures[uuid] = nil
        limitReached = false
        context?.driveAlive.removeKeepAliveFile(uuid)
    }

    /// The UI-confirmed first write (§2.9); on success the service sets `firstWriteDone`.
    func firstWrite(_ uuid: VolumeUUIDKey) {
        guard let context, !firstWriteRunning.contains(uuid) else { return }
        failures[uuid] = nil
        firstWriteRunning.insert(uuid)
        context.driveAlive.firstWrite(uuid) { [weak self] error in
            guard let self else { return }
            self.firstWriteRunning.remove(uuid)
            if let error { self.failures[uuid] = error }
        }
    }
}

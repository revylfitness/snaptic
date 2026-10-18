import SwiftUI
import SnapticKit

// Settings → Displays → Safety (owner: B). Every safety option, the guard and journal
// status, the panic shortcut, "Allow without asking" and remembered modes.

struct SafetyPage: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State private var tick = 0
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var safety: Binding<SafetyConfig> {
        Binding(get: { env.config.value.safety }, set: { env.config.value.safety = $0.sanitized() })
    }

    var body: some View {
        Form {
            Section(L("Confirm display changes")) {
                Picker(L("Confirm resolution changes"), selection: safety.confirmResolution) {
                    Text(L("New modes only")).tag(ConfirmResolutionChanges.newModesOnly)
                    Text(L("Always")).tag(ConfirmResolutionChanges.always)
                    Text(L("Never for listed modes")).tag(ConfirmResolutionChanges.neverForPublic)
                }
                Stepper(value: safety.confirmSeconds, in: SafetyConfig.confirmSecondsRange) {
                    Text(L("Revert automatically after \(env.config.value.safety.confirmSeconds) seconds"))
                }
                Text(L("Risky changes (new resolutions, mirroring, disconnecting, rotation, HDR) show “Keep this change?” on every visible display. Esc or no answer reverts them; a separate safety helper reverts them even if Snaptic stops responding."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("Tell me when displays were restored after an unexpected exit"), isOn: safety.announceRecovery)
            }

            Section(L("Restore All Displays")) {
                Toggle(L("Keyboard shortcut"), isOn: safety.panicHotkeyEnabled)
                    .disabled(env.context?.guardClient.hasLongState == true && env.config.value.safety.panicHotkeyEnabled)
                LabeledContent(L("Shortcut"), value: shortcutText)
                if env.context?.guardClient.hasLongState == true {
                    Text(L("The shortcut stays on while a display is disconnected, mirrored to a virtual screen or dimmed to black."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let problem = env.context?.panic.hotkeyProblem {
                    Text(problem).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button(L("Restore All Displays Now")) {
                        env.context?.panic.panic(reason: L("Safety settings"))
                    }
                    .disabled(env.context == nil)
                    if env.runtime.isPanicLatched {
                        Button(L("Resume Display Automation")) { _ = env.context?.actions.perform(PanicCoordinator.resumeActionID, on: .all) }
                    }
                }
                Text(L("Undoes resolution changes from the last minute, reconnects displays Snaptic turned off, removes dimming and overlays, stops virtual screens and streams, and pauses automation until you resume. Rotation and HDR are not touched. Also available from the menu and as `snaptic panic`."))
                    .font(.caption).foregroundStyle(.secondary)
                if let summary = env.runtime.lastPanicSummary {
                    Text(summary).font(.caption)
                }
            }

            Section(L("Safety helper")) {
                LabeledContent(L("Status"), value: guardStatus)
                if env.context?.guardClient.isUnprotected == true {
                    Label(L("Unprotected — restart Snaptic"), systemImage: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                    Button(L("Restart Snaptic")) { env.context?.relauncher.relaunch(reason: L("Safety helper")) }
                }
                if let reason = env.context?.helpers.unavailable {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
                LabeledContent(L("Can revert rotation and HDR"), value: env.context?.guardClient.canMonitorPanel == true ? L("Yes") : L("No"))
                LabeledContent(L("Pending confirmation"), value: env.context?.transactions.hasPendingTrial == true ? L("Yes") : L("No"))
                LabeledContent(L("Undo journal"), value: journalText)
            }

            Section(L("Allowed without asking")) {
                let allowed = env.config.value.safety.preConfirmAllowed.values
                let allowedKeys = allowed.keys.sorted { $0.rawValue < $1.rawValue }
                if allowedKeys.isEmpty {
                    Text(L("No monitor commands are allowed without confirmation.")).foregroundStyle(.secondary)
                }
                ForEach(allowedKeys, id: \.self) { key in
                    let list = allowed[key] ?? PreConfirmAllowList()
                    HStack {
                        VStack(alignment: .leading) {
                            Text(displayName(key))
                            Text(list.entries.map { L("code \($0)") }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Ask Again")) { env.config.value.safety.preConfirmAllowed[key] = nil }
                    }
                }
            }

            Section(L("Remembered resolutions")) {
                let kept = env.config.value.safety.keptModes.values
                let keptKeys = kept.keys.sorted { $0.rawValue < $1.rawValue }
                if keptKeys.isEmpty {
                    Text(L("Resolutions you keep are remembered here and won't ask again.")).foregroundStyle(.secondary)
                }
                ForEach(keptKeys, id: \.self) { key in
                    let modes = kept[key] ?? KeptModes()
                    HStack {
                        Text(displayName(key))
                        Spacer()
                        Text(L("\(modes.modes.count) modes")).foregroundStyle(.secondary)
                        Button(L("Forget")) { env.config.value.safety.keptModes[key] = nil }
                    }
                }
            }

            if let ctx = env.context {
                let missing = ctx.privateAPI.unavailableFeatures()
                let missingKeys = missing.keys.sorted { $0.rawValue < $1.rawValue }
                if !missingKeys.isEmpty {
                    Section(L("Unavailable on this Mac")) {
                        ForEach(missingKeys, id: \.self) { feature in
                            LabeledContent(feature.rawValue, value: missing[feature] ?? "")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(refresh) { _ in tick &+= 1 }
    }

    private var shortcutText: String {
        if let combo = env.context?.panic.registeredHotkey { return PanicCoordinator.describe(combo) }
        if !env.config.value.safety.panicHotkeyEnabled { return L("Off") }
        return env.context == nil ? PanicCoordinator.describe(SafetyConfig.defaultPanicHotkey) : L("Not registered")
    }

    private var guardStatus: String {
        _ = tick
        guard let ctx = env.context else { return L("Displays are off") }
        if ctx.guardClient.isAlive { return ctx.guardClient.pid.map { L("Running (pid \($0))") } ?? L("Running") }
        return ctx.guardClient.lastFailure ?? L("Starts when needed")
    }

    private var journalText: String {
        guard let ctx = env.context else { return "—" }
        let session = ctx.transactions.hasSessionJournal ? L("pending change") : L("empty")
        let permanent = ctx.transactions.permanentJournalCount
        return permanent > 0 ? L("\(session); \(permanent) rotation/HDR steps to confirm") : session
    }

    private func displayName(_ key: DisplayKey) -> String {
        if let info = env.runtime.displays.first(where: { $0.key == key }) { return info.name }
        let per = env.config.value.perDisplay[key]?.identity
        return per?.customName ?? per?.lastKnownName ?? L("Display \(key.rawValue.prefix(6))")
    }
}

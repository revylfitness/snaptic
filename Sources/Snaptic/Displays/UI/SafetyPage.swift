import SwiftUI
import SnapticKit

// Settings → Displays → Safety (owner: B; 0.2 page, deleted at the 0.3 step-3 exit). Its settings are the 0.3
// Confirm display changes section (shown here until then); the rest are status rows that move to Display
// Information (F). Live through `revision(.diagnostics)` (0.3 §4.5): no timer.

struct SafetyPage: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @ObservedObject private var revision: ControllerRevision

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _revision = ObservedObject(wrappedValue: env.runtime.revision(.diagnostics))
    }

    var body: some View {
        Form {
            ConfirmChangesSection(env: env)

            Section {
                LabeledContent {
                    Button(L("Restore All Displays")) {
                        env.context?.panic.panic(reason: L("Safety settings"))
                    }
                    .disabled(env.context == nil)
                } label: {
                    Text(L("Restore all displays now"))
                    Text(L("Undoes recent resolution changes, reconnects displays, and pauses display automation."))
                }
                if let summary = env.runtime.lastPanicSummary {
                    Text(summary).foregroundStyle(.secondary)
                }
            }

            Section(L("Safety helper")) {
                LabeledContent(L("Status"), value: guardStatus)
                if env.context?.guardClient.isUnprotected == true {
                    StatusRow(L("The safety helper stopped."), style: .warning, actions: [
                        StatusAction(title: L("Restart Snaptic")) { [env] in
                            env.context?.relauncher.relaunch(reason: L("Safety helper"))
                        },
                    ])
                }
                if let reason = env.context?.helpers.unavailable {
                    StatusRow(reason, style: .warning)
                }
                LabeledContent(L("Can revert rotation and HDR"),
                               value: env.context?.guardClient.canMonitorPanel == true ? L("Yes") : L("No"))
                LabeledContent(L("Change awaiting confirmation"),
                               value: env.context?.transactions.hasPendingTrial == true ? L("Yes") : L("No"))
                LabeledContent(L("Undo journal"), value: journalText)
            }

            Section(L("Remembered resolutions")) {
                let kept = env.config.value.safety.keptModes.values
                let keptKeys = kept.keys.sorted { $0.rawValue < $1.rawValue }
                if keptKeys.isEmpty {
                    Text(L("Resolutions you keep are remembered here and won't ask again.")).foregroundStyle(.secondary)
                }
                ForEach(keptKeys, id: \.self) { key in
                    let modes = kept[key] ?? KeptModes()
                    LabeledContent {
                        Button(L("Forget")) { env.config.value.safety.keptModes[key] = nil }
                    } label: {
                        Text(displayName(key))
                        Text(modes.modes.count == 1 ? L("1 resolution") : L("\(modes.modes.count) resolutions"))
                    }
                }
            }

            if let ctx = env.context {
                let missing = ctx.privateAPI.unavailableFeatures()
                let missingKeys = missing.keys.sorted { DisplaysUIText.title($0) < DisplaysUIText.title($1) }
                if !missingKeys.isEmpty {
                    Section(L("Unavailable on this Mac")) {
                        ForEach(missingKeys, id: \.self) { feature in
                            LabeledContent(DisplaysUIText.title(feature), value: missing[feature] ?? "")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var guardStatus: String {
        guard let ctx = env.context else { return L("Displays are off") }
        if ctx.guardClient.isAlive { return L("Running") }
        return ctx.guardClient.lastFailure ?? L("Starts when needed")
    }

    private var journalText: String {
        guard let ctx = env.context else { return "—" }
        let session = ctx.transactions.hasSessionJournal ? L("A change can be undone") : L("Empty")
        let permanent = ctx.transactions.permanentJournalCount
        return permanent > 0 ? L("\(session); \(permanent) rotation or HDR steps to confirm") : session
    }

    private func displayName(_ key: DisplayKey) -> String {
        if let info = env.runtime.displays.first(where: { $0.key == key }) { return info.name }
        let per = env.config.value.perDisplay[key]?.identity
        return per?.customName ?? per?.lastKnownName ?? L("A display that isn't connected")
    }
}

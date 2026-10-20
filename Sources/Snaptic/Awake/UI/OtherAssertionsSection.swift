import SwiftUI
import SnapticKit

/// "Other apps keeping your Mac awake" in Awake › Advanced (owner: G; PLAN 0.3 §1.1, §1.3, §4.3, design M4): a live
/// list of the processes holding power assertions (J's OtherAssertionsReader, read every 5 s only while this section
/// is shown) and a warning when the system-wide SleepDisabled setting is on. Local UI only: nothing here is logged,
/// stored or sent anywhere. 0.3.1 B3.4: Snaptic's own lid-closed mode (and a journal it is still checking) isn't
/// "another app"; sleep left off by an earlier lid-closed session gets the leftover rows instead.
struct OtherAssertionsSection: View, ControlDeclaring {
    typealias Controls = AwakeAdvancedSheetControls

    @StateObject private var reader = OtherAssertionsReader()
    @StateObject private var viewing = OtherAssertionsViewing()
    private let runtime: AwakeRuntimeState?
    private let recovery: LidRecoveryState?

    init(runtime: AwakeRuntimeState? = nil, recovery: LidRecoveryState? = nil) {
        self.runtime = runtime
        self.recovery = recovery
    }

    var body: some View {
        Section {
            if reader.sleepDisabled {
                if let runtime, let recovery {
                    SleepDisabledRows(runtime: runtime, recovery: recovery)
                } else {
                    StatusRow(OtherAssertions.sleepDisabledByOther, style: .warning)
                }
            }
            if !reader.hasRead {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Checking…")).foregroundStyle(.secondary)
                }
            } else if reader.readFailed {
                Text(L("Snaptic couldn’t read which apps are keeping your Mac awake."))
                    .foregroundStyle(.secondary)
            } else if reader.rows.isEmpty {
                Text(L("No other apps are keeping your Mac awake."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(reader.rows.enumerated()), id: \.offset) { _, row in
                    LabeledContent {
                        Text(Self.kindsText(row.kinds))
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(row.processes > 1 ? L("\(row.name) (\(row.processes))") : row.name)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text(L("Other apps keeping your Mac awake"))
                .modifier(SettingsAnchor(ControlID("awake.advanced.otherApps")))
        } footer: {
            Text(L("These keep your Mac awake on their own, whatever Awake does. Updated every few seconds."))
        }
        .onAppear { viewing.begin(reader) }
        .onDisappear { viewing.end() }
    }

    /// What the strongest assertion of a row keeps from happening.
    static func kindsText(_ kinds: [OtherAssertionKind]) -> String {
        switch kinds.first {
        case .systemSleep?: return L("Prevents sleep")
        case .display?: return L("Keeps the display on")
        case .idleSleep?, nil: return L("Prevents idle sleep")
        }
    }
}

/// SleepDisabled is on: someone else's setting, Snaptic's own mode (nothing to say), or the leftover rows.
private struct SleepDisabledRows: View, ControlDeclaring {
    typealias Controls = AwakeAdvancedSheetControls

    @ObservedObject var runtime: AwakeRuntimeState
    @ObservedObject var recovery: LidRecoveryState

    var body: some View {
        if recovery.recovery == .leftover {
            LidLeftoverRow(recovery: recovery, restore: ControlID("awake.advanced.lidRestore"),
                           keepOff: ControlID("awake.advanced.lidKeepOff"),
                           dismiss: ControlID("awake.advanced.lidDismiss"))
        } else if case .off = runtime.lidMode, recovery.recovery == .nothing {
            StatusRow(OtherAssertions.sleepDisabledByOther, style: .warning)
        }
    }
}

/// The reader's viewer lifetime while the section is on screen (`keepUpdated(_:)`): one per appearance.
@MainActor final class OtherAssertionsViewing: ObservableObject {
    private var lifetime: Lifetime?

    func begin(_ reader: OtherAssertionsReader) {
        guard lifetime == nil else { return }
        let life = Lifetime()
        lifetime = life
        reader.keepUpdated(life)
    }

    func end() {
        lifetime?.end()
        lifetime = nil
    }
}

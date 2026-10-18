import SwiftUI
import SnapticKit

/// "Other apps keeping your Mac awake" in Awake › Advanced (owner: G; PLAN 0.3 §1.1, §1.3, §4.3, design M4): a live
/// list of the processes holding power assertions (J's OtherAssertionsReader, read every 5 s only while this section
/// is shown) and a warning when the system-wide SleepDisabled setting is on. Local UI only: nothing here is logged,
/// stored or sent anywhere.
struct OtherAssertionsSection: View, ControlDeclaring {
    typealias Controls = AwakeAdvancedSheetControls

    @StateObject private var reader = OtherAssertionsReader()
    @StateObject private var viewing = OtherAssertionsViewing()

    var body: some View {
        Section {
            if reader.sleepDisabled {
                StatusRow(L("Sleep is turned off for this Mac by another app or command. Snaptic can’t change this."),
                          style: .warning)
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

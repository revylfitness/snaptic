import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

enum SettingsBadge: Equatable { case beta, experimental, new, paused(String), unavailable(String) }

/// Top section of every page. `isOn` = master switch (module or feature group); `switchLabel` is its accessibility
/// label and tooltip ("Use Awake", N5).
struct SettingsPageHeader: View {
    let title: String
    let summary: String
    let symbol: String
    let tint: SettingsTint
    let isOn: Binding<Bool>?
    let switchLabel: String?
    let badge: SettingsBadge?
    let status: String?
    /// R5-13.
    let control: ControlID?

    init(_ title: String, summary: String, symbol: String, tint: SettingsTint,
         isOn: Binding<Bool>? = nil, switchLabel: String? = nil, badge: SettingsBadge? = nil, status: String? = nil,
         control: ControlID? = nil) {
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.tint = tint
        self.isOn = isOn
        self.switchLabel = switchLabel
        self.badge = badge
        self.status = status
        self.control = control
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIcon(symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(summary).foregroundStyle(.secondary)
                if let status { Text(status).foregroundStyle(.secondary) }
            }
            Spacer()
            if let isOn {
                Toggle(switchLabel ?? title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .help(switchLabel ?? title)
            }
        }
    }
}

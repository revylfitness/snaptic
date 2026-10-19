import SwiftUI
import SnapticKit

enum SettingsBadge: Equatable {
    case beta, experimental, new, paused(String), unavailable(String)

    var title: String {
        switch self {
        case .beta: return L("Beta")
        case .experimental: return L("Experimental")
        case .new: return L("New")
        case .paused(let text), .unavailable(let text): return text
        }
    }

    /// VoiceOver label of a row that shows this badge after its title ("Disconnect displays, Beta"; review ux m8).
    func spoken(_ title: String) -> String { L("\(title), \(self.title)") }

    var color: Color {
        switch self {
        case .beta: return .orange
        case .experimental: return .purple
        case .new: return .accentColor
        case .paused, .unavailable: return .secondary
        }
    }

    /// The badge as styled text, for labels that must stay plain `Text` (toggle and picker titles).
    var text: Text {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
    }
}

/// A small capsule: "Beta", "Experimental", "New", or a paused/unavailable note.
struct SettingsBadgeView: View {
    let badge: SettingsBadge

    init(_ badge: SettingsBadge) { self.badge = badge }

    var body: some View {
        Text(badge.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badge.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(badge.color.opacity(0.15)))
            .fixedSize()
    }
}

/// Top section of every page. `isOn` = master switch (module or feature group), the only `.regular` switch in
/// Settings; `switchLabel` is its accessibility label and tooltip ("Use Awake", N5). Without a switch the header is
/// the centered "hero" variant (General, About), as in System Settings on macOS 14 and later. `status` is a short
/// live line ("2 displays").
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
        Section {
            if let isOn {
                row(isOn)
            } else {
                hero
            }
        }
    }

    private func row(_ isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsIcon(symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if let badge { SettingsBadgeView(badge) }
                }
                Text(summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Toggle(switchText, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .help(switchText)
                    .accessibilityLabel(switchText)
                    .modifier(OptionalSettingsAnchor(control))
                if let status {
                    Text(status)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            SettingsIcon(symbol, tint: tint, size: 64)
                .padding(.bottom, 2)
            HStack(spacing: 6) {
                Text(title).font(.title2.weight(.semibold))
                if let badge { SettingsBadgeView(badge) }
            }
            Text(summary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let status {
                Text(status)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .modifier(OptionalSettingsAnchor(control))
    }

    private var switchText: String { switchLabel ?? L("Use \(title)") }
}

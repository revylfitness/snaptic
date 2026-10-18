import SwiftUI
import SnapticKit

struct StatusAction {
    let title: String
    let action: @MainActor () -> Void
    /// R5-13.
    var control: ControlID? = nil

    init(title: String, control: ControlID? = nil, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.control = control
        self.action = action
    }
}

enum StatusStyle {
    case info, warning, error

    var symbol: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return .secondary
        case .warning: return .yellow
        case .error: return .red
        }
    }

    /// Spoken before the text, so the state never rests on color alone.
    var spokenPrefix: String {
        switch self {
        case .info: return ""
        case .warning: return L("Warning: ")
        case .error: return L("Error: ")
        }
    }
}

/// A state line with its actions: "Safe Mode is on." [Leave Safe Mode]. Shown only while the state is true.
struct StatusRow: View {
    let text: String
    let symbol: String?
    let style: StatusStyle
    let actions: [StatusAction]

    init(_ text: String, symbol: String? = nil, style: StatusStyle = .info, actions: [StatusAction] = []) {
        self.text = text
        self.symbol = symbol
        self.style = style
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol ?? style.symbol)
                .symbolRenderingMode(style == .warning ? .multicolor : .monochrome)
                .foregroundStyle(style.color)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(style.spokenPrefix + text)
            Spacer(minLength: 8)
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(action.title) { action.action() }
                    .fixedSize()
                    .modifier(OptionalSettingsAnchor(action.control))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A kill switch's status row (review ux m9): the one wording and style for every page and sheet, with an (i) that
/// shows the Terminal command that turns it back on. Pages use `DefaultsLockRow(module:)` for
/// `Modules.disable.<id>` and `DefaultsLockRow(key:)` for a feature's own key (`Displays.disable.<feature>`,
/// `Awake.disable.<feature>`).
struct DefaultsLockRow: View {
    let key: String

    init(key: String) {
        self.key = key
    }

    init(module: ModuleID) {
        self.init(key: ModuleHost.disableKey(module))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            StatusRow(DefaultsLock.text, symbol: "lock.fill")
            InfoButton(L("How to turn it back on"),
                       message: DefaultsLock.details(domain: ConfigStore<ModulesConfig>.persistentDomainName, key: key))
        }
    }
}

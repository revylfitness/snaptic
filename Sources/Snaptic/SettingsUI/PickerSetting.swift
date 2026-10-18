import SwiftUI
import SnapticKit

enum PickerSettingStyle {
    /// Radio group for 2–5 options with help; segmented for 2–4 short options; a pop-up otherwise.
    case automatic
    case popUp, segmented, radio
    /// A pull-down button showing the current choice, its menu with a checkmark.
    case pullDown

    /// The automatic choice for these options (design §2: pop-up > 4, segmented 2–4 short, radio 2–5 with help).
    static func resolved(count: Int, anyHelp: Bool, longestTitle: Int) -> PickerSettingStyle {
        if anyHelp && (2...5).contains(count) { return .radio }
        if (2...4).contains(count) && longestTitle <= 14 { return .segmented }
        return .popUp
    }
}

struct PickerOption<V: Hashable>: Identifiable {
    let value: V
    let title: String
    let help: String?
    let symbol: String?
    let enabled: Bool
    var id: V { value }

    init(_ value: V, _ title: String, help: String? = nil, symbol: String? = nil, enabled: Bool = true) {
        self.value = value
        self.title = title
        self.help = help
        self.symbol = symbol
        self.enabled = enabled
    }
}

/// One choice among options, as a pop-up, segmented control, radio group or pull-down. With `defaultValue` the row
/// gets "Reset to Default" in its context menu. Disabled options show but can't be chosen.
struct PickerSetting<V: Hashable>: View {
    let title: String
    let help: String?
    let selection: Binding<V>
    let options: [PickerOption<V>]
    let style: PickerSettingStyle
    let defaultValue: V?
    let anchor: ControlID?
    let subordinate: Bool

    init(_ title: String, help: String? = nil, selection: Binding<V>, options: [PickerOption<V>],
         style: PickerSettingStyle = .automatic, defaultValue: V?, anchor: ControlID? = nil, subordinate: Bool = false) {
        self.title = title
        self.help = help
        self.selection = selection
        self.options = options
        self.style = style
        self.defaultValue = defaultValue
        self.anchor = anchor
        self.subordinate = subordinate
    }

    var body: some View {
        content
            .padding(.leading, subordinate ? 20 : 0)
            .modifier(ResetContextMenu(reset: resetAction, isDefault: defaultValue == nil || selection.wrappedValue == defaultValue))
            .modifier(OptionalSettingsAnchor(anchor))
    }

    @ViewBuilder private var content: some View {
        switch resolvedStyle {
        case .segmented:
            picker.pickerStyle(.segmented)
        case .radio:
            picker.pickerStyle(.radioGroup)
        case .pullDown:
            pullDown
        case .popUp, .automatic:
            picker.pickerStyle(.menu)
        }
    }

    private var resolvedStyle: PickerSettingStyle {
        guard style == .automatic else { return style }
        return PickerSettingStyle.resolved(count: options.count, anyHelp: options.contains { $0.help != nil },
                                           longestTitle: options.map(\.title.count).max() ?? 0)
    }

    private var picker: some View {
        Picker(selection: selection) {
            ForEach(options) { option in
                optionLabel(option)
                    .tag(option.value)
                    .disabled(!option.enabled)
            }
        } label: {
            Text(title)
            if let help { Text(help) }
        }
    }

    @ViewBuilder private func optionLabel(_ option: PickerOption<V>) -> some View {
        if resolvedStyle == .radio, let help = option.help {
            VStack(alignment: .leading, spacing: 1) {
                Text(option.title)
                Text(help)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let symbol = option.symbol, resolvedStyle != .segmented {
            Label(option.title, systemImage: symbol)
                .help(option.help ?? "")
        } else {
            Text(option.title)
                .help(option.help ?? "")
        }
    }

    private var pullDown: some View {
        LabeledContent {
            Menu {
                ForEach(options) { option in
                    Button {
                        selection.wrappedValue = option.value
                    } label: {
                        if option.value == selection.wrappedValue {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                    .disabled(!option.enabled)
                }
            } label: {
                Text(options.first { $0.value == selection.wrappedValue }?.title ?? "")
            }
            .fixedSize()
        } label: {
            Text(title)
            if let help { Text(help) }
        }
    }

    private var resetAction: (() -> Void)? {
        guard let defaultValue else { return nil }
        let binding = selection
        return { if binding.wrappedValue != defaultValue { binding.wrappedValue = defaultValue } }
    }
}

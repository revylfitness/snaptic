import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

enum PickerSettingStyle { case automatic, popUp, segmented, radio, pullDown }

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
        Picker(title, selection: selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.value)
            }
        }
        .padding(.leading, subordinate ? 20 : 0)
    }
}

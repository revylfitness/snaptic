import SwiftUI
import SnapticKit

/// **Arrange Displays…** (owner D; PLAN 0.3 §4.3 Arrangement): a sheet with the drag canvas, Snap to edges and, as a
/// disclosure, the keyboard path (move a display to one of 16 places next to another). Opened from the root page's
/// Arrangement section (`ArrangementRows`) through `SettingsShell.openSheet = ArrangeSheetControls.sheet`, and from
/// the menu's "Arrange Displays…". Never presents another sheet.
struct ArrangeSheet: View, ControlDeclaring {
    typealias Controls = ArrangeSheetControls

    private let env: DisplaysPageEnvironment?

    init() {
        env = DisplaysSettingsLookup.environment()
    }

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        AdvancedSheet(L("Arrange Displays"), restoreDefaults: nil) {
            if let env {
                ArrangeContent(env: env)
            } else {
                Section {
                    StatusRow(L("Turn on Displays to arrange your displays."))
                }
            }
        }
    }
}

/// The sheet's sections: canvas, Snap to edges and the keyboard disclosure (also used by the 0.2 Arrangement page
/// until the step-3 exit removes it).
struct ArrangeContent: View {
    typealias Controls = ArrangeSheetControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @State private var keyboardExpanded = false

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
    }

    private var active: [DisplayInfo] { runtime.displays.filter { $0.isActive && $0.mirrorOf == nil } }

    var body: some View {
        if env.context?.connectPlanner.arrangement == nil {
            Section {
                StatusRow(L("Turn on Displays to arrange your displays."))
            }
        } else if !runtime.isEffective(.arrangement) {
            Section {
                StatusRow(offText, actions: offActions)
            }
        } else if active.count < 2 {
            Section {
                StatusRow(L("Connect another display to arrange them."))
            }
        } else {
            Section {
                ArrangementCanvas(env: env)
                    .modifier(SettingsAnchor(ControlID("displays.arrange.canvas")))
                ToggleSetting(L("Snap to edges"),
                              help: L("Displays line up with each other’s edges and centers while you drag."),
                              isOn: SettingsBinding.store(env.config, \.management.snapArrangement),
                              anchor: ControlID("displays.arrange.snap"))
            } footer: {
                Text(L("Drag a display to move it. The white bar marks the main display, which has the menu bar."))
            }
            Section {
                DisclosureGroup(isExpanded: $keyboardExpanded) {
                    PositionAlignRows(env: env, displays: active)
                } label: {
                    Text(L("Move with the keyboard"))
                }
                .modifier(SettingsAnchor(ControlID("displays.arrange.position")))
                .modifier(SettingsRevealExpansion([ControlID("displays.arrange.position")], isExpanded: $keyboardExpanded))
            }
        }
    }

    private var offText: String {
        if case .unavailable(let reason)? = runtime.availability[.arrangement] { return reason }
        return env.context?.otherApps.pauseReason(for: .arrangement) ?? L("Arrangement and mirroring is off.")
    }

    private var offActions: [StatusAction] {
        if case .unavailable? = runtime.availability[.arrangement] { return [] }
        if env.context?.otherApps.pauseReason(for: .arrangement) != nil { return [] }
        return [StatusAction(title: L("Turn On")) { [env] in env.enableFeature(.arrangement) }]
    }
}

/// The keyboard path: put a display in one of 16 places next to another one.
private struct PositionAlignRows: View {
    let env: DisplaysPageEnvironment
    let displays: [DisplayInfo]
    @State private var moving: DisplayKey?
    @State private var reference: DisplayKey?
    @State private var placement: ArrangementPlacement = .rightCenter

    var body: some View {
        let movingKey = moving ?? displays.first(where: { !$0.isMain })?.key ?? displays.first?.key
        let referenceKey = reference.flatMap { r in r == movingKey ? nil : r }
            ?? displays.first(where: { $0.key != movingKey })?.key
        PickerSetting(L("Display"),
                      selection: Binding(get: { movingKey }, set: { moving = $0 }),
                      options: displays.map { PickerOption(Optional($0.key), $0.name) },
                      style: .popUp, defaultValue: nil)
        PickerSetting(L("Place"),
                      selection: $placement,
                      options: ArrangementPlacement.allCases.map { PickerOption($0, $0.title) },
                      style: .popUp, defaultValue: nil)
        PickerSetting(L("Next to"),
                      selection: Binding(get: { referenceKey }, set: { reference = $0 }),
                      options: displays.filter { $0.key != movingKey }.map { PickerOption(Optional($0.key), $0.name) },
                      style: .popUp, defaultValue: nil)
        ButtonRow(L("Move Display")) {
            guard let m = movingKey, let r = referenceKey, m != r else { return }
            env.context?.connectPlanner.arrangement?.place(m, placement, relativeTo: r)
        }
        .disabled(movingKey == nil || referenceKey == nil || movingKey == referenceKey)
    }
}

/// The root page's Arrangement rows for the selected display (owner D; F places them before its Saved Layouts row):
/// **Use as** (Main display / Extended display / Mirror for "X"; Apple's wording) and **Arrange Displays…**.
struct ArrangementRows: View {
    typealias Controls = ArrangeSheetControls

    let env: DisplaysPageEnvironment
    let display: DisplayInfo
    let displayCount: Int
    /// False where the arrangement is on the page itself (the 0.2 Arrangement page).
    let showsArrangeButton: Bool
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var arrangement: ControllerRevision

    init(env: DisplaysPageEnvironment, display: DisplayInfo, displayCount: Int, showsArrangeButton: Bool = true) {
        self.env = env
        self.display = display
        self.displayCount = displayCount
        self.showsArrangeButton = showsArrangeButton
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _arrangement = ObservedObject(wrappedValue: env.runtime.revision(.arrangement))
    }

    var body: some View {
        if displayCount > 1, let c = env.context?.connectPlanner.arrangement {
            useAsRow(c)
            if showsArrangeButton, runtime.isEffective(.arrangement) {
                ButtonRow(L("Arrange Displays…"), control: ControlID("displays.arrange.open")) {
                    SettingsShell.shared.openSheet = ArrangeSheetControls.sheet
                }
            }
        }
    }

    /// One pop-up for main, extended and mirroring; the options a feature doesn't allow are left out.
    @ViewBuilder private func useAsRow(_ c: ArrangementController) -> some View {
        let canMain = runtime.isEffective(.mainDisplay)
        let canMirror = runtime.isEffective(.mirroring)
        if canMain || canMirror {
            let others = runtime.displays.filter { $0.isActive && $0.mirrorOf == nil && $0.key != display.key }
            let mainRefusal = display.isMain ? nil : c.setMainRefusal(display.key)
            let options = UseAsChoice.options(display: display, others: others, canMain: canMain && mainRefusal == nil,
                                              canMirror: canMirror)
            PickerSetting(L("Use as"),
                          help: display.isMain ? L("The main display has the menu bar and the Dock.") : nil,
                          selection: Binding(get: { current }, set: { choose($0, controller: c) }),
                          options: options, style: .popUp, defaultValue: nil,
                          anchor: ControlID("displays.arrange.useAs"))
        }
    }

    private var current: UseAsChoice {
        if let source = display.mirrorOf,
           let original = runtime.displays.first(where: { $0.desktopID == source || $0.hardwareID == source }) {
            return .mirror(original.key)
        }
        return display.isMain ? .main : .extended
    }

    private func choose(_ choice: UseAsChoice, controller c: ArrangementController) {
        guard choice != current else { return }
        switch choice {
        case .main:
            if display.mirrorOf != nil { c.mirror(display.key, of: nil) }
            c.setMain(display.key)
        case .extended:
            if display.mirrorOf != nil {
                c.mirror(display.key, of: nil)
            } else if display.isMain, let other = runtime.displays.first(where: {
                $0.isActive && $0.mirrorOf == nil && $0.key != display.key && c.setMainRefusal($0.key) == nil
            }) {
                // "Extended" for the main display: another display becomes main.
                c.setMain(other.key)
            }
        case .mirror(let source):
            c.mirror(display.key, of: source)
        }
    }
}

/// The "Use as" pop-up's values.
private enum UseAsChoice: Hashable {
    case main, extended, mirror(DisplayKey)

    static func options(display: DisplayInfo, others: [DisplayInfo], canMain: Bool,
                        canMirror: Bool) -> [PickerOption<UseAsChoice>] {
        var list: [PickerOption<UseAsChoice>] = []
        list.append(PickerOption(.main, L("Main display"), enabled: canMain || display.isMain))
        list.append(PickerOption(.extended, L("Extended display")))
        if canMirror || display.mirrorOf != nil {
            for other in others {
                list.append(PickerOption(.mirror(other.key), L("Mirror for “\(other.name)”"), enabled: canMirror))
            }
        }
        return list
    }
}

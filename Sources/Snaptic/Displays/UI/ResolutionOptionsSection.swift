import AppKit
import SwiftUI
import SnapticKit

/// **Resolution options** for one display (owner D; PLAN 0.3 §4.3 Resolution row, design M6): the discrete resolution
/// slider (applies on release), **Quick Changes ▾** (Toggle HiDPI, Native, Default, Half of Native, Toggle Notch, Undo
/// and Redo Resolution Change), Add to / Remove from Favorites and the favorites (Apply, −). Rows only: the root page
/// shows them inside its collapsed disclosure, the `displays.resolution` page in a section of their own.
struct ResolutionOptionsSection: View, ControlDeclaring {
    typealias Controls = ResolutionSectionsControls

    private let env: DisplaysPageEnvironment?
    private let key: DisplayKey?
    private let standalone: Bool

    /// The options for the display the shared tiles selected, as a page of their own.
    init() {
        env = DisplaysSettingsLookup.environment()
        key = SettingsShell.shared.selectedDisplay
        standalone = true
    }

    init(env: DisplaysPageEnvironment, display: DisplayInfo) {
        self.env = env
        key = display.key
        standalone = false
    }

    var body: some View {
        if standalone {
            SettingsPageScaffold(route: SettingsRoute(Controls.surface)) {
                Section {
                    content
                } header: {
                    Text(L("Resolution options"))
                }
            }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        if let env, let c = env.context?.connectPlanner.resolution {
            ResolutionOptionsRows(env: env, controller: c, key: key)
        } else {
            StatusRow(L("Turn on Displays to change resolutions."))
        }
    }
}

private struct ResolutionOptionsRows: View {
    typealias Controls = ResolutionSectionsControls

    let env: DisplaysPageEnvironment
    let controller: ResolutionController
    let key: DisplayKey?
    @ObservedObject private var runtime: DisplaysRuntimeState
    /// Mode lists, undo history and favorites change with D's revision.
    @ObservedObject private var revision: ControllerRevision
    @StateObject private var settings: ConfigSlice<DisplaysConfig, ResolutionConfig>

    init(env: DisplaysPageEnvironment, controller: ResolutionController, key: DisplayKey?) {
        self.env = env
        self.controller = controller
        self.key = key
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _revision = ObservedObject(wrappedValue: env.runtime.revision(.resolution))
        _settings = StateObject(wrappedValue: ConfigSlice(env.config, \.resolution))
    }

    private var display: DisplayInfo? {
        let eligible = runtime.displays.filter { $0.isActive && $0.mirrorOf == nil }
        if let key { return eligible.first { $0.key == key } }
        return DisplaysSettingsLookup.selected(eligible) { _ in true }
    }

    var body: some View {
        if let display, runtime.isEffective(.resolution) {
            let current = controller.currentMode(display)
            slider(display, current: current)
            actionsRow(display, current: current)
            favorites(display)
        } else {
            StatusRow(L("Choose a display that shows its own picture."))
        }
    }

    // MARK: Slider (discrete, applies on release)

    @ViewBuilder private func slider(_ display: DisplayInfo, current: ModeRef?) -> some View {
        let key = display.key
        let stops = controller.sliderModes(for: key)
        if stops.count >= 2, let current {
            // "Show values as" (size or percent of the default); `settings` re-renders the row when it changes.
            let texts = stops.map { controller.sliderValueText($0, key: key) }
            let index = stops.firstIndex(of: current)
                ?? ResolutionSliderStops.nearestIndex(width: current.pointWidth, in: stops.map(\.pointWidth)) ?? 0
            let defaultIndex = controller.defaultMode(key).flatMap { stops.firstIndex(of: $0) }
            SliderSetting(L("Resolution"),
                          help: L("Left for larger text, right for more space."),
                          value: Binding(get: { Double(index) }, set: { position in
                              apply(position, stops: stops, key: key)
                          }),
                          in: 0...Double(stops.count - 1), step: 1,
                          defaultValue: defaultIndex.map { Double($0) },
                          format: .plain(digits: 0),
                          minSymbol: "textformat.size.larger", maxSymbol: "textformat.size.smaller",
                          commit: .onRelease,
                          anchor: ControlID("displays.resolution.slider"),
                          labels: texts)
        }
    }

    /// Snaps to a favorite, the current, default or native mode next to the released stop (⌥ skips it), then
    /// applies through the transaction queue (a trial when "Confirm resolution changes" asks for one).
    private func apply(_ position: Double, stops: [ModeRef], key: DisplayKey) {
        guard let nearest = ResolutionSliderStops.index(position, count: stops.count) else { return }
        let bypass = NSEvent.modifierFlags.contains(.option)
        let index = controller.snappedStop(nearest, in: stops, key: key, bypass: bypass)
        guard stops.indices.contains(index) else { return }
        controller.apply(stops[index], to: key)
    }

    // MARK: Quick Changes ▾ and favorites

    private func actionsRow(_ display: DisplayInfo, current: ModeRef?) -> some View {
        let key = display.key
        let isFavorite = current.map { controller.favorites(key).contains(FavoriteMode($0)) } ?? false
        let full = controller.favorites(key).count >= PerDisplayResolution.maxFavorites
        return HStack(spacing: 8) {
            ActionMenuButton(L("Quick Changes"), items: quickChanges(display, current: current), primaryAction: nil,
                             control: ControlID("displays.resolution.quickChanges"))
                .fixedSize()
            Spacer(minLength: 8)
            if let current {
                if isFavorite {
                    Button(L("Remove from Favorites")) { controller.removeFavorite(FavoriteMode(current), on: key) }
                        .modifier(SettingsAnchor(ControlID("displays.resolution.favorite")))
                } else {
                    Button(L("Add to Favorites")) { controller.saveFavorite(current, on: key) }
                        .disabled(full)
                        .help(full ? L("You can keep up to \(PerDisplayResolution.maxFavorites) favorites.") : "")
                        .modifier(SettingsAnchor(ControlID("displays.resolution.favorite")))
                }
            }
        }
    }

    private func quickChanges(_ display: DisplayInfo, current: ModeRef?) -> [ActionMenuItem] {
        let key = display.key
        let c = controller
        func item(_ id: String, _ title: String, _ target: ModeRef?) -> ActionMenuItem {
            ActionMenuItem(id: id, title: title, enabled: target != nil && target != current) {
                if let target { c.apply(target, to: key) }
            }
        }
        var items = [
            item("hiDPI", (current?.isHiDPI ?? false) ? L("Turn Off HiDPI") : L("Turn On HiDPI"), c.hiDPIToggleTarget(key)),
            item("native", L("Native Resolution"), c.native(key)),
            item("default", L("Default Resolution"), c.defaultMode(key)),
            item("nativeHalved", L("Half of Native (Sharper)"), c.nativeHalved(key)),
        ]
        if let notch = c.notchToggleTarget(key) {
            items.append(item("notch", L("Toggle Notch Area"), notch))
        }
        items.append(.separator("undoSeparator"))
        items.append(ActionMenuItem(id: "undo", title: L("Undo Resolution Change"), enabled: c.canUndo(key)) {
            c.undo(key)
        })
        items.append(ActionMenuItem(id: "redo", title: L("Redo Resolution Change"), enabled: c.canRedo(key)) {
            c.redo(key)
        })
        return items
    }

    @ViewBuilder private func favorites(_ display: DisplayInfo) -> some View {
        let key = display.key
        let list = controller.favorites(key)
        if !list.isEmpty {
            let all = controller.allModes(display).map(\.ref)
            ForEach(Array(list.enumerated()), id: \.element) { index, favorite in
                let available = favorite.resolve(in: all) != nil
                LabeledContent {
                    HStack(spacing: 4) {
                        Button(L("Apply")) { controller.applyFavorite(index, on: key) }
                            .disabled(!available)
                            .accessibilityLabel(L("Apply \(favorite.label)"))
                        Button {
                            controller.removeFavorite(favorite, on: key)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .help(L("Remove from Favorites"))
                        .accessibilityLabel(L("Remove \(favorite.label) from Favorites"))
                    }
                } label: {
                    Text(favorite.label)
                    if !available {
                        Text(L("Not available with the current filters or connection."))
                    } else {
                        Text(L("Favorite \(index + 1)"))
                    }
                }
                .modifier(OptionalSettingsAnchor(index == 0 ? ControlID("displays.resolution.favorites") : nil))
            }
        }
    }
}

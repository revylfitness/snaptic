import SwiftUI
import SnapticKit

// Helpers C's Displays settings pages share (PLAN 0.3 §4.3: Brightness and Dimming, Color, Hardware Controls,
// Keyboard, their sheets and the Menu bar overlays section of Display Details). Pages read config through
// `ConfigSlice`s and live values through `DisplayRuntime` and the controllers' `ControllerRevision`s (§4.5); these
// helpers only bind and write.

/// Bindings into one display's settings.
@MainActor enum CBind {
    /// A field of one display's settings; a display without settings reads the defaults. Writes only on change.
    static func display<V: Equatable>(_ config: ConfigStore<DisplaysConfig>, _ key: DisplayKey,
                                      _ path: WritableKeyPath<PerDisplayConfig, V>) -> Binding<V> {
        SettingsBinding.lossyEntry(config, \.perDisplay, key, fallback: { PerDisplayConfig() }, path)
    }

    /// An optional per-display value shown as a plain one: `fallback` while unset; writing `fallback` clears it,
    /// so the display follows the shared value again.
    static func override(_ config: ConfigStore<DisplaysConfig>, _ key: DisplayKey,
                         _ path: WritableKeyPath<PerDisplayConfig, Double?>, fallback: Double) -> Binding<Double> {
        SettingsBinding.unwrapped(display(config, key, path), fallback: fallback, nilAtFallback: true)
    }
}

/// The connected displays a page offers, and the one it shows.
@MainActor enum CDisplays {
    /// Connected displays in the registry's order; `externalOnly` for Hardware Controls.
    static func online(_ runtime: DisplaysRuntimeState, externalOnly: Bool = false) -> [DisplayInfo] {
        runtime.displays.filter { $0.isOnline && (!externalOnly || !$0.isBuiltin) }
    }

    /// The shared selection (`SettingsShell.selectedDisplay`), or the first display, as `PerDisplayPicker` shows it.
    static func selected(_ displays: [DisplayInfo], _ selection: DisplayKey?) -> DisplayInfo? {
        displays.first { $0.key == selection } ?? displays.first
    }

    static func tiles(_ displays: [DisplayInfo]) -> [DisplayTile] {
        displays.map {
            DisplayTile(id: $0.key, name: name($0), isBuiltin: $0.isBuiltin, badges: $0.isMain ? [L("Main")] : [])
        }
    }

    static func name(_ display: DisplayInfo) -> String { TextSanitizer.clean(display.name, maxScalars: 64) }

    /// The page environment for a page built without one (a route opened by F's `DisplaysPage.destination`).
    static var environment: DisplaysPageEnvironment? { SettingsShell.shared.host?.displays.pageEnvironment }
}

/// Live hardware sliders on C's pages: every change goes through the shared `DisplaysContext.live` (C's
/// `DisplayLiveController`, a latest-wins mailbox per display and control); `.ended` repeats the final value so the
/// mailbox always delivers it. A drag's local value lives in `SliderSetting`, never here.
@MainActor final class CLiveDrag: ObservableObject {
    private struct Slot: Hashable {
        let key: DisplayKey
        let control: LiveControl
    }

    private var dragging: Set<Slot> = []
    private var lastSent: [Slot: Double] = [:]

    init() {}

    /// A value change: part of a drag, or a single change (keyboard, VoiceOver, a click on the track).
    func set(_ control: LiveControl, _ value: Double, key: DisplayKey, context: DisplaysContext?) {
        let slot = Slot(key: key, control: control)
        lastSent[slot] = value
        context?.live.set(control, value, for: key, phase: dragging.contains(slot) ? .changed : .ended)
    }

    /// `SliderSetting`'s drag phases.
    func phase(_ control: LiveControl, _ phase: DragPhase, current: Double, key: DisplayKey, context: DisplaysContext?) {
        let slot = Slot(key: key, control: control)
        switch phase {
        case .began:
            dragging.insert(slot)
            lastSent[slot] = current
            context?.live.set(control, current, for: key, phase: .began)
        case .changed:
            break
        case .ended:
            dragging.remove(slot)
            context?.live.set(control, lastSent[slot] ?? current, for: key, phase: .ended)
            lastSent[slot] = nil
        }
    }
}

/// What a C page shows while Displays is off or still starting.
struct CDisplaysOffSection: View {
    @ObservedObject var runtime: DisplaysRuntimeState
    let running: Bool

    var body: some View {
        Section {
            if !running {
                StatusRow(L("Turn on Displays to use these settings."), actions: [
                    StatusAction(title: L("Turn On Displays")) {
                        SettingsShell.shared.moduleEnabled(.displays).wrappedValue = true
                    },
                ])
            } else if case .degraded(let reason) = runtime.moduleState {
                StatusRow(reason, style: .warning)
            } else {
                StatusRow(L("Starting…"))
            }
        }
    }
}

/// "<Feature> is off." with Turn On, for settings whose feature switch lives on Displays › Advanced; the reason
/// instead when the feature can't run on this Mac, or is on but paused (another app, Safe Mode).
struct CFeatureOffSection: View {
    let title: String
    let feature: DisplayFeature
    /// The stored switch (`FeatureGraph.rawState`).
    let isOn: Bool
    let context: DisplaysContext?
    @ObservedObject var switcher: DisplaysFeatureSwitcher

    var body: some View {
        Section {
            if let reason = switcher.unavailableReason([feature]) {
                StatusRow(reason, style: .info)
            } else if isOn {
                StatusRow(context?.otherApps.pauseReason(for: feature) ?? L("\(title) isn’t available right now."),
                          symbol: "pause.circle")
            } else {
                StatusRow(L("\(title) is off."), actions: [
                    StatusAction(title: L("Turn On")) {
                        switcher.binding([feature], title: title).wrappedValue = true
                    },
                ])
            }
        }
    }
}

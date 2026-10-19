import Foundation

/// Another display utility Snaptic knows about (PLAN §3.8).
package struct OtherDisplayApp: Equatable, Sendable, Identifiable {
    package let id: String
    package let name: String
    /// Matched exactly or as a prefix followed by "." (betas, setapp builds).
    package let bundlePrefixes: [String]
    /// Snaptic features that fight with it over the same hardware or keys.
    package let overlapping: Set<DisplayFeature>

    package init(id: String, name: String, bundlePrefixes: [String], overlapping: Set<DisplayFeature>) {
        self.id = id
        self.name = name
        self.bundlePrefixes = bundlePrefixes
        self.overlapping = overlapping
    }

    package func matches(bundleID: String) -> Bool {
        bundlePrefixes.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }
}

/// BetterDisplay, MonitorControl and Lunar, by bundle-ID prefix (PLAN §3.8).
package enum OtherDisplayApps {
    /// Brightness, DDC and media keys: what every one of them drives.
    private static let brightnessAndKeys: Set<DisplayFeature> = [
        .brightness, .brightnessApple, .brightnessDDC, .brightnessGamma, .brightnessOverlay, .brightnessRestore,
        .dimToBlack, .dimOnLock, .sync, .ddcControls, .ddcInput, .ddcPower, .ddcCustom,
        .brightnessKeys, .volumeKeys, .osd, .osdBroadcast,
    ]

    package static let known: [OtherDisplayApp] = [
        OtherDisplayApp(
            id: "betterdisplay", name: "BetterDisplay", bundlePrefixes: ["pro.betterdisplay"],
            overlapping: brightnessAndKeys.union([
                .xdr, .nits, .color, .virtualScreens, .smartHiDPI, .hdrVirtual, .hiddenModes, .protection,
                .layouts, .pip, .pipFilters, .menuBarOverlays, .disconnect, .autoDisconnectBuiltin,
            ])),
        OtherDisplayApp(
            id: "monitorcontrol", name: "MonitorControl", bundlePrefixes: ["me.guillaumeb.MonitorControl"],
            overlapping: brightnessAndKeys),
        OtherDisplayApp(
            id: "lunar", name: "Lunar", bundlePrefixes: ["fyi.lunar.Lunar", "site.lunarapp.Lunar"],
            overlapping: brightnessAndKeys.union([.xdr, .nits, .disconnect, .autoDisconnectBuiltin])),
    ]

    /// Known apps among running bundle identifiers, in `known` order, each once.
    package static func detect(bundleIDs: [String]) -> [OtherDisplayApp] {
        known.filter { app in bundleIDs.contains { app.matches(bundleID: $0) } }
    }

    /// Feature → the app it is paused for (the first running app that overlaps).
    /// Nothing is paused with "Run both anyway". Always-on features are never paused.
    package static func paused(running: [OtherDisplayApp], policy: OtherAppsPolicy) -> [DisplayFeature: OtherDisplayApp] {
        guard policy == .pauseOverlapping else { return [:] }
        var result: [DisplayFeature: OtherDisplayApp] = [:]
        for app in running {
            for feature in app.overlapping where result[feature] == nil && !FeatureGraph.alwaysOn.contains(feature) {
                result[feature] = app
            }
        }
        return result
    }

    /// Sentence case, for settings rows and the command line ("Paused while MonitorControl runs").
    package static func pauseReason(_ app: OtherDisplayApp) -> String {
        L("Paused while ") + app.name + L(" runs")
    }

    /// Title Case, for the menu's status row ("Paused While MonitorControl Runs"); the app name stays as it is.
    package static func menuPauseReason(_ app: OtherDisplayApp) -> String {
        L("Paused While ") + app.name + L(" Runs")
    }
}

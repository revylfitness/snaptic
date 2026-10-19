import Foundation

// The 0.2 controls removed with a reason (lead; PLAN 0.3 §4.8.1, last table). Every other ControlLegacy id has a
// home in some control table's `replaces:`.

package enum ControlRemovals {
    package static var removed: [LegacyControlID: String] {
        var map: [LegacyControlID: String] = [:]
        func remove(_ ids: [String], _ reason: String) {
            for id in ids { map[LegacyControlID(rawValue: id)] = reason }
        }
        remove(["l.d.overview.activeFeatures"],
               "Developer statistic; Display Information lists effective and unavailable features")
        remove(["l.d.features.featureOffRows", "l.d.brightness.featureOffRows", "l.d.ddc.featureOffRows",
                "l.d.arrangement.featureOffRows"],
               "\u{201C}X is off · Turn On\u{201D} rows are replaced by FeatureHighlights and header/section switches (§4.4 #6)")
        remove(["l.d.diagnostics.refresh"], "Display Information refreshes on change")
        remove(["l.d.pip.intro"], "FeatureHighlights while Picture in Picture is off")
        remove(["l.onboarding.useTheseFeatures"], "One primary button, in the window footer (§4.7)")
        remove(["l.d.arrangement.powerSwitch", "l.menu.d.powerSwitch"],
               "No switches in menu device rows; migration M10 promotes Disconnect / Turn Off Display (parity M6)")
        remove(["l.menu.c.brightness.method"],
               "Expert choice; Brightness › Advanced › Brightness methods (no submenus in submenus)")
        remove(["l.menu.fixed.quickMenu", "l.menu.d.connectAll.quick", "l.menu.b.restoreAll.quick",
                "l.menu.f.quick.redetect"],
               "Right-click menu removed (C3); each item has a Display Tools twin")
        remove(["l.menu.fixed.tools.moreFeatures"],
               "\u{201C}Display Settings…\u{201D} in each display submenu and \u{201C}Snaptic Settings…\u{201D} cover it (parity minor 3)")
        remove(["l.dfeat.overview", "l.dfeat.diagnostics"],
               "Always on, with no switch; the Displays page and Display Information are always there")
        remove(["l.menu.d.sleepPrevention"],
               "Moved to Awake: a rule keeps the Mac awake while a display is connected (migration M1)")
        return map
    }
}

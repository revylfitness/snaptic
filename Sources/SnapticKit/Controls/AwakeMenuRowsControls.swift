import Foundation

// AwakeMenuRows' controls (owner: G; PLAN 0.3 §5.3, §5.4, R5-10, R5-11): the Awake menu and the compact Awake section
// in the Snaptic menu share one row set; the compact section omits the separators and Awake Settings…. Awake is new in
// 0.3, so nothing here replaces a 0.2 control (Displays' sleep prevention moved to rules through migration M1).

package enum AwakeMenuRowsControls: ControlTable {
    package static let surface = "menu.awake"

    private static let awakeMenu = MenuPlacementSpec("Awake menu", customize: .none)
    private static let startSubmenu = MenuPlacementSpec("Awake menu, Start Session submenu", customize: .none)
    private static let appSubmenu = MenuPlacementSpec("Awake menu, While an App Is Running submenu", customize: .none)
    private static let rulesSubmenu = MenuPlacementSpec("Awake menu, Rules submenu", customize: .none)

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.awake.header", .menuSwitchHeader, menu: awakeMenu),
        ControlSpec("menu.awake.startDefault", .menuItem, when: [.state(.awakeIdle)], menu: awakeMenu),
        ControlSpec("menu.awake.turnOff", .menuItem, when: [.state(.awakeActive)], menu: awakeMenu),
        ControlSpec("menu.awake.add15", .menuItem, when: [.state(.awakeActive), .state(.timedOrCapped)], menu: awakeMenu),
        ControlSpec("menu.awake.addHour", .menuItem, when: [.state(.awakeActive), .state(.timedOrCapped)], menu: awakeMenu),
        ControlSpec("menu.awake.addTime", .menuItem, when: [.state(.awakeActive), .state(.timedOrCapped)], menu: awakeMenu),
        ControlSpec("menu.awake.keepDisplayOn", .menuItem, when: [.state(.awakeActive)], menu: awakeMenu),
        ControlSpec("menu.awake.endHolds", .menuItem, when: [.state(.awakeActive), .state(.holdsExist)], menu: awakeMenu),
        ControlSpec("menu.awake.startSession", .menuSubmenu, menu: awakeMenu),
        ControlSpec("menu.awake.preset", .menuItem, when: [.perItem("preset")], menu: startSubmenu),
        ControlSpec("menu.awake.custom", .menuItem, menu: startSubmenu),
        ControlSpec("menu.awake.whileApp", .menuSubmenu, menu: awakeMenu),
        ControlSpec("menu.awake.app", .menuItem, when: [.perItem("app")], menu: appSubmenu),
        ControlSpec("menu.awake.noApps", .menuItem, menu: appSubmenu),
        ControlSpec("menu.awake.rules", .menuSubmenu, when: [.awakeFeature(.triggers), .state(.rulesExist)], menu: awakeMenu),
        ControlSpec("menu.awake.rule", .menuItem, when: [.awakeFeature(.triggers), .perItem("rule")], menu: rulesSubmenu),
        ControlSpec("menu.awake.ruleEnd", .menuItem, when: [.awakeFeature(.triggers), .perItem("rule")], menu: rulesSubmenu),
        ControlSpec("menu.awake.pauseHour", .menuItem, when: [.awakeFeature(.triggers)], menu: rulesSubmenu),
        ControlSpec("menu.awake.pauseTomorrow", .menuItem, when: [.awakeFeature(.triggers)], menu: rulesSubmenu),
        ControlSpec("menu.awake.resumeRules", .menuItem, when: [.awakeFeature(.triggers), .state(.rulesPaused)],
                    menu: rulesSubmenu),
        ControlSpec("menu.awake.editRules", .menuItem, when: [.awakeFeature(.triggers)], menu: rulesSubmenu),
        ControlSpec("menu.awake.settings", .menuItem, menu: awakeMenu),
        ControlSpec("menu.awake.recentNotices", .menuSubmenu, menu: awakeMenu),
        ControlSpec("menu.awake.notice", .menuItem, when: [.perItem("notice")], menu: awakeMenu),
        ControlSpec("menu.awake.clearNotices", .menuItem, menu: awakeMenu),
        ControlSpec("menu.awake.quit", .menuItem, menu: awakeMenu),
    ]
}

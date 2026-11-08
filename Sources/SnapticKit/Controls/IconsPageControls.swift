import Foundation

// Settings › Hidden Icons (lead; PLAN 0.4 §4.9, §4.17): the Use Hidden Icons switch, the status row and its state
// actions, automatic hiding, launch hiding, Always Hidden, dividers, the shortcut, Sections ›, How to Arrange…, and
// the footer's Restore Defaults… and Advanced…. New in 0.4: nothing here replaces a 0.2 control.

package enum IconsPageControls: ControlTable {
    package static let surface = "icons.page"
    /// The How to Arrange sheet (no controls of its own; Done closes it).
    package static let arrangeSheet = "icons.arrange"

    private static let root = SettingsRootID.hiddenIcons
    private static let icons: [ControlCondition] = [.module(.hiddenIcons)]

    package static let controls: [ControlSpec] = [
        ControlSpec("icons.page.useHiddenIcons", .setting, keys: ["modules.*.enabled"],
                    search: SearchSpec("Use Hidden Icons", keywords: ["hidden bar", "bartender", "hide menu bar icons",
                                                                      "menu bar items", "declutter", "arrow"],
                                       root: root)),
        // The status row's button: Show Icons / Hide Icons, or the state's own action.
        ControlSpec("icons.page.showIcons", .statusAction, when: icons + [.state(.iconsCollapsed)]),
        ControlSpec("icons.page.hideIcons", .statusAction, when: icons + [.state(.iconsExpanded)]),
        ControlSpec("icons.page.openPrivacy", .statusAction, when: icons + [.state(.iconsNeedsPermission)]),
        ControlSpec("icons.page.relaunch", .statusAction, when: icons + [.state(.iconsNotEffective)]),
        ControlSpec("icons.page.showArrow", .statusAction, when: icons + [.state(.iconsArrowMissing)]),
        ControlSpec("icons.page.tryAgain", .statusAction, when: icons + [.state(.iconsCrashGuard)]),
        ControlSpec("icons.page.arrangeNow", .statusAction, when: icons + [.state(.iconsFirstRun)]),
        // Rows.
        ControlSpec("icons.page.autoCollapse", .setting, when: icons, keys: ["autoCollapse", "autoCollapseSeconds"],
                    search: SearchSpec("Hide icons automatically", keywords: ["auto collapse", "seconds", "timer",
                                                                              "delay"], root: root)),
        ControlSpec("icons.page.collapseAtLaunch", .setting, when: icons, keys: ["collapseAtLaunch"],
                    search: SearchSpec("Hide icons when Snaptic opens", keywords: ["launch", "login", "start"],
                                       root: root)),
        ControlSpec("icons.page.alwaysHidden", .setting, when: icons, keys: ["alwaysHidden"],
                    search: SearchSpec("Always Hidden section", keywords: ["option-click", "always hidden", "divider"],
                                       root: root)),
        ControlSpec("icons.page.dividers", .setting, when: icons, keys: ["dividers"],
                    search: SearchSpec("Section dividers", keywords: ["separator", "divider", "bar"], root: root)),
        ControlSpec("icons.page.shortcut", .shortcut, when: icons, keys: ["shortcut"],
                    search: SearchSpec("Show or hide icons", keywords: ["shortcut", "hotkey", "keyboard"], root: root)),
        ControlSpec("icons.page.sections", .navigation, when: icons,
                    search: SearchSpec("Sections", keywords: ["hidden icons list", "always show", "always hide",
                                                              "per app"], root: root)),
        ControlSpec("icons.page.howToArrange", .button, when: icons,
                    search: SearchSpec("How to Arrange", keywords: ["command drag", "move icons", "order"],
                                       root: root)),
        // Footer.
        ControlSpec("icons.page.restore", .button, when: icons, keys: IconsConfig.exportedKeys,
                    search: SearchSpec("Restore Hidden Icons defaults", keywords: ["reset", "defaults"], root: root)),
        ControlSpec("icons.page.advanced", .button, when: icons,
                    search: SearchSpec("Hidden Icons advanced settings", keywords: ["advanced", "more"], root: root)),
    ]
}

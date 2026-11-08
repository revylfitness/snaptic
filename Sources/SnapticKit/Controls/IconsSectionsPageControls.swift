import Foundation

// Hidden Icons › Sections (lead; PLAN 0.4 §4.9 Sections, G-7, X-21): the live or cached list under Shown, Hidden and
// Always Hidden; on macOS 27 each app's Where It Is / Always Show / Always Hide pop-up; Refresh (or Show All Icons and
// Refresh while the read is limited); Open Privacy Settings without the permission.

package enum IconsSectionsPageControls: ControlTable {
    package static let surface = "icons.sections"

    private static let root = SettingsRootID.hiddenIcons
    private static let icons: [ControlCondition] = [.module(.hiddenIcons)]

    package static let controls: [ControlSpec] = [
        ControlSpec("icons.sections.list", .list, when: icons,
                    search: SearchSpec("Icons in each section", keywords: ["shown", "hidden", "always hidden", "list"],
                                       root: root, route: SettingsRoute(surface))),
        ControlSpec("icons.sections.choice", .setting,
                    when: icons + [.iconsEngine(.native), .perItem("app")], keys: ["choices"],
                    search: SearchSpec("Always show or hide an app’s icons",
                                       keywords: ["always show", "always hide", "where it is", "per app"], root: root,
                                       route: SettingsRoute(surface))),
        ControlSpec("icons.sections.refresh", .button, when: icons,
                    search: SearchSpec("Refresh the icon list", keywords: ["reload", "update"], root: root,
                                       route: SettingsRoute(surface))),
        ControlSpec("icons.sections.showAllAndRefresh", .statusAction,
                    when: icons + [.iconsEngine(.native), .state(.iconsRestricted)]),
        ControlSpec("icons.sections.openPrivacy", .statusAction, when: icons + [.state(.accessibilityMissing)]),
    ]
}

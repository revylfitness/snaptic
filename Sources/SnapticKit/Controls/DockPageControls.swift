import Foundation

// Settings › Dock Previews (lead; PLAN 0.5 §4.17, §4.18, §4.11): the Use Dock Previews switch, the status row and its
// added rows' actions, the Previews and Dock click actions sections, and the footer's Restore Defaults… and
// Advanced…. New in 0.5: nothing here replaces an earlier control.

package enum DockPageControls: ControlTable {
    package static let surface = "dock.page"

    private static let root = SettingsRootID.dockPreviews
    private static let dock: [ControlCondition] = [.module(.dockPreviews)]

    package static let controls: [ControlSpec] = [
        ControlSpec("dock.page.useDockPreviews", .setting, keys: ["modules.*.enabled"],
                    search: SearchSpec("Use Dock Previews", keywords: ["dockdoor", "hyperdock", "dock preview", "hover",
                                                                       "window preview", "thumbnail"], root: root)),
        // The status row's button (§4.17): rows 4 to 8, and Resume for a pause held under Starting, row 4 or row 5.
        ControlSpec("dock.page.openPrivacy", .statusAction, when: dock + [.state(.dockNeedsPermission)]),
        ControlSpec("dock.page.tryAgain", .statusAction, when: dock + [.state(.dockUnreadable)]),
        ControlSpec("dock.page.otherToolAdvanced", .statusAction, when: dock + [.state(.dockOtherTool)]),
        ControlSpec("dock.page.voiceOverAdvanced", .statusAction, when: dock + [.state(.dockVoiceOver)]),
        ControlSpec("dock.page.resume", .statusAction, when: dock + [.state(.dockCommandPause)]),
        // Added rows below the status row: thumbnails without Screen Recording, a tripped breaker (click actions or
        // keys) and one crash-guard stop per WindowFeature.
        ControlSpec("dock.page.thumbnailsPrivacy", .statusAction, when: dock + [.state(.screenRecordingMissing)]),
        ControlSpec("dock.page.relaunch", .statusAction, when: dock + [.state(.dockBreakerTripped)]),
        ControlSpec("dock.page.crashGuardTryAgain", .statusAction,
                    when: dock + [.state(.dockCrashGuard), .perItem("windowFeature")]),
        // Previews.
        ControlSpec("dock.page.delay", .setting, when: dock, keys: ["delay"],
                    search: SearchSpec("Show previews after", keywords: ["delay", "hover", "seconds", "immediately",
                                                                         "wait"], root: root)),
        ControlSpec("dock.page.cardSize", .setting, when: dock, keys: ["cardSize"],
                    search: SearchSpec("Card size", keywords: ["small", "medium", "large", "preview size"],
                                       root: root)),
        ControlSpec("dock.page.thumbnails", .setting, when: dock, keys: ["thumbnails"],
                    search: SearchSpec("Window thumbnails", keywords: ["screen recording", "pictures", "titles",
                                                                       "preview"], root: root)),
        ControlSpec("dock.page.includeMinimizedAndHidden", .setting, when: dock, keys: ["includeMinimizedAndHidden"],
                    search: SearchSpec("Include minimized and hidden windows",
                                       keywords: ["minimized", "hidden apps", "minimised"], root: root)),
        ControlSpec("dock.page.otherSpaces", .setting, when: dock, keys: ["otherSpaces"],
                    search: SearchSpec("Windows on other Spaces", keywords: ["spaces", "desktops", "mission control"],
                                       root: root)),
        // Dock click actions (`Dock.disable.clickActions` disables the section and shows its lock row under it).
        ControlSpec("dock.page.clickActions", .setting, when: dock, keys: ["clickActions"],
                    search: SearchSpec("When you click the active app in the Dock",
                                       keywords: ["dock click", "hide the app", "minimize", "click"], root: root)),
        ControlSpec("dock.page.restoreAllMinimized", .setting, when: dock, keys: ["restoreAllMinimized"],
                    search: SearchSpec("Restore all minimized windows",
                                       keywords: ["unminimize", "dock click", "minimized", "bring back"], root: root)),
        ControlSpec("dock.page.clickActionsLock", .list, when: dock + [.perItem("killSwitch")]),
        // Footer (Starting and rows 3 to 9). Never the shared privacy keys (§4.10).
        ControlSpec("dock.page.restore", .button, when: dock, keys: DockConfig.exportedKeys,
                    search: SearchSpec("Restore Dock Previews defaults", keywords: ["reset", "defaults"], root: root)),
        ControlSpec("dock.page.advanced", .button, when: dock,
                    search: SearchSpec("Dock Previews advanced settings", keywords: ["advanced", "more"], root: root)),
    ]
}

import Foundation

// Displays › Automations (owner A; PLAN 0.3 §4.3 sub-page table "Automations"): the two section switches (event
// hooks, custom actions), each section's list with its row controls and Add… button, the status rows, and the
// footer's Delete All Hooks and Actions…. Each list row opens its editor sheet (HookEditorSheet, ActionEditorSheet).
// Budget (§4.3 counts): 2 settings + 2 lists + 2 buttons = 6.

package enum AutomationsPageControls: ControlTable {
    package static let surface = "displays.automations"

    private static let root = SettingsRootID.displays
    private static let route = SettingsRoute(surface)
    private static let hookRow: [ControlCondition] = [.module(.displays), .perItem("hook")]
    private static let actionRow: [ControlCondition] = [.module(.displays), .perItem("customAction")]

    private static func find(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: route)
    }

    package static let controls: [ControlSpec] = [
        // Event hooks
        ControlSpec("displays.automations.hooks", .setting, when: [.module(.displays)], replaces: ["l.dfeat.hooks"],
                    keys: ["features.hooks"],
                    search: find("Event hooks", ["automation", "run a program", "script", "display connects",
                                                 "display disconnects", "sleep", "wake"])),
        ControlSpec("displays.automations.hookList", .list, when: [.module(.displays)], keys: ["automation.hooks"],
                    search: find("Hooks", ["automation", "programs"])),
        ControlSpec("displays.automations.hookEnabled", .setting, when: hookRow,
                    replaces: ["l.d.automation.hook.enabled"], keys: ["automation.hooks.*.enabled"],
                    search: find("Turn a hook on or off", ["enable hook", "disable hook"])),
        ControlSpec("displays.automations.hookDetails", .button, when: hookRow,
                    search: find("Hook details", ["edit hook"])),
        ControlSpec("displays.automations.addHook", .button, when: [.module(.displays)],
                    search: find("Add Hook", ["new hook", "automation"])),
        // Custom actions
        ControlSpec("displays.automations.actions", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.customActions"], keys: ["features.customActions"],
                    search: find("Custom actions", ["automation", "run a program", "script", "menu", "shortcut"])),
        ControlSpec("displays.automations.actionList", .list, when: [.module(.displays)], keys: ["automation.actions"],
                    search: find("Actions", ["custom actions", "programs"])),
        ControlSpec("displays.automations.actionShowInMenu", .setting, when: actionRow,
                    replaces: ["l.d.automation.action.showInMenu"], keys: ["automation.actions.*.showInMenu"],
                    search: find("Show an action in the menu", ["Actions submenu", "Displays menu"])),
        ControlSpec("displays.automations.actionDetails", .button, when: actionRow,
                    search: find("Action details", ["edit action"])),
        ControlSpec("displays.automations.addAction", .button, when: [.module(.displays)],
                    search: find("Add Action", ["new custom action", "automation"])),
        // Status rows and footer
        ControlSpec("displays.automations.status.resume", .statusAction,
                    when: [.module(.displays), .state(.automationPaused)]),
        ControlSpec("displays.automations.status.clearProblem", .statusAction, when: [.module(.displays)]),
        ControlSpec("displays.automations.restore", .button, when: [.module(.displays)],
                    search: find("Delete All Hooks and Actions", ["restore automations defaults", "reset"])),
    ]
}

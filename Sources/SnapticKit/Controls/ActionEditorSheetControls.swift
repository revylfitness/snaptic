import Foundation

// Displays › Automations › a custom action's Details… sheet (owner A; PLAN 0.3 §4.3 "Actions list (Show in menu,
// Details… sheet with Run Now)", §4.8 Automation row): every 0.2 action field except Show in menu, which is the list
// row's checkbox. The shortcut is also listed in Keyboard › Keyboard Shortcuts… (C). One sheet per action, so search
// leads to the Automations page.

package enum ActionEditorSheetControls: ControlTable {
    package static let surface = "displays.automations.action"

    private static let root = SettingsRootID.displays
    private static let route = SettingsRoute(AutomationsPageControls.surface)
    private static let perAction: [ControlCondition] = [.module(.displays), .perItem("customAction")]

    private static func find(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: route)
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.automations.action.name", .setting, when: perAction,
                    replaces: ["l.d.automation.action.name"], keys: ["automation.actions.*.name"],
                    search: find("Action name", ["rename action"])),
        ControlSpec("displays.automations.action.program", .setting, when: perAction,
                    replaces: ["l.d.automation.action.program"], keys: ["automation.actions.*.command.executable"],
                    search: find("Action program", ["executable", "path", "script"])),
        ControlSpec("displays.automations.action.choose", .button, when: perAction),
        ControlSpec("displays.automations.action.arguments", .list, when: perAction,
                    replaces: ["l.d.automation.action.arguments"], keys: ["automation.actions.*.command.arguments"],
                    search: find("Action arguments", ["parameters", "options"])),
        // The action's own shortcut is the home of its registered action (`a.custom.<id>`, l.action.a.custom.*).
        ControlSpec("displays.automations.action.shortcut", .shortcut, when: perAction,
                    replaces: ["l.d.automation.action.shortcut", "l.action.a.custom.*"],
                    keys: ["automation.actions.*.shortcut"],
                    search: find("Action shortcut", ["hotkey", "keyboard shortcut"])),
        ControlSpec("displays.automations.action.cliAllowed", .setting, when: perAction,
                    replaces: ["l.d.automation.action.cliAllowed"], keys: ["automation.actions.*.cliAllowed"],
                    search: find("Allow an action from the command line", ["snaptic action run", "CLI", "terminal"])),
        ControlSpec("displays.automations.action.runNow", .button,
                    when: perAction + [.displayFeature(.customActions)], replaces: ["l.d.automation.action.runNow"],
                    search: find("Run Now", ["test action", "run action"])),
        ControlSpec("displays.automations.action.delete", .button, when: perAction,
                    replaces: ["l.d.automation.action.delete"]),
    ]
}

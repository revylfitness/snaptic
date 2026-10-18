import Foundation

// Displays › Automations › a hook's Details… sheet (owner A; PLAN 0.3 §4.3 "Hooks list (Enabled, When, Details…
// sheet)", §4.8 Automation row): every 0.2 hook field except Enabled, which is the list row's switch. The sheet
// edits the stored hook directly (fixes [UA] B2). One sheet per hook, so search leads to the Automations page.

package enum HookEditorSheetControls: ControlTable {
    package static let surface = "displays.automations.hook"

    private static let root = SettingsRootID.displays
    private static let route = SettingsRoute(AutomationsPageControls.surface)
    private static let perHook: [ControlCondition] = [.module(.displays), .perItem("hook")]

    private static func find(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: route)
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.automations.hook.name", .setting, when: perHook, replaces: ["l.d.automation.hook.name"],
                    keys: ["automation.hooks.*.name"], search: find("Hook name", ["rename hook"])),
        ControlSpec("displays.automations.hook.event", .setting, when: perHook, replaces: ["l.d.automation.hook.event"],
                    keys: ["automation.hooks.*.event"],
                    search: find("When a hook runs", ["connects", "disconnects", "sleep", "wake", "event"])),
        ControlSpec("displays.automations.hook.display", .setting, when: perHook,
                    replaces: ["l.d.automation.hook.display"], keys: ["automation.hooks.*.display"],
                    search: find("Display a hook watches", ["any display", "which display"])),
        ControlSpec("displays.automations.hook.delay", .setting, when: perHook, replaces: ["l.d.automation.hook.delay"],
                    keys: ["automation.hooks.*.delaySeconds"], search: find("Delay after wake", ["wait", "seconds"])),
        ControlSpec("displays.automations.hook.program", .setting, when: perHook,
                    replaces: ["l.d.automation.hook.program"], keys: ["automation.hooks.*.command.executable"],
                    search: find("Hook program", ["executable", "path", "script"])),
        ControlSpec("displays.automations.hook.choose", .button, when: perHook, replaces: ["l.d.automation.hook.choose"]),
        ControlSpec("displays.automations.hook.arguments", .list, when: perHook,
                    replaces: ["l.d.automation.hook.arguments"], keys: ["automation.hooks.*.command.arguments"],
                    search: find("Hook arguments", ["parameters", "options"])),
        ControlSpec("displays.automations.hook.delete", .button, when: perHook),
    ]
}

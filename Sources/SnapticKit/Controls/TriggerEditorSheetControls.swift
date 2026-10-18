import Foundation

// The rule editor (owner: G; PLAN 0.3 §4.3 "Rule editor sheet", §2.7, parity minor 5, design M4): On, Name,
// Conditions (all / any, up to 8 rows of kind · is / is not · value; CriterionEditors), Session options, Timing and
// "After I turn it off"; Delete Rule… · Cancel / Done. It edits one rule from the Awake page's list, so its search
// entries reveal that list.

package enum TriggerEditorSheetControls: ControlTable {
    package static let surface = "awake.rule"

    private static let root = SettingsRootID.awake
    private static let rule: [ControlCondition] = [.module(.awake), .perItem("rule")]
    private static let condition: [ControlCondition] = [.module(.awake), .perItem("rule"), .perItem("condition")]

    package static let controls: [ControlSpec] = [
        ControlSpec("awake.rule.on", .setting, when: rule,
                    search: SearchSpec("Rule on or off", keywords: ["disable rule"], root: root)),
        ControlSpec("awake.rule.name", .setting, when: rule,
                    search: SearchSpec("Rule name", keywords: ["rename rule"], root: root)),
        ControlSpec("awake.rule.match", .setting, when: rule,
                    search: SearchSpec("All or any conditions", keywords: ["and", "or"], root: root)),
        ControlSpec("awake.rule.conditions", .list, when: rule, keys: ["triggers.triggers"]),
        ControlSpec("awake.rule.condition.kind", .setting, when: condition,
                    search: SearchSpec("Rule conditions", keywords: ["app", "display", "power", "battery", "schedule",
                                                                     "CPU", "audio", "idle", "drive", "USB", "network",
                                                                     "VPN", "Bluetooth"], root: root)),
        ControlSpec("awake.rule.condition.negated", .setting, when: condition,
                    search: SearchSpec("Condition is or is not", keywords: ["not", "negate"], root: root)),
        ControlSpec("awake.rule.condition.value", .setting, when: condition,
                    search: SearchSpec("Condition value", keywords: ["which app", "which display", "which network"],
                                       root: root)),
        ControlSpec("awake.rule.condition.add", .button, when: rule),
        ControlSpec("awake.rule.condition.remove", .button, when: condition),
        ControlSpec("awake.rule.display", .setting, when: rule,
                    search: SearchSpec("Rule display", keywords: ["keep display on", "display can turn off"],
                                       root: root)),
        ControlSpec("awake.rule.activity", .setting, when: rule + [.awakeFeature(.activity)],
                    search: SearchSpec("Rule activity", keywords: ["appear active"], root: root)),
        ControlSpec("awake.rule.startDelay", .setting, when: rule,
                    search: SearchSpec("Wait before starting", keywords: ["delay", "timing"], root: root)),
        ControlSpec("awake.rule.endDelay", .setting, when: rule,
                    search: SearchSpec("Wait before ending", keywords: ["delay", "hysteresis", "timing"], root: root)),
        ControlSpec("awake.rule.resume", .setting, when: rule,
                    search: SearchSpec("After I turn it off", keywords: ["resume", "reactivate"], root: root)),
        ControlSpec("awake.rule.delete", .button, when: rule),
        ControlSpec("awake.rule.cancel", .button, when: rule),
        ControlSpec("awake.rule.done", .button, when: rule),
    ]
}

import Foundation

// Awake › History (owner: G; PLAN 0.3 §4.3 "History", parity minor 12): totals (Today, Last 7 days), the list with
// Start Again where it is offered, and Clear History…. Local only: never exported or in diagnostics.

package enum AwakeHistoryPageControls: ControlTable {
    package static let surface = "awake.history"

    private static let root = SettingsRootID.awake
    private static let route = SettingsRoute("awake.history")
    private static let history: [ControlCondition] = [.module(.awake), .awakeFeature(.history)]

    package static let controls: [ControlSpec] = [
        ControlSpec("awake.history.totals", .list, when: history,
                    search: SearchSpec("Time kept awake", keywords: ["today", "last 7 days", "statistics", "total"],
                                       root: root, route: route)),
        ControlSpec("awake.history.list", .list, when: history,
                    search: SearchSpec("Past sessions", keywords: ["history", "log"], root: root, route: route)),
        ControlSpec("awake.history.startAgain", .button, when: history + [.perItem("entry")],
                    search: SearchSpec("Start Again", keywords: ["repeat session"], root: root, route: route)),
        ControlSpec("awake.history.clear", .button, when: history,
                    search: SearchSpec("Clear History", keywords: ["delete history"], root: root, route: route)),
    ]
}

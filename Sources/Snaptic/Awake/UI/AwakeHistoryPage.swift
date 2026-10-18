import SwiftUI
import SnapticKit

/// Awake › History (owner: G; PLAN 0.3 §4.3 "History", §1.1 `history`, parity minor 12, r3 consistency m3): today's
/// and the last 7 days' totals, the sessions by day (newest first) with Start Again in each row's context menu (and as
/// a VoiceOver action) where it is offered (not for command-line, process or rule entries), and Clear History…. Local
/// only: never exported, logged or put in diagnostics.
struct AwakeHistoryPage: View, ControlDeclaring {
    typealias Controls = AwakeHistoryPageControls

    let env: AwakePageEnvironment
    @ObservedObject private var history: ConfigStore<AwakeHistory>
    @ObservedObject private var runtime: AwakeRuntimeState
    @StateObject private var sessions: ConfigSlice<AwakeConfig, AwakeSessionsConfig>
    @StateObject private var triggers: ConfigSlice<AwakeConfig, AwakeTriggersConfig>
    @State private var confirmClear = false

    /// Rows shown at most (the store keeps ≤ 500 entries for 90 days).
    static let maxRows = 200

    init(env: AwakePageEnvironment) {
        self.env = env
        _history = ObservedObject(wrappedValue: env.history)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _sessions = StateObject(wrappedValue: ConfigSlice(env.config, \.sessions))
        _triggers = StateObject(wrappedValue: ConfigSlice(env.config, \.triggers))
    }

    var body: some View {
        let entries = history.value.entries
        SettingsPageScaffold(route: AwakePageControls.historyRoute) {
            Section {
                totals
            }
            if entries.isEmpty {
                Section {
                    ContentUnavailableView(L("No Sessions Yet"), systemImage: "cup.and.saucer",
                                           description: Text(L("Sessions you start, and those rules start, appear here.")))
                        .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(days(entries), id: \.start) { day in
                    Section {
                        ForEach(Array(day.entries.enumerated()), id: \.offset) { index, entry in
                            row(entry, anchored: day.isFirst && index == 0)
                        }
                    } header: {
                        Text(day.title)
                            .modifier(OptionalSettingsAnchor(day.isFirst ? ControlID("awake.history.list") : nil))
                    }
                }
                Section {
                } footer: {
                    HStack {
                        Text(L("Kept on this Mac for 90 days."))
                        Spacer(minLength: 8)
                        Button(L("Clear History…"), role: .destructive) { confirmClear = true }
                            .modifier(SettingsAnchor(ControlID("awake.history.clear")))
                    }
                }
            }
        }
        .alert(L("Clear Awake history?"), isPresented: $confirmClear) {
            Button(L("Clear History"), role: .destructive) {
                if !env.history.value.entries.isEmpty { env.history.value = AwakeHistory() }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The list and the totals start over. Your settings stay as they are."))
        }
    }

    // MARK: Totals

    private var totals: some View {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let week = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let t = history.value.totals(todayStart: today.timeIntervalSince1970, weekStart: week.timeIntervalSince1970,
                                     now: now.timeIntervalSince1970)
        return HStack(spacing: 0) {
            total(L("Today"), t.today)
            Divider().frame(height: 36)
            total(L("Last 7 days"), t.week)
        }
        .padding(.vertical, 4)
        .modifier(SettingsAnchor(ControlID("awake.history.totals")))
    }

    private func total(_ title: String, _ seconds: Double) -> some View {
        VStack(spacing: 2) {
            Text(AwakeHistoryText.total(seconds))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    private struct Day {
        let start: Double
        let title: String
        let entries: [AwakeHistoryEntry]
        let isFirst: Bool
    }

    /// Newest first, grouped by local day ("Today", "Yesterday", "Monday, October 12").
    private func days(_ entries: [AwakeHistoryEntry]) -> [Day] {
        let calendar = Calendar.autoupdatingCurrent
        var order: [Double] = []
        var groups: [Double: [AwakeHistoryEntry]] = [:]
        for e in entries.reversed().prefix(Self.maxRows) {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: e.end)).timeIntervalSince1970
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(e)
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        var out: [Day] = []
        for (i, start) in order.enumerated() {
            let date = Date(timeIntervalSince1970: start)
            let title: String
            if calendar.isDateInToday(date) {
                title = L("Today")
            } else if calendar.isDateInYesterday(date) {
                title = L("Yesterday")
            } else {
                title = formatter.string(from: date)
            }
            out.append(Day(start: start, title: title, entries: groups[start] ?? [], isFirst: i == 0))
        }
        return out
    }

    @ViewBuilder private func row(_ entry: AwakeHistoryEntry, anchored: Bool) -> some View {
        let presets = sessions.value.presets
        let presetTitle = entry.presetID.flatMap { id in presets.first { $0.id == id }?.title(AwakeFormat.text) }
        let ruleName = entry.triggerID.flatMap { id in
            triggers.value.triggers.first { $0.id == id }?.displayName(AwakeFormat.text)
        }
        let appName = entry.bundleID.flatMap { AwakeFormat.appName($0) }
        let floor = env.config.value.guards.batteryFloor
        let again = runtime.isEffective(.sessions) ? entry.startAgain(presets: presets) : nil
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AwakeHistoryText.title(entry, presetTitle: presetTitle, appName: appName, ruleName: ruleName))
                Text(AwakeHistoryText.subtitle(entry, startClock: AwakeFormat.clock(entry.start),
                                               endClock: AwakeFormat.clock(entry.end), floor: floor))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let again {
                Button(L("Start Again")) { start(again) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if let again {
                Button(L("Start Again")) { start(again) }
            }
        }
        .modifier(OptionalSettingsAnchor(anchored && again != nil ? ControlID("awake.history.startAgain") : nil))
    }

    /// A UI start (`.settings`): asks `mayStart()` first (R5-8).
    private func start(_ again: AwakeStartAgain) {
        guard SettingsShell.shared.mayStart(), let sessions = env.context?.sessions else { return }
        switch again {
        case .preset(let id):
            _ = sessions.startPreset(id, source: .settings)
        case .kind(let kind):
            _ = sessions.start(kind, options: nil, presetID: nil, source: .settings, overrideGuards: false)
        }
    }
}

import AppKit
import SnapticKit

// App-side formatting and calendar helpers for Awake (owner: G; PLAN 0.3 N12): the Kit formats text by hand, the app
// only supplies what needs the system locale or Calendar (12/24 h once per process, local hour and minute of an
// instant, DST-correct "until 17:30", minutes of the week for schedules, app display names for local UI).

@MainActor enum AwakeFormat {
    /// From the system locale, once per process (N12).
    static let text: AwakeTextContext = {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.autoupdatingCurrent) ?? "h a"
        let decimal = Locale.autoupdatingCurrent.decimalSeparator ?? "."
        return AwakeTextContext(uses24Hour: !template.contains("a"), decimalSeparator: decimal)
    }()

    /// "5:00 PM" / "17:00" for a wall instant in the current time zone.
    static func clock(_ unix: Double) -> String {
        guard unix.isFinite else { return "" }
        let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: unix))
        return AwakeCountdown.clock(hour: c.hour ?? 0, minute: c.minute ?? 0, uses24Hour: text.uses24Hour)
    }

    /// The next wall instant at hour:minute after `now` (DST-correct, `.nextTime`).
    static func nextUnix(hour: Int, minute: Int, after now: Date = Date()) -> Double? {
        var match = DateComponents()
        match.hour = hour
        match.minute = minute
        match.second = 0
        return Calendar.autoupdatingCurrent.nextDate(after: now, matching: match, matchingPolicy: .nextTime)?
            .timeIntervalSince1970
    }

    /// 0..<10080, Sunday 00:00 = 0, local time.
    static func minuteOfWeek(_ date: Date = Date()) -> Int {
        let c = Calendar.autoupdatingCurrent.dateComponents([.weekday, .hour, .minute], from: date)
        let day = ((c.weekday ?? 1) - 1 + 7) % 7
        return day * 1_440 + (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The local display name of an app (running or installed); local UI only, never logged or sent over the CLI.
    static func appName(_ bundleID: String) -> String? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName, !name.isEmpty {
            return TextSanitizer.clean(name, maxScalars: 64)
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        let trimmed = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        return trimmed.isEmpty ? nil : TextSanitizer.clean(trimmed, maxScalars: 64)
    }

    /// An app's icon at menu size (local UI only).
    static func appIcon(_ bundleID: String) -> NSImage? {
        let icon: NSImage?
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            icon = app.icon
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = nil
        }
        guard let copy = icon?.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    /// Whether an app with this bundle id runs now (regular or accessory, not terminated).
    static func isRunning(_ bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
    }

    /// Running regular apps for "While an App Is Running" (Snaptic excluded), recent first, then by name; ≤ limit.
    static func runningApps(recent: [String], limit: Int = 12) -> [(bundleID: String, name: String)] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var apps: [(bundleID: String, name: String)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            guard let id = app.bundleIdentifier, id != own, AwakeBundleID.isValid(id), seen.insert(id).inserted else { continue }
            apps.append((id, TextSanitizer.clean(app.localizedName ?? id, maxScalars: 64)))
        }
        let rank = Dictionary(recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        apps.sort { a, b in
            switch (rank[a.bundleID], rank[b.bundleID]) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        return Array(apps.prefix(limit))
    }
}

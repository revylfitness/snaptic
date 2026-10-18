import SwiftUI
import SnapticKit

// Small building blocks shared by D's settings pages (owner: D).

/// "Feature is off" row with a Turn On button, or the reason it can't be used.
struct ManagementFeatureNotice: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let feature: DisplayFeature
    let title: String

    var body: some View {
        if !env.runtime.isEffective(feature) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("\(title) is off"))
                    if let reason = unavailableReason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    } else if let paused = env.context?.otherApps.pauseReason(for: feature) {
                        Text(paused).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if unavailableReason == nil {
                    Button(L("Turn On")) { env.enableFeature(feature) }
                        .accessibilityLabel(L("Turn on \(title)"))
                }
            }
        }
    }

    private var unavailableReason: String? {
        if case .unavailable(let why) = env.runtime.availability[feature] { return why }
        return nil
    }
}

/// "Displays is off" placeholder for pages that need live controls.
struct ManagementOffNotice: View {
    var body: some View {
        Text(L("Turn on Displays to change these settings for connected displays."))
            .foregroundStyle(.secondary)
    }
}

/// A caption-styled explanatory line.
struct ManagementNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

enum ManagementText {
    static func mode(_ m: ModeRef) -> String {
        var t = "\(m.pointWidth) × \(m.pointHeight)"
        if m.isHiDPI { t += " HiDPI" }
        if m.refreshMilliHz > 0 { t += String(format: " · %.0f Hz", Double(m.refreshMilliHz) / 1000) }
        return t
    }

    static func bytes(_ n: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: n), countStyle: .memory)
    }
}

/// Binding helpers onto the Displays config store.
@MainActor enum ManagementBindings {
    static func config<T>(_ env: DisplaysPageEnvironment, _ path: WritableKeyPath<DisplaysConfig, T>) -> Binding<T> {
        Binding(get: { env.config.value[keyPath: path] }, set: { env.config.value[keyPath: path] = $0 })
    }

    static func perDisplay<T>(_ env: DisplaysPageEnvironment, _ key: DisplayKey,
                              _ path: WritableKeyPath<PerDisplayConfig, T>) -> Binding<T> {
        Binding(get: { (env.config.value.perDisplay[key] ?? PerDisplayConfig())[keyPath: path] },
                set: { newValue in
                    var value = env.config.value
                    var pd = value.perDisplay[key] ?? PerDisplayConfig()
                    pd[keyPath: path] = newValue
                    value.perDisplay[key] = pd.sanitized()
                    env.config.value = value
                })
    }
}

/// Re-renders its content whenever a controller's revision publishes (PLAN 0.3 §4.5): sections that read controller
/// state (busy, live, undo, protection) observe the one id they show.
struct ControllerRevisionReader<Content: View>: View {
    @ObservedObject private var revision: ControllerRevision
    private let content: () -> Content

    init(_ revision: ControllerRevision, @ViewBuilder content: @escaping () -> Content) {
        self.revision = revision
        self.content = content
    }

    var body: some View { content() }
}

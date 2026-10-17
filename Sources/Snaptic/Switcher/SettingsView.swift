import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import SnapticKit

struct AppChoice: Hashable {
    let bundleID: String
    let name: String
}

/// The switcher's settings sections, shown as pages by SwitcherPages (PLAN §3.7).
@MainActor
struct SwitcherShortcutsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section {
            ForEach(settings.config.shortcuts) { shortcut in
                ShortcutEditor(
                    shortcut: shortcut,
                    canDelete: settings.config.shortcuts.count > 1,
                    isDuplicate: settings.config.shortcuts.contains { $0.id != shortcut.id && $0.sameKeys(as: shortcut) },
                    commandShortcutsOff: !settings.config.isOn(.commandTabTakeover),
                    onUpdate: { updated in replace(updated) },
                    onDelete: { remove(shortcut.id) }
                )
            }
            Button {
                addShortcut()
            } label: {
                Label("Add shortcut", systemImage: "plus")
            }
            .disabled(settings.config.shortcuts.count >= Config.maxShortcuts)
        } header: {
            Text("Shortcuts")
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: String {
        let keys = settings.config.disabledFeatures.hintLine()
        let base = "Hold the modifier and press the key to open; keep pressing to cycle, add ⇧ to go back, release to switch."
        return keys.isEmpty ? base + " Esc cancels." : base + " While open: " + keys + ", Esc to cancel."
    }

    private func replace(_ updated: Shortcut) {
        guard let index = settings.config.shortcuts.firstIndex(where: { $0.id == updated.id }) else { return }
        settings.config.shortcuts[index] = updated
    }

    private func remove(_ id: UUID) {
        settings.config.shortcuts.removeAll { $0.id == id }
    }

    /// Adds the first modifier + key combination that isn't already taken.
    private func addShortcut() {
        let candidates: [(ModifierKey, Int)] = [
            (.option, KeyCode.tab), (.option, KeyCode.backtick), (.command, KeyCode.tab),
            (.command, KeyCode.backtick), (.option, KeyCode.space), (.control, KeyCode.backtick),
        ]
        for (modifier, key) in candidates {
            let shortcut = Shortcut(modifier: modifier, keyCode: key, scope: .allWindows, style: .icons)
            if !settings.config.shortcuts.contains(where: { $0.sameKeys(as: shortcut) }) {
                settings.config.shortcuts.append(shortcut)
                return
            }
        }
        for choice in Keys.choices where choice.code != KeyCode.tab {
            let shortcut = Shortcut(modifier: .option, keyCode: choice.code, scope: .allWindows, style: .icons)
            if !settings.config.shortcuts.contains(where: { $0.sameKeys(as: shortcut) }) {
                settings.config.shortcuts.append(shortcut)
                return
            }
        }
    }
}

@MainActor
struct SwitcherBehaviorSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section {
            Toggle("Switch when the modifier key is released", isOn: $settings.config.releaseToSwitch)
            Picker("Show the switcher on", selection: $settings.config.showOnScreen) {
                ForEach(ScreenChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
        } header: {
            Text("Behavior")
        } footer: {
            Text("Previews, other Spaces and hover selection are on the Features page.")
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct SwitcherThumbnailsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section {
            Toggle("Auto-size to fit the number of windows", isOn: $settings.config.autoSize)
            LabeledContent("Size") {
                Slider(value: $settings.config.thumbnailSize, in: 100...300, step: 10)
                    .frame(width: 220)
                    .accessibilityLabel("Thumbnail size")
            }
            .disabled(settings.config.autoSize)
        } header: {
            Text("Thumbnails")
        } footer: {
            if !settings.config.isOn(.thumbnails) {
                Text("Window thumbnails are turned off on the Features page, so every shortcut shows app icons.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct SwitcherAppListsSections: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        AppListSection(
            title: "Hidden from the switcher",
            footer: "These apps never appear in the switcher.",
            bundleIDs: $settings.config.excludedBundleIDs
        )
        AppListSection(
            title: "Apps that keep the shortcut",
            footer: settings.config.isOn(.passthrough)
                ? "While one of these is in front, Snaptic's shortcuts go to it instead. Useful for virtual machines and remote desktops. An entry like com.parallels also covers every app whose identifier starts with it."
                : "Turned off on the Features page: this list is ignored.",
            bundleIDs: $settings.config.passthroughBundleIDs
        ) {
            Toggle("Only while the app is full screen", isOn: $settings.config.passthroughOnlyWhenFullscreen)
        }
    }
}

@MainActor
struct SwitcherPrivacySections: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section {
            Toggle("Never capture password managers or private browsing windows", isOn: $settings.config.protectPrivateWindows)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Thumbnails stay in memory only, are never saved to disk, and are cleared when your Mac locks or sleeps. Snaptic asks macOS to keep its panels out of screen sharing, but some capture methods may ignore that. Private windows are only recognised when the browser puts it in the title (Firefox does; Safari and Chrome don't), so add a browser below if you want none of its windows captured.")
                .foregroundStyle(.secondary)
        }
        if settings.config.protectPrivateWindows {
            AppListSection(
                title: "Never capture these apps",
                footer: "Shown with their app icon instead of a thumbnail.",
                bundleIDs: $settings.config.privateBundleIDs
            )
        }
    }
}

/// "Launch Snaptic at login" (General → Startup).
@MainActor
struct LaunchAtLoginSection: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchNote: String?
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Section("Startup") {
            Toggle("Launch Snaptic at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    setLaunchAtLogin(launchAtLogin)
                }
            if let launchNote {
                Text(launchNote)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .onReceive(poll) { _ in
            let enabled = SMAppService.mainApp.status == .enabled
            if enabled != launchAtLogin { launchAtLogin = enabled }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        let current = service.status == .enabled
        guard enabled != current else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            if service.status == .requiresApproval {
                launchNote = "Approve Snaptic in System Settings → General → Login Items."
                SMAppService.openSystemSettingsLoginItems()
            } else {
                launchNote = nil
            }
        } catch {
            launchNote = "Couldn't change the login item: \(error.localizedDescription)"
            launchAtLogin = current   // guard above stops this from looping
        }
    }
}

/// An editable list of apps, shown by name, stored by bundle identifier.
@MainActor
struct AppListSection<Extra: View>: View {
    let title: String
    let footer: String
    @Binding var bundleIDs: [String]
    let extra: Extra

    init(title: String, footer: String, bundleIDs: Binding<[String]>, @ViewBuilder extra: () -> Extra) {
        self.title = title
        self.footer = footer
        _bundleIDs = bundleIDs
        self.extra = extra()
    }

    var body: some View {
        Section {
            extra
            if bundleIDs.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
            ForEach(bundleIDs, id: \.self) { bundleID in
                HStack {
                    Text(AppNames.name(for: bundleID))
                    Text(bundleID)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        bundleIDs.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(AppNames.name(for: bundleID))")
                }
            }
            HStack {
                Menu("Add a running app") {
                    ForEach(AppNames.runningApps(), id: \.self) { app in
                        Button(app.name) { add(app.bundleID) }
                    }
                }
                Button("Choose…") {
                    if let bundleID = AppNames.chooseApp() { add(bundleID) }
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
    }

    private func add(_ bundleID: String) {
        if !bundleIDs.contains(bundleID) { bundleIDs.append(bundleID) }
    }
}

extension AppListSection where Extra == EmptyView {
    init(title: String, footer: String, bundleIDs: Binding<[String]>) {
        self.init(title: title, footer: footer, bundleIDs: bundleIDs) { EmptyView() }
    }
}

@MainActor
enum AppNames {
    static func name(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    static func runningApps() -> [AppChoice] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != own }
            .compactMap { app -> AppChoice? in
                guard let id = app.bundleIdentifier else { return nil }
                return AppChoice(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}

@MainActor
struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open Settings", action: open)
            }
        }
    }
}

@MainActor
struct ShortcutEditor: View {
    @State private var local: Shortcut
    let canDelete: Bool
    let isDuplicate: Bool
    let commandShortcutsOff: Bool
    let onUpdate: (Shortcut) -> Void
    let onDelete: () -> Void

    init(
        shortcut: Shortcut,
        canDelete: Bool,
        isDuplicate: Bool,
        commandShortcutsOff: Bool,
        onUpdate: @escaping (Shortcut) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _local = State(initialValue: shortcut)
        self.canDelete = canDelete
        self.isDuplicate = isDuplicate
        self.commandShortcutsOff = commandShortcutsOff
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Modifier", selection: $local.modifier) {
                    ForEach(ModifierKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                Text("+")
                    .foregroundStyle(.secondary)

                Picker("Key", selection: $local.keyCode) {
                    ForEach(Keys.allowedChoices(for: local.modifier)) { choice in
                        Text(choice.label).tag(choice.code)
                    }
                }
                .labelsHidden()
                .frame(width: 170)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!canDelete)
                .accessibilityLabel("Delete shortcut")
            }

            HStack(spacing: 16) {
                Picker("Show", selection: $local.scope) {
                    ForEach(SwitcherScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                Picker("Style", selection: $local.style) {
                    ForEach(SwitcherStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            }

            Picker("Spaces", selection: $local.spaces) {
                ForEach(SpacesFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            Toggle("Include minimized and hidden windows", isOn: $local.includeMinimized)
            Toggle("Include apps with no open windows", isOn: $local.includeWindowlessApps)
            Toggle("One entry per app (its most recent window)", isOn: $local.oneWindowPerApp)

            if isDuplicate {
                Label("Another shortcut uses the same keys; only the first one works.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if local.modifier == .command && commandShortcutsOff {
                Label("⌘ shortcuts are turned off on the Features page; this one does nothing.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if local.modifier == .command {
                Text("Replaces the built-in macOS shortcut while Snaptic is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: local) {
            // ⌘ + letter/digit is never allowed (it would hijack ⌘C, ⌘V, …).
            if !Keys.isAllowed(local) {
                local.keyCode = KeyCode.tab
                return   // the change above triggers onChange again
            }
            onUpdate(local)
        }
    }
}

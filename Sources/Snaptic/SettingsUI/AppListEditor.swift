import AppKit
import SwiftUI
import SnapticKit

/// A list of apps by bundle id (moved from the Switcher's AppListSection; used by the Switcher and PIP): a section
/// whose header is the title and footer the help; each app shows its icon and name with a remove button; **Add ▾**
/// lists running apps, then "Choose…" (an app-modal open panel, never one attached to a sheet).
struct AppListEditor: View {
    let title: String
    let help: String?
    let bundleIDs: Binding<[String]>
    let anchor: ControlID?

    /// Most apps a list keeps (sanitizers clamp too).
    static let maxApps = 64

    init(_ title: String, help: String?, bundleIDs: Binding<[String]>, anchor: ControlID?) {
        self.title = title
        self.help = help
        self.bundleIDs = bundleIDs
        self.anchor = anchor
    }

    var body: some View {
        Section {
            if bundleIDs.wrappedValue.isEmpty {
                Text(L("No apps"))
                    .foregroundStyle(.secondary)
            }
            ForEach(bundleIDs.wrappedValue, id: \.self) { bundleID in
                AppListRow(bundleID: bundleID) { remove(bundleID) }
            }
            HStack {
                Spacer(minLength: 0)
                Menu(L("Add")) {
                    let running = AppNames.runningApps().filter { !bundleIDs.wrappedValue.contains($0.bundleID) }
                    ForEach(running, id: \.self) { app in
                        Button(app.name) { add(app.bundleID) }
                    }
                    if !running.isEmpty { Divider() }
                    Button(L("Choose…")) {
                        if let bundleID = AppNames.chooseApp() { add(bundleID) }
                    }
                }
                .fixedSize()
                .disabled(bundleIDs.wrappedValue.count >= Self.maxApps)
            }
        } header: {
            Text(title)
        } footer: {
            if let help {
                Text(help).foregroundStyle(.secondary)
            }
        }
        .modifier(OptionalSettingsAnchor(anchor))
    }

    private func add(_ bundleID: String) {
        guard !bundleID.isEmpty, !bundleIDs.wrappedValue.contains(bundleID),
              bundleIDs.wrappedValue.count < Self.maxApps else { return }
        bundleIDs.wrappedValue.append(bundleID)
    }

    private func remove(_ bundleID: String) {
        bundleIDs.wrappedValue.removeAll { $0 == bundleID }
    }
}

private struct AppListRow: View {
    let bundleID: String
    let remove: () -> Void

    var body: some View {
        let name = AppNames.name(for: bundleID)
        // Well-known entries of the default lists are often identifier prefixes: never "Not installed".
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            || AppNames.knownNames[bundleID] != nil
        HStack(spacing: 8) {
            icon
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !installed {
                    Text(L("Not installed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(L("Remove \(name)"))
            .accessibilityLabel(L("Remove \(name)"))
        }
        .contextMenu {
            Button(L("Remove"), role: .destructive, action: remove)
        }
    }

    private var icon: Image {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: "app.dashed")
    }
}

import AppKit
import SwiftUI
import SnapticKit

/// The Settings window (PLAN §3.7): a NavigationSplitView, at least 820×600, whose sidebar
/// lists the General pages and then each running module's pages. While it is open the app
/// is `.regular` (Dock and ⌘⇥, R5.8); it goes back to `.accessory` on close.
@MainActor final class SettingsWindowHost: NSObject, NSWindowDelegate {
    static let minimumSize = NSSize(width: 820, height: 600)

    /// Posted by Displays UI with userInfo["page"] = a page id ("displays.features").
    static let openPageNotification = Notification.Name("SnapticOpenSettingsPage")

    private weak var host: ModuleHost?
    private var window: NSWindow?
    private var pageToken: NSObjectProtocol?
    let navigation = SettingsNavigation()

    init(host: ModuleHost) {
        self.host = host
        super.init()
        pageToken = NotificationCenter.default.addObserver(forName: Self.openPageNotification, object: nil,
                                                           queue: .main) { [weak self] note in
            let page = note.userInfo?["page"] as? String
            MainActor.assumeIsolated { self?.show(page: page.flatMap(Self.validPageID)) }
        }
    }

    /// Page ids are short and printable; anything else selects nothing.
    nonisolated static func validPageID(_ id: String) -> String? {
        guard !id.isEmpty, id.utf8.count <= 64,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_" })
        else { return nil }
        return id
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func show(page: String? = nil) {
        guard let host else { return }
        if let page { navigation.selection = page }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 920, height: 660)),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L("Snaptic Settings")
            window.isReleasedWhenClosed = false
            window.minSize = Self.minimumSize
            window.contentMinSize = Self.minimumSize
            window.contentView = NSHostingView(rootView: SettingsRootView(host: host, navigation: navigation))
            window.setFrameAutosaveName("SnapticSettings")
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar app. Deferred, so the window finishes closing first.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !(self.window?.isVisible ?? false) { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }
}

@MainActor final class SettingsNavigation: ObservableObject {
    @Published var selection: String? = GeneralPages.modulesID
}

struct SettingsSection: Identifiable {
    let id: String
    let title: String
    let pages: [SettingsPage]
}

private struct SettingsRootView: View {
    @ObservedObject var host: ModuleHost
    @ObservedObject var navigation: SettingsNavigation

    private var sections: [SettingsSection] {
        _ = host.revision
        var result = [SettingsSection(id: "general", title: L("General"), pages: GeneralPages.pages(host: host))]
        for module in host.modules where host.isRunning(module.id) {
            let pages = module.settingsPages()
            if !pages.isEmpty {
                result.append(SettingsSection(id: module.id.rawValue, title: module.title, pages: pages))
            }
        }
        return result
    }

    var body: some View {
        let sections = self.sections
        let selected = sections.lazy.flatMap(\.pages).first { $0.id == navigation.selection }
        NavigationSplitView {
            List(selection: $navigation.selection) {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.pages) { page in
                            Label(page.title, systemImage: page.symbol)
                                .tag(page.id as String?)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if host.safeMode.isActive {
                    SafeModeBanner(host: host)
                }
                if let selected {
                    selected.makeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    Text(L("Choose a page in the sidebar."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: SettingsWindowHost.minimumSize.width, minHeight: SettingsWindowHost.minimumSize.height)
    }
}

/// Shown on every page while Safe Mode is on (PLAN §4.8).
struct SafeModeBanner: View {
    let host: ModuleHost

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Safe Mode")).fontWeight(.semibold)
                Text(host.safeMode.reason ?? L("Display automation is paused."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Leave Safe Mode")) { host.relauncher.relaunch(reason: "leave safe mode") }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}

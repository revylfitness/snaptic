import AppKit
import SwiftUI
import SnapticKit

/// The Settings window (PLAN 0.3 §4.2): `SettingsShellView` over `SettingsShell.shared` — sidebar with search and
/// the seven roots, a NavigationStack per root. Fixed width 715 pt, vertical resize only (min 520, default 720);
/// minimize and zoom are off, as for System Settings. While it is open the app is `.regular` (Dock and ⌘⇥, 0.2
/// R5.8); it goes back to `.accessory` when it closes and no other Snaptic window (onboarding) is open.
@MainActor final class SettingsWindowHost: NSObject, NSWindowDelegate {
    static let width: CGFloat = 715
    static let minimumHeight: CGFloat = 520
    static let defaultHeight: CGFloat = 720
    static let autosaveName = "SnapticSettings03"

    /// Posted by Displays UI with userInfo["page"] = a page id ("displays.color"); an open from Snaptic itself.
    static let openPageNotification = Notification.Name("SnapticOpenSettingsPage")

    private weak var host: ModuleHost?
    private var window: NSWindow?
    private var pageToken: NSObjectProtocol?
    private var eventMonitor: Any?
    let shell = SettingsShell.shared

    init(host: ModuleHost) {
        self.host = host
        super.init()
        shell.attach(host)
        pageToken = NotificationCenter.default.addObserver(forName: Self.openPageNotification, object: nil,
                                                           queue: .main) { [weak self] note in
            let page = note.userInfo?["page"] as? String
            MainActor.assumeIsolated { self?.show(page: page.flatMap(Self.validPageID)) }
        }
    }

    /// Page ids are short and printable; anything else selects nothing.
    nonisolated static func validPageID(_ id: String) -> String? {
        SettingsLocation.isValidID(id) ? id : nil
    }

    var isOpen: Bool { window?.isVisible ?? false }

    /// Opens (or brings forward) Settings at `page` (a root, a route or a 0.2 page id; nil = where it was).
    /// `external`: the request came from outside Snaptic's own menus and hotkeys (the `open-settings` verb); a
    /// reopen from the Dock or Finder is recognized by its Apple event. External opens arm the focus guard (R5-8).
    func show(page: String? = nil, external: Bool = false) {
        guard let host else { return }
        let isExternal = external || NSAppleEventManager.shared().currentAppleEvent != nil
        shell.open(page: page, external: isExternal)
        let window = self.window ?? makeWindow(host: host)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow(host: ModuleHost) -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: Self.width, height: Self.defaultHeight)),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L("Settings")
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.collectionBehavior.insert(.fullScreenNone)
        let content = NSHostingController(rootView: SettingsShellView(host: host, shell: shell))
        content.sizingOptions = []
        content.sceneBridgingOptions = [.title, .toolbars]
        window.contentViewController = content
        window.contentMinSize = NSSize(width: Self.width, height: Self.minimumHeight)
        window.contentMaxSize = NSSize(width: Self.width, height: CGFloat.greatestFiniteMagnitude)
        window.setContentSize(NSSize(width: Self.width, height: Self.defaultHeight))
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.delegate = self
        if !window.setFrameUsingName(Self.autosaveName) { window.center() }
        window.setFrameAutosaveName(Self.autosaveName)
        // Whatever a saved frame says, the width is fixed and the height at least the minimum.
        let height = window.contentRect(forFrameRect: window.frame).height
        window.setContentSize(NSSize(width: Self.width, height: max(Self.minimumHeight, height)))
        window.focusSearch = { [weak self, weak window] in
            guard let self, let window else { return false }
            return self.focusSearch(in: window)
        }
        self.window = window
        installEventMonitor()
        return window
    }

    /// R5-8: the first mouse-down in the window clears the pending external open. (⌘F is Edit › Find…, handled by
    /// `SettingsWindow`.)
    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated {
                guard let self, let window = self.window, window.isVisible, window.windowNumber == windowNumber
                else { return }
                self.shell.mouseDown()
            }
            return event
        }
    }

    /// Puts the cursor in the sidebar search field. False when there is none.
    private func focusSearch(in window: NSWindow) -> Bool {
        guard let root = window.contentView?.superview ?? window.contentView,
              let field = Self.searchField(in: root, depth: 0) else { return false }
        return window.makeFirstResponder(field)
    }

    private static func searchField(in view: NSView, depth: Int) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        guard depth < 40 else { return nil }
        for sub in view.subviews {
            if let field = searchField(in: sub, depth: depth + 1) { return field }
        }
        return nil
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar app. Deferred, so the window finishes closing first.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let settingsOpen = self.window?.isVisible ?? false
                let onboardingOpen = self.host?.onboarding.isShowing ?? false
                if !settingsOpen && !onboardingOpen { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }
}

/// The Settings window. Edit › Find… (⌘F, `performFindPanelAction:` with the show-find tag) puts the focus in the
/// sidebar search field, as in System Settings; Find Next, Find Previous and Use Selection for Find have nothing to
/// act on here and stay disabled (a focused text view earlier in the responder chain still handles them).
final class SettingsWindow: NSWindow {
    var focusSearch: (@MainActor () -> Bool)?

    @objc func performFindPanelAction(_ sender: Any?) {
        guard Self.isShowFind(sender) else { return }
        _ = focusSearch?()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(performFindPanelAction(_:)) { return Self.isShowFind(item) }
        return super.validateUserInterfaceItem(item)
    }

    /// Only Find… (tag `NSTextFinder.Action.showFindInterface`, 1); never ⌘G or ⌘E.
    static func isShowFind(_ sender: Any?) -> Bool {
        (sender as? NSValidatedUserInterfaceItem)?.tag == NSTextFinder.Action.showFindInterface.rawValue
    }
}

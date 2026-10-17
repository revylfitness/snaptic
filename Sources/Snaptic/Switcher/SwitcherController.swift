import AppKit
import SwiftUI
import SnapticKit

enum WindowAction {
    case close, minimize, fullscreen, quitApp, hideApp

    /// The switcher feature that turns this action on or off (PLAN §2.2).
    var feature: SwitcherFeature {
        switch self {
        case .close: return .actionClose
        case .minimize: return .actionMinimize
        case .fullscreen: return .actionFullscreen
        case .quitApp: return .actionQuit
        case .hideApp: return .actionHide
        }
    }
}

/// The switcher's state machine: open on a shortcut, cycle while the modifier
/// is held, switch on release; S starts a search, W/M/F/Q/H act on the selection.
@MainActor
final class SwitcherController {
    let model = SwitcherModel()

    private lazy var window = SwitcherWindow(rootView: AnyView(SwitcherView(model: model, actions: makeActions())))
    /// Created on first use, so a switcher with previews off never builds the panel.
    private var preview: PreviewOverlay?

    private var active: Shortcut?
    /// Sticky = stay open after the modifier is released (search mode or
    /// "release to switch" turned off). Return switches, Esc cancels.
    private var sticky = false
    private var visible = false
    private var delayElapsed = false
    /// The modifier was released before the window list finished loading.
    private var pendingCommit = false
    /// Tab presses made before the list finished loading.
    private var pendingSteps = 0
    private var openToken = 0
    private var openedAt = Date()
    private var screen: NSScreen?
    private var lastInteraction = Date()
    /// Snaptic's own actions (focus, quit, hide) make macOS report app and Space
    /// changes; don't mistake those for the user leaving.
    private var ignoreDismissSignalsUntil = Date.distantPast
    /// Keys whose keyDown we swallowed; only their keyUp is swallowed too.
    private var swallowedKeys = Set<Int>()
    private var hiResPreview: (id: CGWindowID, image: NSImage)?

    private var loadTask: Task<Void, Never>?
    private var showTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var mouseMonitor: Any?
    private var workspaceTokens: [NSObjectProtocol] = []

    private var config: Config { AppSettings.shared.config }

    // MARK: Keyboard

    /// Called for every key event system-wide. Returns true to swallow it.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .keyDown:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if let shortcut = active {
                // The switch is decided and only waiting for the window list:
                // let everything through except Esc and the shortcut key.
                let isShortcutKey = KeyCode.matches(code, shortcutKey: shortcut.keyCode)
                    && event.flags.contains(shortcut.modifier.flag)
                if pendingCommit, code != KeyCode.escape, !isShortcutKey {
                    swallowedKeys.remove(code)
                    return false
                }
                swallowedKeys.insert(code)
                handleKeyWhileOpen(code: code, event: event, shortcut: shortcut)
                return true
            }
            guard let shortcut = matchingShortcut(code: code, flags: event.flags),
                  !frontmostAppKeepsShortcuts() else {
                // Clears a stale entry left by a keyUp the tap never saw.
                swallowedKeys.remove(code)
                return false
            }
            swallowedKeys.insert(code)
            open(shortcut, reverse: event.flags.contains(.maskShift))
            return true

        case .keyUp:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            return swallowedKeys.remove(code) != nil

        case .flagsChanged:
            if let shortcut = active, !sticky, !event.flags.contains(shortcut.modifier.flag) {
                commit()
            }
            return false

        default:
            return false
        }
    }

    private func matchingShortcut(code: Int, flags: CGEventFlags) -> Shortcut? {
        let primary: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
        let held = flags.intersection(primary)
        return config.activeShortcuts.first { KeyCode.matches(code, shortcutKey: $0.keyCode) && held == $0.modifier.flag }
    }

    /// Virtual machines and remote desktops get the keys instead of Snaptic
    /// (by default only while they're full screen).
    private func frontmostAppKeepsShortcuts() -> Bool {
        guard config.isOn(.passthrough), let app = NSWorkspace.shared.frontmostApplication,
              Config.bundleID(app.bundleIdentifier, matchesAny: config.passthroughBundleIDs) else { return false }
        return !config.passthroughOnlyWhenFullscreen || Screens.isFullscreen(pid: app.processIdentifier)
    }

    private func handleKeyWhileOpen(code: Int, event: CGEvent, shortcut: Shortcut) {
        lastInteraction = Date()
        let flags = event.flags
        let shift = flags.contains(.maskShift)

        // While searching, the shortcut's key only cycles with its modifier held,
        // so a shortcut like ⌥Space still lets you type a space.
        if KeyCode.matches(code, shortcutKey: shortcut.keyCode),
           !model.searching || flags.contains(shortcut.modifier.flag) {
            move(shift ? -1 : 1)
            return
        }
        // Another Snaptic shortcut while open: switch to it.
        if let other = matchingShortcut(code: code, flags: flags), other.id != shortcut.id {
            dismiss()
            open(other, reverse: shift)
            return
        }

        switch code {
        case KeyCode.escape:
            if !model.query.isEmpty {
                setQuery("")
            } else {
                cancel()
            }
        case KeyCode.returnKey, KeyCode.enter:
            commit()
        case KeyCode.left:
            move(-1)
        case KeyCode.right:
            move(1)
        case KeyCode.up:
            model.moveVertically(-1)
            selectionChanged()
        case KeyCode.down:
            model.moveVertically(1)
            selectionChanged()
        case KeyCode.delete, KeyCode.forwardDelete:
            if model.searching, !model.query.isEmpty { setQuery(String(model.query.dropLast())) }
        default:
            if model.searching {
                if let character = printableCharacter(event) { setQuery(model.query + String(character)) }
                return
            }
            // Physical keys, so these work on every keyboard layout. A turned-off feature's
            // key does nothing (it is still swallowed, like every key while open).
            switch code {
            case KeyCode.keyS, KeyCode.slash: if config.isOn(.search) { startSearch() }
            case KeyCode.keyW: performOnSelection(.close)
            case KeyCode.keyM: performOnSelection(.minimize)
            case KeyCode.keyF: performOnSelection(.fullscreen)
            case KeyCode.keyQ: performOnSelection(.quitApp)
            case KeyCode.keyH: performOnSelection(.hideApp)
            default: break
            }
        }
    }

    private func printableCharacter(_ event: CGEvent) -> Character? {
        guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
              let character = characters.first,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol || character == " "
        else { return nil }
        return character
    }

    // MARK: Open / close

    private func open(_ shortcut: Shortcut, reverse: Bool) {
        openToken += 1
        let token = openToken
        active = shortcut
        sticky = !config.releaseToSwitch
        visible = false
        delayElapsed = false
        pendingCommit = false
        pendingSteps = 0
        hiResPreview = nil
        openedAt = Date()
        lastInteraction = Date()

        let frontPID = WindowManager.shared.effectiveFrontPID
        screen = config.showOnScreen == .mouse ? Screens.mouseScreen : Screens.activeWindowScreen(frontPID: frontPID)
        let settingsNow = config
        model.begin(style: settingsNow.effectiveStyle(shortcut),
                    hint: settingsNow.disabledFeatures.hintLine(),
                    hoverButtons: settingsNow.isOn(.hoverButtons),
                    actions: Set(SwitcherFeaturesConfig.actions.filter { settingsNow.isOn($0) }))
        installDismissMonitors()
        startWatchdog()

        let settings = config
        loadTask = Task { @MainActor [weak self] in
            // With "Windows on other Spaces" off, every shortcut lists the current Space only.
            let otherSpaces = settings.isOn(.otherSpaces) && shortcut.spaces != .current
            let list = await WindowManager.shared.loadWindows(
                includeOtherSpaces: otherSpaces,
                includeWindowless: shortcut.includeWindowlessApps && settings.isOn(.windowlessApps),
                excluded: settings.excludedBundleIDs
            )
            guard let self, token == self.openToken, self.active != nil else { return }
            self.finishLoading(list, shortcut: shortcut, reverse: reverse)
        }

        // A quick tap-and-release switches without ever drawing the panel.
        showTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(70))
            guard let self, !Task.isCancelled, token == self.openToken, self.active != nil else { return }
            self.delayElapsed = true
            self.present()
        }
    }

    private func finishLoading(_ list: WindowList, shortcut: Shortcut, reverse: Bool, keepSelection: Int? = nil) {
        var items = list.items.map { markPrivacy($0) }

        if config.isOn(.thumbnails) {
            // Drop cached images of windows that closed or may no longer be captured.
            ThumbnailStore.shared.prune(keeping: Set(items.filter { capturePermitted($0) }.map { $0.id }))
        }
        if !config.isOn(.otherSpaces) {
            items = items.filter { !$0.isOnOtherSpace }
        }

        switch shortcut.scope {
        case .allWindows:
            break
        case .activeApp:
            items = items.filter { $0.pid == list.frontPID }
        case .currentScreen:
            if let frame = screen?.frame {
                items = items.filter {
                    if $0.isWindowless { return true }
                    let rect = Screens.cocoaRect(fromGlobal: $0.frame)
                    return frame.contains(CGPoint(x: rect.midX, y: rect.midY))
                }
            }
        }
        switch shortcut.spaces {
        case .all:
            break
        case .current:
            items = items.filter { !$0.isOnOtherSpace }
        case .others:
            items = items.filter { $0.isOnOtherSpace || $0.isWindowless }
        }
        if !shortcut.includeMinimized {
            items = items.filter { !$0.isMinimized && !$0.isHidden }
        }
        if shortcut.oneWindowPerApp {
            items = groupedByApp(items)
        }

        model.load(items)
        // The window you're in is first, so start on the one before it.
        // (Compared against the filtered list, in case a search was typed already.)
        let shown = model.filtered
        if let keepSelection {
            model.selectedIndex = min(keepSelection, max(0, shown.count - 1))
        } else if reverse {
            model.selectedIndex = max(0, shown.count - 1)
        } else if shown.count > 1, let focused = list.focusedID, shown.first?.id == focused {
            model.selectedIndex = 1
        } else if shown.count > 1, shortcut.oneWindowPerApp, shown.first?.pid == list.frontPID {
            model.selectedIndex = 1
        } else {
            model.selectedIndex = 0
        }
        if pendingSteps != 0 {
            model.step(pendingSteps)
            pendingSteps = 0
        }

        if pendingCommit {
            commit()
            return
        }
        if visible {
            relayout()
            loadThumbnails()
            selectionChanged()
        }
    }

    /// Windows of protected apps, windows whose title marks private browsing,
    /// and browser windows whose title can't be read are never captured, and
    /// their titles are never shown, searched or read aloud.
    private func markPrivacy(_ item: WindowItem) -> WindowItem {
        guard config.protectPrivateWindows, !item.isWindowless else { return item }
        var item = item
        if Config.bundleID(item.bundleID, matchesAny: config.privateBundleIDs) {
            item.isPrivate = true
            item.title = ""            // shows the app name instead
        } else if item.hasPrivateMarker {
            item.isPrivate = true
            item.title = "Private window"
        } else if item.title.isEmpty, Config.isBrowser(item.bundleID) {
            item.isPrivate = true
        }
        return item
    }

    /// One entry per app: its most recent window, with a window count.
    private func groupedByApp(_ items: [WindowItem]) -> [WindowItem] {
        var counts: [pid_t: Int] = [:]
        for item in items where !item.isWindowless { counts[item.pid, default: 0] += 1 }
        var seen = Set<pid_t>()
        var result: [WindowItem] = []
        for var item in items where !seen.contains(item.pid) {
            seen.insert(item.pid)
            item.groupedCount = counts[item.pid] ?? 1
            result.append(item)
        }
        return result
    }

    private func present() {
        // Not once the keys are released: the switch is already decided.
        guard active != nil, delayElapsed, !visible, !pendingCommit else { return }
        relayout()
        window.show()
        visible = true
        if model.loaded {
            loadThumbnails()
            selectionChanged()
        }
    }

    private func relayout() {
        guard let screen else { return }
        let area = screen.visibleFrame
        let maxPanel = CGSize(width: floor(area.width * 0.92), height: floor(area.height * 0.85))
        let chrome = CGSize(
            width: Metrics.panelPadding * 2,
            height: Metrics.panelPadding * 2 + Metrics.headerHeight + Metrics.headerSpacing
        )
        let maxContent = CGSize(width: maxPanel.width - chrome.width, height: maxPanel.height - chrome.height)
        model.relayout(maxContent: maxContent, autoSize: config.autoSize, baseHeight: CGFloat(config.thumbnailSize))

        let content = model.layout.contentSize
        let size = CGSize(
            width: min(max(content.width, Metrics.minPanelContent.width) + chrome.width + 2, maxPanel.width),
            height: min(max(content.height, Metrics.minPanelContent.height) + chrome.height + 2, maxPanel.height)
        )
        window.setFrame(size: size, centeredIn: area)
    }

    func commit() {
        guard active != nil else { return }
        guard model.loaded else {
            pendingCommit = true
            return
        }
        let selection = model.selected
        dismiss()
        guard let target = selection else { return }
        // The switch makes macOS report an app (and maybe Space) change a little
        // later; it must not cancel a switcher the user opens again right away.
        ignoreDismissSignalsUntil = Date().addingTimeInterval(1.0)
        // Let the key event finish before we start moving windows around.
        Task { @MainActor in WindowManager.shared.focus(target) }
    }

    func cancel() {
        dismiss()
    }

    /// Module stop: closes the switcher and forgets per-session key state.
    func reset() {
        dismiss()
        swallowedKeys = []
        ignoreDismissSignalsUntil = .distantPast
        preview?.hide()
        preview = nil
    }

    private func dismiss() {
        guard active != nil || visible else { return }
        active = nil
        sticky = false
        visible = false
        delayElapsed = false
        pendingCommit = false
        pendingSteps = 0
        hiResPreview = nil
        openToken += 1
        loadTask?.cancel()
        showTask?.cancel()
        watchdog?.cancel()
        previewTask?.cancel()
        loadTask = nil
        showTask = nil
        watchdog = nil
        previewTask = nil
        removeDismissMonitors()
        ThumbnailStore.shared.invalidate()
        window.hide()
        preview?.hide()
        model.reset()
    }

    // MARK: Safety nets

    /// If the modifier-release event is ever missed (macOS can pause event
    /// taps, e.g. during secure input), check the real keyboard state. A sticky
    /// switcher left alone for 30 seconds closes itself, and so does one whose
    /// window list takes too long to load.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, let shortcut = self.active else { return }
                if !self.model.loaded, Date().timeIntervalSince(self.openedAt) > 2 {
                    self.cancel()
                    return
                }
                if self.sticky {
                    if Date().timeIntervalSince(self.lastInteraction) > 30 {
                        self.cancel()
                        return
                    }
                } else if !CGEventSource.flagsState(.combinedSessionState).contains(shortcut.modifier.flag) {
                    self.commit()
                }
            }
        }
    }

    /// Clicking anywhere else, switching apps or switching Spaces closes the
    /// switcher, so it can never keep holding the keyboard.
    private func installDismissMonitors() {
        removeDismissMonitors()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification]
        for name in names {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, Date() > self.ignoreDismissSignalsUntil else { return }
                    self.cancel()
                }
            })
        }
    }

    private func removeDismissMonitors() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens { center.removeObserver(token) }
        workspaceTokens = []
    }

    // MARK: Selection, search, preview

    private func move(_ delta: Int) {
        guard model.loaded else {
            pendingSteps += delta
            return
        }
        model.step(delta)
        selectionChanged()
    }

    private func startSearch() {
        model.searching = true
        sticky = true
    }

    private func setQuery(_ query: String) {
        model.setQuery(query)
        if visible { relayout() }
        selectionChanged()
    }

    private func selectionChanged() {
        updatePreview()
        announceSelection()
    }

    private func announceSelection() {
        guard visible, NSWorkspace.shared.isVoiceOverEnabled, let item = model.selected else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(item.appName), \(item.displayTitle)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func capturePermitted(_ item: WindowItem) -> Bool {
        item.isCapturable
    }

    private var blockedBundleIDs: [String] {
        config.protectPrivateWindows ? config.privateBundleIDs : []
    }

    private func updatePreview() {
        previewTask?.cancel()
        guard visible, config.isOn(.preview), let item = model.selected, capturePermitted(item) else {
            preview?.hide()
            return
        }
        let preview = self.preview ?? PreviewOverlay()
        self.preview = preview
        let frame = Screens.cocoaRect(fromGlobal: item.frame)
        if let hiResPreview, hiResPreview.id == item.id {
            preview.show(image: hiResPreview.image, frame: frame, below: window.level)
            return
        }
        if let image = model.thumbnails[item.id] {
            preview.show(image: image, frame: frame, below: window.level)
        } else {
            preview.hide()
        }

        // Then swap in a sharp, full-resolution capture.
        let target = CaptureTarget(id: item.id, pid: item.pid)
        let blocked = blockedBundleIDs
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled,
                  let image = await ThumbnailStore.shared.captureForPreview(target, blockedBundleIDs: blocked, maxPixels: 2400),
                  !Task.isCancelled,
                  let self, self.visible,
                  let current = self.model.selected, current.id == target.id else { return }
            self.hiResPreview = (target.id, image)
            self.preview?.show(image: image, frame: Screens.cocoaRect(fromGlobal: current.frame), below: self.window.level)
        }
    }

    private func loadThumbnails() {
        guard config.isOn(.thumbnails) else { return }
        let eligible = model.allItems.filter { capturePermitted($0) }
        model.thumbnails = ThumbnailStore.shared.cached(eligible.map { $0.id })
        guard let shortcut = active, config.effectiveStyle(shortcut) == .thumbnails else { return }
        ThumbnailStore.shared.refresh(
            eligible.map { CaptureTarget(id: $0.id, pid: $0.pid) },
            blockedBundleIDs: blockedBundleIDs,
            maxPixels: 640,
            priority: model.selected?.id
        ) { [weak self] id, image in
            guard let self, self.active != nil else { return }
            self.model.thumbnails[id] = image
            if self.model.selected?.id == id { self.updatePreview() }
        }
    }

    // MARK: Window actions (keys and hover buttons)

    private func makeActions() -> SwitcherActions {
        SwitcherActions(
            select: { [weak self] index in self?.mouseSelect(index) },
            activate: { [weak self] index in
                guard let self, self.model.filtered.indices.contains(index) else { return }
                self.model.selectedIndex = index
                self.commit()
            },
            close: { [weak self] id in self?.perform(.close, on: id) },
            minimize: { [weak self] id in self?.perform(.minimize, on: id) },
            fullscreen: { [weak self] id in self?.perform(.fullscreen, on: id) }
        )
    }

    private func mouseSelect(_ index: Int) {
        guard active != nil else { return }
        lastInteraction = Date()   // mouse use keeps a sticky switcher open
        guard config.isOn(.hoverSelect), index != model.selectedIndex, model.filtered.indices.contains(index) else { return }
        model.selectedIndex = index
        selectionChanged()
    }

    private func performOnSelection(_ action: WindowAction) {
        guard let id = model.selected?.id else { return }
        perform(action, on: id)
    }

    private func perform(_ action: WindowAction, on id: CGWindowID) {
        guard active != nil, config.isOn(action.feature),
              let item = model.allItems.first(where: { $0.id == id }) else { return }
        lastInteraction = Date()
        ignoreDismissSignalsUntil = Date().addingTimeInterval(action == .quitApp ? 5 : 1.5)

        switch action {
        case .close:
            guard item.axElement != nil else { return }
            WindowManager.shared.close(item)
            if active?.oneWindowPerApp == true, item.groupedCount > 1 {
                reloadSoon()   // the app still has other windows
            } else {
                removeFromList { $0.id == id }
            }

        case .minimize:
            guard item.axElement != nil else { return }
            WindowManager.shared.toggleMinimized(item)
            model.update(id) { $0.isMinimized.toggle() }
            selectionChanged()

        case .fullscreen:
            guard item.axElement != nil else { return }
            dismiss()
            ignoreDismissSignalsUntil = Date().addingTimeInterval(1.5)
            Task { @MainActor in
                WindowManager.shared.focus(item)
                try? await Task.sleep(for: .milliseconds(250))
                WindowManager.shared.toggleFullscreen(item)
            }

        case .quitApp:
            // Finder only quits if its hidden "Quit Finder" menu item is enabled.
            if item.bundleID == "com.apple.finder",
               UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "QuitMenuItem") != true {
                NSSound.beep()
                return
            }
            WindowManager.shared.quitApp(item)
            removeFromList { $0.pid == item.pid }

        case .hideApp:
            WindowManager.shared.toggleHidden(item)
            let hidden = !item.isHidden
            for other in model.allItems where other.pid == item.pid {
                model.update(other.id) { $0.isHidden = hidden }
            }
            selectionChanged()
        }
    }

    /// Reloads the list shortly after an action, keeping the selection position.
    private func reloadSoon() {
        guard let shortcut = active else { return }
        let token = openToken
        let keep = model.selectedIndex
        let settings = config
        loadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            let otherSpaces = settings.isOn(.otherSpaces) && shortcut.spaces != .current
            let list = await WindowManager.shared.loadWindows(
                includeOtherSpaces: otherSpaces,
                includeWindowless: shortcut.includeWindowlessApps && settings.isOn(.windowlessApps),
                excluded: settings.excludedBundleIDs
            )
            guard let self, token == self.openToken, self.active != nil else { return }
            self.finishLoading(list, shortcut: shortcut, reverse: false, keepSelection: keep)
        }
    }

    private func removeFromList(where predicate: (WindowItem) -> Bool) {
        for item in model.allItems where predicate(item) {
            model.remove(item.id)
        }
        if model.allItems.isEmpty {
            dismiss()
        } else {
            relayout()   // keeps the grid used for ↑/↓ in sync even before the panel shows
            selectionChanged()
        }
    }
}

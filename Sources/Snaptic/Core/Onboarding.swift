import AppKit
import SwiftUI
import SnapticKit

/// First-run onboarding (H; PLAN 0.3 §4.7): Welcome → Choose modules → Displays chips (F's
/// `DisplaysOnboardingStep`, only while Displays is on) → Permissions (only what was chosen) → Keep Snaptic Up to
/// Date (0.3.1 E1a) → Done. One primary button, always in the window footer ("Continue" / "Done"; on the Displays step
/// it applies the chips; on the updates page Check Automatically and Not Now, either of which moves on), with Back
/// beside it. The step is saved after every move, so closing the window and relaunching resumes where it stopped.
///
/// The updates page shows only in builds that update themselves and while the user hasn't answered (Kit
/// `OnboardingUpdatesPage`). A first launch opens the window before `startUpdater()` creates the updater, so the page
/// joins when the updater starts (`updaterDidStart`) or at Continue, and once in it stays in for the run, so answering
/// doesn't renumber the pages (r1 U6, r2 C2-1). It sits between the last saved step and Done without a saved step of
/// its own (`ModulesConfig.onboarding` keeps the step before it), so a relaunch there comes back to it through
/// Continue.
@MainActor final class Onboarding: NSObject, NSWindowDelegate, ControlDeclaring {
    typealias Controls = OnboardingControls
    static let size = NSSize(width: 600, height: 580)

    private weak var host: ModuleHost?
    private var window: NSWindow?
    private let model = OnboardingModel()

    init(host: ModuleHost) {
        self.host = host
        super.init()
    }

    var isShowing: Bool { window?.isVisible ?? false }

    /// Shows onboarding at the saved step if it isn't finished.
    func showIfNeeded() {
        guard let host, host.modulesStore.value.needsOnboarding else { return }
        show()
    }

    func show() {
        guard let host else { return }
        host.permissions.holdAutomaticGuides = true
        if !isShowing { beginRun() }
        model.step = host.modulesStore.value.resumeStep
        if model.step == .done { model.step = .welcome }
        save()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = L("Welcome to Snaptic")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(
                host: host, store: host.modulesStore, permissions: host.permissions, model: model,
                next: { [weak self] in self?.advance() }, back: { [weak self] in self?.goBack() },
                finish: { [weak self] in self?.finish() },
                answerUpdates: { [weak self] allowed in self?.answerUpdates(allowed) }))
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func advance() {
        guard let host else { return }
        guard model.step != .done else { finish(); return }
        let next = host.modulesStore.value.step(after: model.step)
        model.updatesPage.refresh(asks: Self.asksAboutUpdates(host))
        if next == .done && !model.showingUpdates && model.updatesPage.included {
            model.showingUpdates = true
            return
        }
        model.showingUpdates = false
        model.step = next
        save()
    }

    /// E1a: the updates question, once, in builds that update themselves.
    static func asksAboutUpdates(_ host: ModuleHost) -> Bool {
        OnboardingUpdatesPage.asks(updaterExists: host.updaterController != nil,
                                   consentDecided: host.updaterController?.consentDecided ?? false)
    }

    /// `ModuleHost.startUpdater()` made the updater: the page joins this run if the question is open (C2-1).
    func updaterDidStart() {
        guard let host else { return }
        model.updatesPage.refresh(asks: Self.asksAboutUpdates(host))
    }

    /// This run has the updates page (`--selftest-launch` checks it after `startUpdater()`).
    var includesUpdatesPage: Bool { model.updatesPage.included }

    /// A new run starts (`show()` while the window isn't showing; `--selftest-launch` calls it without a window): the
    /// updates page is in if the question is open now, and may join later (C2-1).
    func beginRun() {
        guard let host else { return }
        model.updatesPage.windowOpened(asks: Self.asksAboutUpdates(host))
        model.showingUpdates = false
    }

    /// Check Automatically (checks and automatic install, never install for root-owned copies) or Not Now (both
    /// off); either moves on.
    private func answerUpdates(_ allowed: Bool) {
        host?.updaterController?.setConsent(allowed)
        advance()
    }

    private func goBack() {
        guard let host else { return }
        if model.showingUpdates {
            model.showingUpdates = false
            return
        }
        let steps = host.modulesStore.value.onboardingSteps()
        guard let index = steps.firstIndex(of: model.step), index > 0 else { return }
        model.step = steps[index - 1]
        save()
    }

    private func finish() {
        guard let host else { return }
        host.modulesStore.value.onboarding = .done
        host.modulesStore.value.onboardingPermissions = []
        host.permissions.holdAutomaticGuides = false
        EventLog.shared.record(.modules, "Onboarding finished")
        window?.close()
        // Bootstrap held the launch request back while onboarding ran (W15).
        host.requestLaunchPermissions()
    }

    private func save() {
        host?.modulesStore.value.onboarding = model.step
        host?.modulesStore.flush()
    }

    func windowWillClose(_ notification: Notification) {
        // Closed early: the saved step stays, and onboarding resumes next launch.
        host?.permissions.holdAutomaticGuides = false
        host?.modulesStore.flush()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !(self.host?.settingsWindow.isOpen ?? false) { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }
}

@MainActor final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    /// Bumped by the footer's Continue on the Displays step: F's step applies its chips and calls `onApply`.
    @Published var displaysApplyToken = 0
    /// 0.3.1 E1a: the Keep Snaptic Up to Date page shows (between `step` and Done).
    @Published var showingUpdates = false
    /// E1a: whether this run has the updates page (r1 U6, r2 C2-1).
    @Published var updatesPage = OnboardingUpdatesPage()
}

private struct OnboardingView: View {
    let host: ModuleHost
    @ObservedObject var store: ConfigStore<ModulesConfig>
    @ObservedObject var permissions: PermissionFlow
    @ObservedObject var model: OnboardingModel
    let next: () -> Void
    let back: () -> Void
    let finish: () -> Void
    let answerUpdates: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            progress
            Group {
                if model.showingUpdates {
                    updatesStep
                } else {
                    switch model.step {
                    case .welcome: welcome
                    case .modules: modules
                    case .displays: displays
                    case .permissions: permissionsStep
                    case .done: done
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: Onboarding.size.width, height: Onboarding.size.height)
    }

    /// The pages in order: the steps, with the updates page before Done for the whole run that includes it (E1a, U6).
    private var pages: [OnboardingPage] {
        store.value.onboardingPages(includesUpdates: model.updatesPage.included || model.showingUpdates)
    }

    private var currentPage: OnboardingPage { model.showingUpdates ? .updates : .step(model.step) }

    /// A page indicator: one dot per page.
    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(pages, id: \.self) { page in
                Circle()
                    .fill(page == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 36)
        .padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Step \((pages.firstIndex(of: currentPage) ?? 0) + 1) of \(pages.count)"))
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text(L("Welcome to Snaptic"))
                .font(.largeTitle.weight(.semibold))
            Text(L("A window switcher, display controls, and Keep Awake, in your menu bar. Turn on only what you want; everything else stays off."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private var modules: some View {
        VStack(spacing: 0) {
            heading(L("Choose What Snaptic Does"),
                    L("A feature that’s off adds nothing to the menu bar and doesn’t run. You can change this in Settings."))
            Form {
                Section {
                    ForEach(ModuleID.allCases, id: \.self) { id in
                        let blocked = host.disabledByDefaults.contains(id)
                        ModuleSwitchRow(id, title: host.module(id).title,
                                        isOn: Binding(get: { store.value.isEnabled(id) },
                                                      set: { on in if !blocked { host.setEnabled(on, id) } }),
                                        blocked: blocked,
                                        anchor: ControlID("onboarding.modules"))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }

    /// F's chips; the footer's Continue applies them (one primary button, §4.7), then setup moves on.
    private var displays: some View {
        DisplaysOnboardingStep(env: host.displays.pageEnvironment, hideMenuIcon: hideDisplaysIcon,
                               applyToken: model.displaysApplyToken) { chosen in
            store.value.onboardingPermissions = Permission.allCases.filter { chosen.contains($0) }
            next()
        }
    }

    private var hideDisplaysIcon: Binding<Bool> {
        Binding(get: { store.value.presence(.displays) == .hidden },
                set: { store.value.setPresence($0 ? .hidden : .inSnapticMenu, for: .displays) })
    }

    /// What the chosen modules and display features need.
    private var needed: [Permission] {
        var set = Set(store.value.onboardingPermissions)
        if store.value.isEnabled(.windowSwitcher) && !host.disabledByDefaults.contains(.windowSwitcher) {
            set.formUnion(host.switcher.requiredPermissions)
        }
        return Permission.allCases.filter { set.contains($0) }
    }

    private var permissionsStep: some View {
        VStack(spacing: 0) {
            heading(L("Allow Access"),
                    needed.isEmpty ? L("Nothing you chose needs a permission.")
                        : L("macOS asks you to allow these for the features you chose. Snaptic asks for nothing else."))
            if !needed.isEmpty {
                Form {
                    Section {
                        ForEach(needed, id: \.self) { permission in
                            OnboardingPermissionRow(permission: permission, granted: permissions.granted.contains(permission)) {
                                permissions.presentGuide(permission)
                            }
                        }
                    } footer: {
                        Text(L("After you allow something, macOS may ask Snaptic to quit and reopen. Setup continues where you left off."))
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
        }
        .onAppear { permissions.refresh() }
    }

    /// E1a: the update consent, asked in Snaptic's own words (Sparkle's prompt never appears).
    private var updatesStep: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(L("Keep Snaptic Up to Date"))
                .font(.largeTitle.weight(.semibold))
            Text(L("Snaptic can check GitHub once a day and install updates when you quit it. GitHub sees your IP address and macOS version, nothing more."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private var done: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(L("You’re All Set"))
                .font(.largeTitle.weight(.semibold))
            Text(L("Snaptic is in the menu bar. To change settings later, choose Snaptic Settings… from its menu, or open Snaptic again from Finder."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private func heading(_ title: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title.weight(.semibold))
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, 40)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if model.step != .welcome && model.step != .done {
                Button(L("Back")) { back() }
            }
            Spacer()
            if model.showingUpdates {
                // Either answer moves on; there is no separate Continue (E1a).
                Button(L("Not Now")) { answerUpdates(false) }
                    .modifier(SettingsAnchor(ControlID("onboarding.updates.notNow")))
                Button(L("Check Automatically")) { answerUpdates(true) }
                    .keyboardShortcut(.defaultAction)
                    .modifier(SettingsAnchor(ControlID("onboarding.updates.check")))
            } else {
                Button(model.step == .done ? L("Done") : L("Continue")) {
                    switch model.step {
                    case .done: finish()
                    case .displays: model.displaysApplyToken &+= 1
                    default: next()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

/// A permission in onboarding: its System Settings name, what it allows, and its state or the button that opens
/// Snaptic's guide.
private struct OnboardingPermissionRow: View {
    let permission: Permission
    let granted: Bool
    let open: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text(L("Allowed"))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(L("Open Privacy Settings…"), action: open)
                    .fixedSize()
            }
        } label: {
            Text(PermissionFlow.paneName(permission))
            Text(PermissionFlow.purpose(permission))
        }
        .accessibilityValue(granted ? L("Allowed") : L("Not allowed"))
    }
}

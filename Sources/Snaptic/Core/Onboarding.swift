import AppKit
import SwiftUI
import SnapticKit

/// First-run onboarding (H; PLAN 0.3 §4.7): Welcome → Choose modules → Displays chips (F's
/// `DisplaysOnboardingStep`, only while Displays is on) → Permissions (only what was chosen) → Done. One primary
/// button, always in the window footer ("Continue" / "Done"), with Back beside it. The step is saved after every
/// move, so closing the window and relaunching resumes where it stopped.
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
                finish: { [weak self] in self?.finish() }))
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
        model.step = host.modulesStore.value.step(after: model.step)
        save()
    }

    private func goBack() {
        guard let host else { return }
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
}

private struct OnboardingView: View {
    let host: ModuleHost
    @ObservedObject var store: ConfigStore<ModulesConfig>
    @ObservedObject var permissions: PermissionFlow
    @ObservedObject var model: OnboardingModel
    let next: () -> Void
    let back: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            progress
            Group {
                switch model.step {
                case .welcome: welcome
                case .modules: modules
                case .displays: displays
                case .permissions: permissionsStep
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: Onboarding.size.width, height: Onboarding.size.height)
    }

    private var steps: [OnboardingStep] { store.value.onboardingSteps() }

    /// A page indicator: one dot per step.
    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(steps, id: \.self) { step in
                Circle()
                    .fill(step == model.step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 36)
        .padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Step \((steps.firstIndex(of: model.step) ?? 0) + 1) of \(steps.count)"))
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
                    L("A feature that's off adds nothing to the menu bar and doesn't run. You can change this in Settings."))
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

    /// F's chips. Until F's step takes its apply from this footer, its own button applies and moves on (§4.7).
    private var displays: some View {
        DisplaysOnboardingStep(env: host.displays.pageEnvironment, hideMenuIcon: hideDisplaysIcon) { chosen in
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

    private var done: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(L("You're All Set"))
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
            if model.step == .displays {
                Button(L("Skip")) { next() }
            } else {
                Button(model.step == .done ? L("Done") : L("Continue")) {
                    model.step == .done ? finish() : next()
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

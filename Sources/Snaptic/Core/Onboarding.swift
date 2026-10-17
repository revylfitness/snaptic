import AppKit
import SwiftUI
import SnapticKit

/// First-run onboarding (PLAN §3.7): welcome, modules, the Displays chips (team F's
/// DisplaysOnboardingStep), then permissions for what was chosen. The step is saved in
/// ModulesConfig after every move, so onboarding resumes after a relaunch.
@MainActor final class Onboarding: NSObject, NSWindowDelegate {
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = L("Welcome to Snaptic")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 560, height: 520)
            window.contentView = NSHostingView(rootView: OnboardingView(
                host: host, store: host.modulesStore, permissions: host.permissions, model: model,
                next: { [weak self] in self?.advance() }, finish: { [weak self] in self?.finish() }))
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
        model.step = next
        save()
    }

    private func finish() {
        guard let host else { return }
        host.modulesStore.value.onboarding = .done
        host.modulesStore.value.onboardingPermissions = []
        host.permissions.holdAutomaticGuides = false
        EventLog.shared.record(.modules, "Onboarding finished")
        window?.close()
    }

    private func save() {
        host?.modulesStore.value.onboarding = model.step
        host?.modulesStore.flush()
    }

    func windowWillClose(_ notification: Notification) {
        // Closed early: the saved step stays, and onboarding resumes next launch.
        host?.permissions.holdAutomaticGuides = false
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
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            progress
            Divider()
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
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var steps: [OnboardingStep] { store.value.onboardingSteps() }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { step in
                Capsule()
                    .fill(step == model.step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(height: 4)
            }
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Step ") + String((steps.firstIndex(of: model.step) ?? 0) + 1) + L(" of ") + String(steps.count))
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Welcome to Snaptic")).font(.largeTitle.weight(.semibold))
            Text(L("Snaptic is a small set of menu bar tools. Pick the ones you want; everything you don't pick stays off and costs nothing."))
            Text(L("You can change every choice later in Settings."))
                .foregroundStyle(.secondary)
            Spacer()
            footer(primary: L("Get Started"))
        }
        .padding(24)
    }

    private var modules: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Choose your tools")).font(.title.weight(.semibold))
            ForEach(ModuleID.allCases, id: \.self) { id in
                let module = host.module(id)
                Toggle(isOn: Binding(get: { store.value.isEnabled(id) }, set: { host.setEnabled($0, id) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.title).fontWeight(.medium)
                        Text(module.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            Spacer()
            footer(primary: L("Continue"))
        }
        .padding(24)
    }

    private var displays: some View {
        VStack(spacing: 0) {
            DisplaysOnboardingStep(env: host.displays.pageEnvironment, hideMenuIcon: hideDisplaysIcon) { chosen in
                store.value.onboardingPermissions = Permission.allCases.filter { chosen.contains($0) }
                next()
            }
            HStack {
                Spacer()
                Button(L("Skip")) { next() }
            }
            .padding(16)
        }
    }

    private var hideDisplaysIcon: Binding<Bool> {
        Binding(get: { store.value.placement(.displays) == .hidden },
                set: { store.value.setPlacement($0 ? .hidden : .shared, for: .displays) })
    }

    /// What the chosen modules and display features need.
    private var needed: [Permission] {
        var set = Set(store.value.onboardingPermissions)
        if store.value.isEnabled(.windowSwitcher) { set.formUnion(host.switcher.requiredPermissions) }
        return Permission.allCases.filter { set.contains($0) }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Permissions")).font(.title.weight(.semibold))
            if needed.isEmpty {
                Text(L("Nothing you chose needs a permission."))
                    .foregroundStyle(.secondary)
            } else {
                Text(L("macOS asks you to allow these for what you chose. Snaptic never asks for anything else."))
                ForEach(needed, id: \.self) { permission in
                    PermissionRow(title: PermissionFlow.paneName(permission), detail: PermissionFlow.purpose(permission),
                                  granted: permissions.granted.contains(permission),
                                  open: { permissions.presentGuide(permission) })
                }
                Text(L("After a grant, macOS may ask Snaptic to relaunch; onboarding picks up where you left off."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            footer(primary: L("Continue"))
        }
        .padding(24)
        .onAppear { permissions.refresh() }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("You're all set")).font(.title.weight(.semibold))
            Text(L("Snaptic lives in the menu bar. Open it again from Finder or Spotlight any time to get to Settings."))
            Spacer()
            footer(primary: L("Finish"))
        }
        .padding(24)
    }

    private func footer(primary: String) -> some View {
        HStack {
            if model.step != .welcome {
                Button(L("Finish Later")) { NSApp.keyWindow?.close() }
            }
            Spacer()
            Button(primary) { model.step == .done ? finish() : next() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

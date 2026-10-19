import AppKit
import SwiftUI
import SnapticKit

// "Custom…" and "Add Time…" (owner: G; PLAN 0.3 §5.3, R5-9, r3 security L8). A small panel opened from the Awake
// menu and from the Settings status row (Custom…, Add Time…): keep awake for a duration, until a time, or while an app
// is running with an optional "At most" cap (§4.3, parity minor 6), with the "Keep the display on" choice; in extend
// mode it adds time to the running session. No control has a Return binding (focus safety): Start and Add act only
// on a click or an accessibility press; Escape cancels. A Settings start checks the focus guard (R5-8).

struct CustomSessionPanel: View, ControlDeclaring {
    typealias Controls = CustomSessionPanelControls
    /// 0.3.1 B7: Keep awake with the lid closed (Start mode). Step 0 stub: T-lid-app uses these ids in step 1 (and deletes this list).
    private static let step0Controls = [ControlID("awake.custom.lidClosed")]

    enum Mode: Equatable { case start, extend }
    enum Kind: Hashable { case duration, until, whileApp }
    /// A running app the "While an App Is Running" kind can wait for.
    struct App: Hashable {
        let bundleID: String
        let name: String
    }
    /// "At most" choices for the app kind (hours; 0 = no limit).
    static let capChoices = [0, 1, 2, 4, 8, 12]

    let mode: Mode
    let initialSeconds: Int
    let initialKeepDisplayOn: Bool
    /// Running apps when the panel opened (recent first, ≤ 12).
    let apps: [App]
    let onStart: @MainActor (_ kind: AwakeSessionKind, _ keepDisplayOn: Bool) -> Void
    let onExtend: @MainActor (_ seconds: Int) -> Void
    let onCancel: @MainActor () -> Void

    @State private var kind: Kind = .duration
    @State private var hours = 1
    @State private var minutes = 30
    @State private var until = Date().addingTimeInterval(3_600)
    @State private var keepDisplayOn = true
    @State private var app = ""
    @State private var capHours = 0
    @State private var loaded = false

    private var seconds: Int { hours * 3_600 + minutes * 60 }
    private var valid: Bool {
        switch (mode, kind) {
        case (.extend, _), (.start, .duration): return AwakeClock.durationRange.contains(seconds)
        case (.start, .until): return true
        case (.start, .whileApp): return apps.contains { $0.bundleID == app }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if mode == .start {
                        PickerSetting(L("Keep awake"), selection: $kind, options: [
                            PickerOption(.duration, L("For")), PickerOption(.until, L("Until")),
                            PickerOption(.whileApp, L("While an App Is Running")),
                        ], style: .segmented, defaultValue: nil)
                    }
                    if mode == .start && kind == .whileApp {
                        if apps.isEmpty {
                            Text(L("No apps are running."))
                                .foregroundStyle(.secondary)
                        } else {
                            PickerSetting(L("App"), selection: $app,
                                          options: apps.map { PickerOption($0.bundleID, $0.name) },
                                          style: .popUp, defaultValue: nil)
                        }
                        PickerSetting(L("At most"), help: L("Ends after this long even if the app is still running."),
                                      selection: $capHours,
                                      options: Self.capChoices.map {
                                          PickerOption($0, $0 == 0 ? L("No Limit") : AwakePresetKind.spanTitle($0 * 3_600))
                                      },
                                      style: .popUp, defaultValue: 0)
                    } else if mode == .extend || kind == .duration {
                        StepperSetting(L("Hours"), value: $hours, in: 0...(AwakeClock.maxSessionSeconds / 3_600 - 1),
                                       defaultValue: nil, format: .plain(digits: 0))
                        StepperSetting(L("Minutes"), value: $minutes, in: 0...55, step: 5, defaultValue: nil,
                                       format: .minutes)
                    } else {
                        DatePicker(L("Time"), selection: $until, displayedComponents: .hourAndMinute)
                    }
                    if mode == .start {
                        ToggleSetting(L("Keep the display on"),
                                      help: L("When off, your Mac stays awake but the display can turn off."),
                                      isOn: $keepDisplayOn)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button(L("Cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(ControlID("awake.custom.cancel").rawValue)
                Button(mode == .start ? L("Start") : L("Add")) { commit() }
                    .disabled(!valid)
                    .accessibilityIdentifier(ControlID("awake.custom.start").rawValue)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 420)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let s = AwakeMath.clamp(initialSeconds, AwakeClock.durationRange)
            hours = s / 3_600
            minutes = (s % 3_600) / 60 / 5 * 5
            keepDisplayOn = initialKeepDisplayOn
            app = apps.first?.bundleID ?? ""
        }
    }

    private func commit() {
        // Hours or minutes typed without Return are written first (review round 3 ui F1/F2).
        FocusedField.commit()
        switch (mode, kind) {
        case (.extend, _):
            onExtend(seconds)
        case (.start, .duration):
            onStart(.duration(seconds: seconds), keepDisplayOn)
        case (.start, .until):
            let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: until)
            guard let unix = AwakeFormat.nextUnix(hour: c.hour ?? 0, minute: c.minute ?? 0) else { return }
            onStart(.until(unixTime: unix), keepDisplayOn)
        case (.start, .whileApp):
            guard apps.contains(where: { $0.bundleID == app }) else { return }
            onStart(.whileApp(bundleID: app, maxSeconds: capHours > 0 ? capHours * 3_600 : nil), keepDisplayOn)
        }
    }
}

/// Presents CustomSessionPanel in a small utility window and starts or extends through the session controller.
@MainActor final class CustomSessionWindow {
    private var window: NSPanel?
    weak var context: AwakeContext?
    /// Who starts or extends: the Awake menu, or the Settings status row (`.settings`).
    let source: AwakeSessionSource

    init(source: AwakeSessionSource = .menu) {
        self.source = source
    }

    func present(_ mode: CustomSessionPanel.Mode) {
        guard let ctx = context else { return }
        close()
        let sessions = ctx.config.value.sessions
        let view = CustomSessionPanel(
            mode: mode, initialSeconds: mode == .start ? sessions.lastCustomSeconds : 3_600,
            initialKeepDisplayOn: sessions.defaultOptions.display != .maySleep,
            apps: mode == .start ? AwakeFormat.runningApps(recent: sessions.recentApps).map {
                CustomSessionPanel.App(bundleID: $0.bundleID, name: $0.name)
            } : [],
            onStart: { [weak self] kind, keepDisplayOn in self?.start(kind, keepDisplayOn: keepDisplayOn) },
            onExtend: { [weak self] seconds in
                guard let self, self.mayAct() else { return }
                _ = self.context?.sessions.extend(by: seconds, source: self.source)
                self.close()
            },
            onCancel: { [weak self] in self?.close() })
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        panel.title = mode == .start ? L("Keep Awake") : L("Add Time")
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = NSHostingController(rootView: view)
        panel.center()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    /// R5-8 (security N-2): a Settings start or extend from the panel checks the focus guard like every other
    /// Settings start handler.
    private func mayAct() -> Bool {
        source != .settings || SettingsShell.shared.mayStart()
    }

    private func start(_ kind: AwakeSessionKind, keepDisplayOn: Bool) {
        guard let ctx = context, mayAct() else { return }
        if case .duration(let s) = kind { ctx.config.value.sessions.lastCustomSeconds = s }
        var options = ctx.config.value.sessions.effectiveOptions(for: kind, preset: nil,
                                                                  effective: ctx.runtime.effectiveFeatures)
        options.display = keepDisplayOn ? (options.display == .maySleep ? .keepOn : options.display) : .maySleep
        _ = ctx.sessions.start(kind, options: options, presetID: nil, source: source, overrideGuards: false)
        close()
    }
}

import AppKit
import SwiftUI
import SnapticKit

// "Custom…" and "Add Time…" (owner: G; PLAN 0.3 §5.3, R5-9, r3 security L8). A small panel opened from the Awake
// menu (and, in step 3, from the Settings status row): keep awake for a duration or until a time, with the "Keep the
// display on" choice; in extend mode it adds time to the running session. No control has a Return binding (focus
// safety): Start and Add act only on a click or an accessibility press; Escape cancels.

struct CustomSessionPanel: View, ControlDeclaring {
    typealias Controls = CustomSessionPanelControls

    enum Mode: Equatable { case start, extend }
    enum Kind: Hashable { case duration, until }

    let mode: Mode
    let initialSeconds: Int
    let initialKeepDisplayOn: Bool
    let onStart: @MainActor (_ kind: AwakeSessionKind, _ keepDisplayOn: Bool) -> Void
    let onExtend: @MainActor (_ seconds: Int) -> Void
    let onCancel: @MainActor () -> Void

    @State private var kind: Kind = .duration
    @State private var hours = 1
    @State private var minutes = 30
    @State private var until = Date().addingTimeInterval(3_600)
    @State private var keepDisplayOn = true
    @State private var loaded = false

    private var seconds: Int { hours * 3_600 + minutes * 60 }
    private var valid: Bool {
        switch (mode, kind) {
        case (.extend, _), (.start, .duration): return AwakeClock.durationRange.contains(seconds)
        case (.start, .until): return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if mode == .start {
                        PickerSetting(L("Keep awake"), selection: $kind, options: [
                            PickerOption(.duration, L("For")), PickerOption(.until, L("Until")),
                        ], style: .segmented, defaultValue: nil)
                    }
                    if mode == .extend || kind == .duration {
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
        .frame(width: 360)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let s = AwakeMath.clamp(initialSeconds, AwakeClock.durationRange)
            hours = s / 3_600
            minutes = (s % 3_600) / 60 / 5 * 5
            keepDisplayOn = initialKeepDisplayOn
        }
    }

    private func commit() {
        switch (mode, kind) {
        case (.extend, _):
            onExtend(seconds)
        case (.start, .duration):
            onStart(.duration(seconds: seconds), keepDisplayOn)
        case (.start, .until):
            let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: until)
            guard let unix = AwakeFormat.nextUnix(hour: c.hour ?? 0, minute: c.minute ?? 0) else { return }
            onStart(.until(unixTime: unix), keepDisplayOn)
        }
    }
}

/// Presents CustomSessionPanel in a small utility window and starts or extends through the session controller.
@MainActor final class CustomSessionWindow {
    private var window: NSPanel?
    weak var context: AwakeContext?

    init() {}

    func present(_ mode: CustomSessionPanel.Mode) {
        guard let ctx = context else { return }
        close()
        let sessions = ctx.config.value.sessions
        let view = CustomSessionPanel(
            mode: mode, initialSeconds: mode == .start ? sessions.lastCustomSeconds : 3_600,
            initialKeepDisplayOn: sessions.defaultOptions.display != .maySleep,
            onStart: { [weak self] kind, keepDisplayOn in self?.start(kind, keepDisplayOn: keepDisplayOn) },
            onExtend: { [weak self] seconds in
                _ = self?.context?.sessions.extend(by: seconds, source: .menu)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() })
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
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

    private func start(_ kind: AwakeSessionKind, keepDisplayOn: Bool) {
        guard let ctx = context else { return }
        if case .duration(let s) = kind { ctx.config.value.sessions.lastCustomSeconds = s }
        var options = ctx.config.value.sessions.effectiveOptions(for: kind, preset: nil,
                                                                  effective: ctx.runtime.effectiveFeatures)
        options.display = keepDisplayOn ? (options.display == .maySleep ? .keepOn : options.display) : .maySleep
        _ = ctx.sessions.start(kind, options: options, presetID: nil, source: .menu, overrideGuards: false)
        close()
    }
}

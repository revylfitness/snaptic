import AppKit
import SwiftUI
import SnapticKit

/// Records a global shortcut (Carbon key code + modifiers). Click, then type the
/// combination; Esc cancels, Delete clears. Invalid combos (⌥-only, no modifier…) are
/// explained and not accepted.
struct ShortcutRecorder: View {
    @Binding var combo: HotkeyCombo?
    /// Optional extra check, such as a clash with another Snaptic shortcut; returns why
    /// the combo can't be used.
    var validate: ((HotkeyCombo) -> String?)? = nil

    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: toggle) {
                    Text(label)
                        .frame(minWidth: 130)
                }
                .accessibilityLabel(recording ? L("Recording shortcut. Type the keys, or Escape to cancel.")
                                              : L("Shortcut: ") + (combo.map(HotkeyRules.displayString) ?? L("none")))
                if combo != nil && !recording {
                    Button {
                        combo = nil
                        message = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L("Clear shortcut"))
                }
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { stop() }
    }

    private var label: String {
        if recording { return L("Type shortcut…") }
        return combo.map(HotkeyRules.displayString) ?? L("Record Shortcut")
    }

    private func toggle() {
        if recording { stop() } else { start() }
    }

    private func start() {
        stop()
        message = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil   // swallowed while recording
        }
    }

    private func handle(_ event: NSEvent) {
        let mods = ModifierConversion.carbon(from: event.modifierFlags)
        if mods == 0 && event.keyCode == 53 {   // Esc
            stop()
            return
        }
        if mods == 0 && (event.keyCode == 51 || event.keyCode == 117) {   // Delete
            combo = nil
            stop()
            return
        }
        let candidate = HotkeyRules.normalized(ModifierConversion.combo(from: event))
        if let problem = HotkeyRules.problem(candidate) {
            message = HotkeyRules.message(problem)
            return
        }
        if let complaint = validate?(candidate) {
            message = complaint
            return
        }
        message = nil
        combo = candidate
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

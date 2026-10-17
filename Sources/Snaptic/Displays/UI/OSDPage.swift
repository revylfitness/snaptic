import SwiftUI
import SnapticKit
import SnapticShims

/// On-Screen Display (PLAN §8.3, §4.10(2)): style and position (separate settings, OS
/// defaults shown), which display shows it, value and nits, the system OSD option on
/// macOS 14/15, a preview, and the broadcast for other apps.
struct OSDPage: View {
    @ObservedObject var env: DisplaysPageEnvironment

    private var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            Section(L("On-screen display")) {
                CFeatureNote(env: env, feature: .osd)
                if env.runtime.isEffective(.osd) {
                    Picker(L("Style"), selection: CBind.global(env, \.keys.osdStyle)) {
                        Text(L("Automatic (\(OSDStyle.osDefault(majorVersion: osMajor).title))")).tag(OSDStyle?.none)
                        ForEach(OSDStyle.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    Picker(L("Position"), selection: CBind.global(env, \.keys.osdPosition)) {
                        Text(L("Automatic (\(OSDPosition.osDefault(majorVersion: osMajor).title))")).tag(OSDPosition?.none)
                        ForEach(OSDPosition.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    if env.config.value.keys.effectiveOSDPosition(osMajor: osMajor) == .topRight && osMajor >= 27 {
                        Text(L("On macOS 27 the system's own HUD also shows at the top right, so the two can overlap."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker(L("Show on"), selection: CBind.global(env, \.keys.osdTarget)) {
                        ForEach(OSDTarget.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle(L("Show the value"), isOn: CBind.global(env, \.keys.osdShowValue))
                    Toggle(L("Show nits"), isOn: CBind.global(env, \.keys.osdShowNits))
                        .disabled(!env.runtime.isEffective(.nits))
                    if osMajor < 26 {
                        Toggle(L("Use the system OSD when possible"), isOn: CBind.global(env, \.keys.osdNative))
                            .disabled(!SNOSD.isAvailable())
                        if !SNOSD.isAvailable() {
                            Text(L("The system OSD isn't available on this Mac.")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Spacer()
                        Button(L("Preview")) { preview() }
                            .disabled(env.context == nil)
                    }
                    Text(L("The OSD doesn't show in screenshots or screen sharing. VoiceOver announces changes whether or not the OSD is on."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Broadcast")) {
                CFeatureNote(env: env, feature: .osdBroadcast)
                if env.runtime.isEffective(.osdBroadcast) {
                    LabeledContent(L("Notification")) { Text(OSDPresenter.broadcastName.rawValue).monospaced().textSelection(.enabled) }
                    Text(L("Other apps can draw their own OSD from Snaptic's changes. Each message carries only the kind (brightness, volume, …), the value and the maximum, at most 10 per second, and nothing while the screen is locked."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func preview() {
        guard let ctx = env.context else { return }
        if let controller = ctx.osd.controller {
            controller.preview()
            return
        }
        guard let display = ctx.registry.displays.first(where: \.isMain) else { return }
        ctx.osd.show(.brightness, value: ctx.brightness.value(for: display.key) ?? 0.6, max: 1, on: display.desktopID,
                     detail: L("Preview"))
    }
}

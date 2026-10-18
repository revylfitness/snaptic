import AppKit
import SwiftUI
import SnapticKit

/// Awake › Advanced (owner: G; PLAN 0.3 §4.3 "Advanced (11)", §2.14, consistency M2): Activity (Appear active, Move
/// the pointer slightly, Stop appearing active after), End sessions automatically, Display, Restart, and the live
/// "Other apps keeping your Mac awake" section. Footer: Restore Awake Defaults… (keeps history, rules, the Menu Bar
/// icon and shortcuts; turns pointer movement and Drive Alive off).
struct AwakeAdvancedSheet: View, ControlDeclaring {
    typealias Controls = AwakeAdvancedSheetControls

    let env: AwakePageEnvironment
    @ObservedObject private var config: ConfigStore<AwakeConfig>

    init(env: AwakePageEnvironment) {
        self.env = env
        _config = ObservedObject(wrappedValue: env.config)
    }

    var body: some View {
        AdvancedSheet(L("Awake Advanced Settings"), restoreDefaults: restore,
                      restoreControl: ControlID("awake.advanced.restore")) {
            activitySection
            endSection
            Section {
                ToggleSetting(L("Keep the display on while locked"),
                              help: L("Sessions that keep the display on also do so on the lock screen."),
                              isOn: SettingsBinding.store(env.config, \.sessions.behavior.keepDisplayOnWhileLocked),
                              anchor: ControlID("awake.advanced.keepDisplayOnWhileLocked"))
            } header: {
                Text(L("Display"))
            }
            restartSection
            OtherAssertionsSection()
        }
    }

    // MARK: Activity

    @ViewBuilder private var activitySection: some View {
        let appearActive = config.value.features[.activity] ?? false
        let nudge = config.value.features[.pointerNudge] ?? false
        let trusted = PermissionFlow.isGranted(.accessibility)
        Section {
            ToggleSetting(L("Appear active"), help: L("Keeps apps from marking you as away while a session runs."),
                          isOn: Binding(get: { appearActive }, set: { on in
                              let next = env.config.value.settingAppearActive(on)
                              if next != env.config.value { env.config.value = next }
                          }),
                          anchor: ControlID("awake.advanced.appearActive"))
            if appearActive {
                ToggleSetting(L("Move the pointer slightly"),
                              help: L("Moves the pointer 1 point and back. Only for sessions you start in Snaptic. Needs Accessibility."),
                              isOn: Binding(get: { nudge }, set: { on in
                                  let next = env.config.value.settingPointerNudge(on)
                                  if next != env.config.value { env.config.value = next }
                              }),
                              subordinate: true, anchor: ControlID("awake.advanced.pointerNudge"), badge: .experimental,
                              disabledReason: nudge || trusted ? nil : L("Needs Accessibility."),
                              fix: nudge || trusted ? nil : accessibilityFix)
                if nudge && !trusted {
                    SettingsRowNote(L("Snaptic needs Accessibility to move the pointer; until then it only appears active."),
                                    fix: accessibilityFix)
                        .padding(.leading, 20)
                }
                PickerSetting(L("Stop appearing active after"),
                              help: L("Counts from when Awake starts appearing active, also across back-to-back sessions."),
                              selection: SettingsBinding.store(env.config, \.activity.stopAfterHours),
                              options: [1, 2, 4, 8].map { PickerOption($0, AwakeCountdown.unit($0, L("hour"), L("hours"))) },
                              style: .popUp, defaultValue: AwakeActivityConfig().stopAfterHours,
                              anchor: ControlID("awake.advanced.stopAfter"), subordinate: true)
            }
        } header: {
            Text(L("Activity"))
        }
    }

    private var accessibilityFix: StatusAction {
        StatusAction(title: L("Open Accessibility Settings…")) {
            SettingsShell.shared.host?.permissions.presentGuide(.accessibility,
                                                                  reason: L("Awake moves the pointer slightly."))
        }
    }

    // MARK: End sessions automatically

    private var endSection: some View {
        Section {
            ToggleSetting(L("When your Mac sleeps"), help: L("When you choose Sleep or close the lid."),
                          isOn: SettingsBinding.store(env.config, \.sessions.behavior.endOnSystemSleep),
                          anchor: ControlID("awake.advanced.endOnSleep"))
            PickerSetting(L("When you switch users"),
                          help: L("Ends the session when someone else uses this Mac."),
                          selection: SettingsBinding.store(env.config, \.sessions.behavior.userSwitchEnd),
                          options: [
                              PickerOption(UserSwitchEnd.immediately, L("Immediately")),
                              PickerOption(UserSwitchEnd.afterHour, L("After 1 Hour")),
                              PickerOption(UserSwitchEnd.never, L("Never")),
                          ],
                          style: .popUp, defaultValue: AwakeBehavior().userSwitchEnd,
                          anchor: ControlID("awake.advanced.userSwitch"))
            ToggleSetting(L("When Low Power Mode turns on"), help: L("Saves battery by letting your Mac sleep as usual."),
                          isOn: SettingsBinding.store(env.config, \.guards.endOnLowPowerMode),
                          anchor: ControlID("awake.advanced.lowPowerMode"))
            PickerSetting(L("After the screen has been locked for"),
                          help: L("Ends a session you may have forgotten about."),
                          selection: SettingsBinding.store(env.config, \.sessions.behavior.endAfterLockedHours),
                          options: lockedOptions,
                          style: .popUp, defaultValue: AwakeBehavior().endAfterLockedHours,
                          anchor: ControlID("awake.advanced.endAfterLocked"))
        } header: {
            Text(L("End sessions automatically"))
        }
    }

    /// Never, 1 hour, 4 hours, 12 hours.
    private var lockedOptions: [PickerOption<Int?>] {
        var out: [PickerOption<Int?>] = [PickerOption(nil, L("Never"))]
        for hours in AwakeBehavior.lockedHoursChoices {
            out.append(PickerOption(hours, AwakeCountdown.unit(hours, L("hour"), L("hours"))))
        }
        return out
    }

    // MARK: Restart

    /// None, then every session in order.
    private func launchOptions(_ presets: [AwakePreset]) -> [PickerOption<StableID?>] {
        var out: [PickerOption<StableID?>] = [PickerOption(nil, L("None"))]
        for preset in presets {
            out.append(PickerOption(preset.id, preset.title(AwakeFormat.text)))
        }
        return out
    }

    private var restartSection: some View {
        let presets = config.value.sessions.presets
        return Section {
            ToggleSetting(L("Continue sessions after Snaptic restarts"),
                          help: L("A session that was running picks up where it left off, until your Mac restarts."),
                          isOn: SettingsBinding.store(env.config, \.sessions.behavior.resumeAfterRestart),
                          anchor: ControlID("awake.advanced.resumeAfterRestart"))
            PickerSetting(L("Start a session when Snaptic opens"),
                          help: L("For example at login, so your Mac stays awake from the start."),
                          selection: SettingsBinding.store(env.config, \.sessions.behavior.startAtLaunch),
                          options: launchOptions(presets),
                          style: .popUp, defaultValue: AwakeBehavior().startAtLaunch,
                          anchor: ControlID("awake.advanced.startAtLaunch"))
        } header: {
            Text(L("Restart"))
        }
    }

    // MARK: Restore

    private var restore: RestoreDefaults {
        let config = env.config
        return RestoreDefaults(scopeName: L("Awake"), destructive: false) {
            let next = config.value.restoringDefaults()
            if next != config.value { config.value = next }
        }
    }
}

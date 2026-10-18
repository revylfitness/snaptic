import AppKit
import SwiftUI
import SnapticKit

/// The Displays step of onboarding (PLAN §3.7, R5.8): multi-select chips; the selection is
/// the union of the chips' flags closed over the feature graph, written exactly (features
/// not chosen are switched off). Permissions are requested afterwards, only for what was
/// chosen. H's Onboarding embeds this view and owns the single primary button (0.3 §4.7): bumping `applyToken`
/// applies the chips and calls `onApply`.
struct DisplaysOnboardingStep: View, ControlDeclaring {
    typealias Controls = DisplaysOnboardingStepControls

    @ObservedObject private var env: DisplaysPageEnvironment
    /// "Hide the menu-bar icon", offered with the keys chip (A owns menu placement).
    private let hideMenuIcon: Binding<Bool>?
    /// Called after the choices are saved, with the permissions they need. When nil, the
    /// step requests them itself (if the module runs).
    private let onApply: ((Set<Permission>) -> Void)?
    /// Changed by the Onboarding footer's primary button: apply now.
    private let applyToken: Int
    @State private var chips: Set<OnboardingChip> = DisplaysOnboardingPlan.defaultChips
    @State private var useSmartHiDPI = false
    @State private var applied = false

    init(env: DisplaysPageEnvironment, hideMenuIcon: Binding<Bool>? = nil, applyToken: Int = 0,
         onApply: ((Set<Permission>) -> Void)? = nil) {
        _env = ObservedObject(wrappedValue: env)
        self.hideMenuIcon = hideMenuIcon
        self.applyToken = applyToken
        self.onApply = onApply
    }

    private var maxEDR: Double {
        let fromRegistry = env.runtime.displays.map(\.edrPotential).max() ?? 1
        let fromScreens = NSScreen.screens.map { Double($0.maximumPotentialExtendedDynamicRangeColorComponentValue) }.max() ?? 1
        return max(fromRegistry, fromScreens)
    }

    private var available: Set<DisplayFeature> {
        Set(DisplayFeature.allCases.filter { env.runtime.availability[$0]?.isAvailable ?? true })
    }

    /// External displays with no HiDPI mode near their native width (Sharper text, `smartHiDPI`, helps them).
    private var displaysWantingSmartHiDPI: [DisplayInfo] {
        env.runtime.displays.filter { d in
            guard !d.isBuiltin, d.isActive, d.transport == .wired || d.transport == .displayLink else { return false }
            let modes = ManagedModes.modes(for: d.desktopID).map(\.ref)
            let native = modes.filter { !$0.isHiDPI }.map(\.pixelWidth).max() ?? 0
            return !DisplayModeChoices.hasHiDPINearNative(modes, nativePixelWidth: native)
        }
    }

    private var plan: [DisplayFeature: Bool] {
        let extra: Set<DisplayFeature> = chips.contains(.sharperText) && useSmartHiDPI ? [.smartHiDPI] : []
        return DisplaysOnboardingPlan.raw(chips: chips, extra: extra, maxEDRPotential: maxEDR, available: available)
    }

    var body: some View {
        Form {
            Section {
                Text(L("What do you want Snaptic to do with your displays?"))
                    .font(.headline)
                    .modifier(SettingsAnchor(ControlID("onboarding.displays.chips")))
                Text(L("Pick any. You can change this later in Settings › Displays."))
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(OnboardingChip.allCases.filter { DisplaysOnboardingPlan.isOffered($0, maxEDRPotential: maxEDR) },
                        id: \.self) { chip in
                    chipRow(chip)
                }
            }
            if chips.contains(.keys), let hideMenuIcon {
                Section {
                    Toggle(L("Hide the menu-bar icon"), isOn: hideMenuIcon)
                    Text(L("The keys keep working. Open Snaptic again from Finder or Spotlight to get to Settings."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if chips.contains(.sharperText) {
                sharperTextSection
            }
            summarySection
        }
        .formStyle(.grouped)
        .onChange(of: applyToken) { _, _ in
            let raw = plan
            apply(raw, permissions: DisplaysOnboardingPlan.permissions(raw))
        }
    }

    private func chipRow(_ chip: OnboardingChip) -> some View {
        let selected = chips.contains(chip)
        return Button {
            if selected { chips.remove(chip) } else { chips.insert(chip) }
            applied = false
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DisplaysOnboardingPlan.title(chip)).font(.body.weight(.medium))
                    Text(DisplaysOnboardingPlan.summary(chip)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selected ? L("Selected. Activate to remove.") : L("Activate to add."))
    }

    @ViewBuilder
    private var sharperTextSection: some View {
        let candidates = displaysWantingSmartHiDPI
        if !candidates.isEmpty {
            Section {
                Toggle(isOn: $useSmartHiDPI) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Turn on Sharper Text (Beta)"))
                        Text(DisplaysOnboardingPlan.sharperTextNote(candidates.map(\.name)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        let raw = plan
        let on = DisplaysOnboardingPlan.turnedOn(raw)
        let permissions = DisplaysOnboardingPlan.permissions(raw)
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return Section(L("Summary")) {
            if on.isEmpty {
                Text(L("Only the Displays panel, display names, and Display Information stay on."))
                    .foregroundStyle(.secondary)
            } else {
                Text(L("Turns on: \(on.map(DisplaysUIText.title).joined(separator: ", ")).")).font(.callout)
            }
            if !permissions.isEmpty {
                Text(L("Needs afterwards: \(Permission.allCases.filter { permissions.contains($0) }.map { DisplaysUIText.permissionName($0, osMajor: osMajor) }.joined(separator: ", ")).")).font(.callout)
            }
            if applied {
                Label(L("Saved"), systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
        }
    }

    private func apply(_ raw: [DisplayFeature: Bool], permissions: Set<Permission>) {
        var value = env.config.value
        for (feature, on) in raw { value.features[feature] = on }
        env.config.value = value
        applied = true
        EventLog.shared.record(.modules, "Onboarding chose \(DisplaysOnboardingPlan.turnedOn(raw).count) display features")
        if let onApply {
            onApply(permissions)
        } else if let ctx = env.context {
            for permission in Permission.allCases where permissions.contains(permission)
                && ctx.permissions.state(permission) != .granted {
                ctx.permissions.presentGuide(permission, reason: L("Display features you chose"))
            }
        }
    }
}

import SwiftUI
import SnapticKit

/// The 0.2 Overview page id ("displays.overview"), kept until the step-3 exit removes `settingsPages()`: it shows the
/// Displays root page, which replaces it (PLAN 0.3 §4.3, §6.2 ✗). The 0.2 pages that still exist share the status
/// section and badge below until they go too.
struct DisplaysOverviewPage: View {
    let env: DisplaysPageEnvironment

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        DisplaysPage(env: env)
    }
}

/// The 0.2 pages' status banners (Safe Mode, paused automation, paused features, unprotected).
struct DisplaysStatusSection: View {
    @ObservedObject private var env: DisplaysPageEnvironment

    init(env: DisplaysPageEnvironment) {
        _env = ObservedObject(wrappedValue: env)
    }

    var body: some View {
        if let ctx = env.context, hasBanner(ctx) {
            Section {
                if case .degraded(let reason) = env.runtime.moduleState {
                    Label(L("Displays is running with problems: \(reason)"), systemImage: "exclamationmark.triangle")
                }
                if ctx.safeMode.isActive {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Safe Mode is on"), systemImage: "exclamationmark.shield").font(.headline)
                        Text(ctx.safeMode.reason ?? L("Snaptic started in Safe Mode."))
                        Text(L("Restoring brightness, layouts, virtual screens, protection and automatic DDC writes is off."))
                            .font(.callout).foregroundStyle(.secondary)
                        Button(L("Leave Safe Mode…")) { ctx.relauncher.relaunch(reason: L("Leave Safe Mode")) }
                    }
                    .accessibilityElement(children: .contain)
                }
                if ctx.panic.isLatched {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Display automation is paused"), systemImage: "pause.circle").font(.headline)
                        Text(env.runtime.lastPanicSummary ?? L("Restore All Displays ran."))
                        Text(L("Layouts, protection, hooks and virtual-screen recreation wait until you resume."))
                            .font(.callout).foregroundStyle(.secondary)
                        // B's registered Resume action (the same one its Tools item and the CLI use).
                        Button(L("Resume Display Automation")) {
                            _ = ctx.actions.perform(PanicCoordinator.resumeActionID, on: .all)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
                let paused = ctx.otherApps.pausedDisplayFeatures
                if !paused.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Some features are paused"), systemImage: "pause.circle").font(.headline)
                        ForEach(DisplaysMenuBuilder.pauseReasons(paused, monitor: ctx.otherApps), id: \.self) { Text($0) }
                        Text(paused.map(DisplaysUIText.title).sorted().joined(separator: ", "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let reason = DisplaysMenuBuilder.unprotectedReason(ctx) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Unprotected"), systemImage: "exclamationmark.shield").font(.headline)
                        Text(reason)
                        Button(L("Restart Snaptic")) { ctx.relauncher.relaunch(reason: L("Restart the safety helper")) }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private func hasBanner(_ ctx: DisplaysContext) -> Bool {
        if case .degraded = env.runtime.moduleState { return true }
        return ctx.safeMode.isActive || ctx.panic.isLatched || !ctx.otherApps.pausedDisplayFeatures.isEmpty
            || DisplaysMenuBuilder.isUnprotected(ctx)
    }
}

/// A small capsule label ("Main", "Beta").
struct DisplaysBadge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(tint)
            .background(Capsule().strokeBorder(tint.opacity(0.6)))
    }
}

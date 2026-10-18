import AppKit
import SnapticKit

/// The diagnostics report (PLAN §12, 0.3 §3.6). Collects the system facts, module state, per-display
/// facts, every DiagnosticsRegistry section and Awake's lines, plus the EventLog tail. Identifiers are
/// masked and display names replaced; titles, app names, serial numbers, EDID bytes and key codes never appear.
/// Display Information shows it live; Copy Display Information Report and `snaptic diagnostics` print the same text.
struct DiagnosticsReport {
    let generated: Date
    let sections: [DiagnosticsSection]
    let events: [String]
    let text: String
}

@MainActor final class DiagnosticsController: DisplayFeatureController {
    static var id: DisplayControllerID { .diagnostics }
    static var privateSymbols: [PrivateSymbol] { [] }
    static let copyAction = DisplayActionID(rawValue: "f.copyDiagnostics")
    static let eventCount = 200
    /// At least EventLog's capacity, so every entry is considered before filtering.
    private static let ringSize = 1_000

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .available }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        self.context = context
        self.lifetime = lifetime
        context.actions.register(Action(id: Self.copyAction, title: L("Copy Display Information Report"), feature: .diagnostics,
                                        cliAllowed: false) { [weak self] _ in
            guard let ctx = self?.context else { return }
            Self.copyToClipboard(Self.makeReport(context: ctx, runtime: ctx.runtime).text)
            ctx.toasts.show(L("Display Information report copied"), lifetime: lifetime)
        }, lifetime: lifetime)
        context.commands.register("diagnostics", policy: .read, offOnly: false, cliAllowed: true,
                                  summary: L("Print the Display Information report (identifiers masked)"),
                                  lifetime: lifetime) { [weak self] _, _ in
            guard let ctx = self?.context else { return .failure(ControlExit.unavailable, L("Displays isn't running")) }
            return .ok(Self.makeReport(context: ctx, runtime: ctx.runtime).text)
        }
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {}
    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {}

    func stop() {
        lifetime = nil
        context = nil
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: Report

    /// Works with the module stopped too (system facts and events only).
    static func makeReport(context: DisplaysContext?, runtime: DisplaysRuntimeState) -> DiagnosticsReport {
        let now = Date()
        var sections: [DiagnosticsSection] = [systemSection()]
        sections.append(moduleSection(context: context, runtime: runtime))
        if let ctx = context {
            sections += displaySections(ctx)
            sections.append(availabilitySection(runtime))
            sections.append(privateAPISection(ctx))
            for entry in ctx.diagnostics.collect() {
                sections.append(DiagnosticsSection(title: entry.section,
                                                   rows: entry.rows.map { DiagnosticsText.scrub(label: $0.0, value: $0.1) }))
            }
            // 0.3 §3.6: Awake's own lines (already free of names and identifiers), only while Awake runs.
            if let awake = DiagnosticsText.awakeSection(ctx.awakeDiagnosticsLines()) { sections.append(awake) }
        }
        // No display name (system, custom or remembered) leaves in a copied or exported report.
        let names = displayNames(context: context, runtime: runtime)
        sections = DiagnosticsText.redacting(sections, names: names)
        let events = eventLines().map { DiagnosticsText.redacting($0, names: names) }
        let iso = ISO8601DateFormatter()
        let text = DiagnosticsText.report(header: "Snaptic diagnostics, \(iso.string(from: now))", sections: sections,
                                          events: events)
        return DiagnosticsReport(generated: now, sections: sections, events: events, text: text)
    }

    private static func systemSection() -> DiagnosticsSection {
        let info = ProcessInfo.processInfo
        let bundle = Bundle.main
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "-"
        var rows = [
            DiagnosticsRow("Snaptic", "\(version) (\(build))"),
            DiagnosticsRow("macOS", info.operatingSystemVersionString),
            DiagnosticsRow("Model", sysctlString("hw.model") ?? "unknown"),
            DiagnosticsRow("Chip", sysctlString("machdep.cpu.brand_string") ?? "unknown"),
            DiagnosticsRow("Architecture", sysctlString("hw.machine") ?? "unknown"),
            DiagnosticsRow("Memory", "\(info.physicalMemory / (1 << 30)) GB"),
        ]
        if sysctlInt("sysctl.proc_translated") == 1 { rows.append(DiagnosticsRow("Rosetta", "yes")) }
        rows.append(DiagnosticsRow("Screens (AppKit)", "\(NSScreen.screens.count)"))
        rows.append(DiagnosticsRow("Reduce Motion", NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? "on" : "off"))
        rows.append(DiagnosticsRow("VoiceOver", NSWorkspace.shared.isVoiceOverEnabled ? "on" : "off"))
        return DiagnosticsSection(title: "System", rows: rows)
    }

    private static func moduleSection(context: DisplaysContext?, runtime: DisplaysRuntimeState) -> DiagnosticsSection {
        var rows: [DiagnosticsRow] = []
        switch runtime.moduleState {
        case .stopped: rows.append(DiagnosticsRow("State", "stopped"))
        case .running: rows.append(DiagnosticsRow("State", "running"))
        case .degraded(let reason): rows.append(DiagnosticsText.scrub(label: "State", value: "degraded: \(reason)"))
        }
        guard let ctx = context else { return DiagnosticsSection(title: "Displays module", rows: rows) }
        rows.append(DiagnosticsText.scrub(label: "Safe Mode",
                                          value: ctx.safeMode.isActive ? "on (\(ctx.safeMode.reason ?? "no reason"))" : "off"))
        rows.append(DiagnosticsRow("Panic latch", ctx.panic.isLatched ? "latched" : "off"))
        if let summary = runtime.lastPanicSummary { rows.append(DiagnosticsText.scrub(label: "Last panic", value: summary)) }
        rows.append(DiagnosticsRow("Unprotected", DisplaysLive.unprotectedReason(ctx) != nil ? "yes" : "no"))
        rows.append(DiagnosticsRow("Guard helper", ctx.guardClient.isAlive ? "running" : "not running"))
        rows.append(DiagnosticsText.scrub(label: "Helpers", value: ctx.helpers.unavailable.map { "unavailable: \($0)" } ?? "available"))
        rows.append(DiagnosticsRow("Virtual hosts", "\(ctx.virtualHosts.liveDisplays.count)"))
        rows.append(DiagnosticsRow("Transactions", ctx.transactions.isBusy ? "busy" : "idle"))
        rows.append(DiagnosticsRow("Session", ctx.sessionGate.isOpen ? "open" : "paused"))
        let effective = DisplayFeature.allCases.filter { runtime.effectiveFeatures.contains($0) }
        rows.append(DiagnosticsRow("Effective features (\(effective.count))", effective.map(\.rawValue).joined(separator: ", ")))
        let raw = ctx.config.value.rawFeatures
        let onButInactive = DisplayFeature.allCases.filter { FeatureGraph.rawState($0, in: raw) && !runtime.effectiveFeatures.contains($0) }
        rows.append(DiagnosticsRow("On but not effective", onButInactive.isEmpty ? "none" : onButInactive.map(\.rawValue).joined(separator: ", ")))
        let paused = DisplayFeature.allCases.filter { ctx.otherApps.pausedDisplayFeatures.contains($0) }
        rows.append(DiagnosticsRow("Paused for other apps", paused.isEmpty ? "none" : paused.map(\.rawValue).joined(separator: ", ")))
        let kill = killSwitches()
        rows.append(DiagnosticsRow("Kill switches", kill.isEmpty ? "none" : kill.map(\.rawValue).joined(separator: ", ")))
        let services = FeatureGraph.activationOrder.filter { FeatureGraph.requiredServices(effective: runtime.effectiveFeatures).contains($0) }
        rows.append(DiagnosticsRow("Services", services.map(\.rawValue).joined(separator: ", ")))
        return DiagnosticsSection(title: "Displays module", rows: rows)
    }

    private static func displaySections(_ ctx: DisplaysContext) -> [DiagnosticsSection] {
        let displays = DisplaysMenuBuilder.orderedDisplays(ctx, includeHidden: true)
        guard !displays.isEmpty else {
            return [DiagnosticsSection(title: "Displays", rows: [DiagnosticsRow("Registry", "no displays")])]
        }
        var sections: [DiagnosticsSection] = []
        for (index, d) in displays.enumerated() {
            var state: [String] = [d.isOnline ? "online" : "offline", d.isActive ? "active" : "inactive"]
            if d.isMain { state.append("main") }
            if d.isBuiltin { state.append("built-in") }
            if d.isStronglyVisible {
                state.append("strongly visible")
            } else if d.isWeaklyVisible {
                state.append("weakly visible")
            } else {
                state.append("not visible")
            }
            var mode = "unknown"
            if let current = d.currentMode {
                mode = DisplaysUIText.modeLabel(current.ref) + (current.isNative ? ", native" : "")
            }
            var hdr = "unsupported or unknown"
            if d.hdrSupported == true { hdr = d.hdrEnabled == true ? "on" : "off" }
            var rows: [DiagnosticsRow] = [
                DiagnosticsRow("Key", DiagnosticsText.shortKey(d.key)),
                DiagnosticsRow("Transport", d.transport.rawValue),
                DiagnosticsRow("State", state.joined(separator: ", ")),
                DiagnosticsRow("Mode", mode),
                DiagnosticsRow("Rotation", "\(d.rotation)°"),
                DiagnosticsRow("HDR", hdr),
                DiagnosticsRow("EDR potential", String(format: "%.2f", d.edrPotential)),
            ]
            if let size = DisplaysUIText.diagonalInches(widthMM: d.physicalSizeMM.width, heightMM: d.physicalSizeMM.height) {
                rows.append(DiagnosticsRow("Size", String(format: "%.1f in", size)))
            }
            if d.mirrorOf != nil { rows.append(DiagnosticsRow("Mirroring", "yes")) }
            if d.isSmartHiDPIPair { rows.append(DiagnosticsRow("Smart HiDPI pair", "yes")) }
            if d.notchInset > 0 { rows.append(DiagnosticsRow("Notch inset", String(format: "%.0f pt", d.notchInset))) }
            let method = ctx.brightness.activeMethod(for: d.key)?.rawValue ?? "none"
            let methods = ctx.brightness.methods(for: d.key).map(\.rawValue).joined(separator: ", ")
            rows.append(DiagnosticsRow("Brightness method", methods.isEmpty ? method : "\(method) (of \(methods))"))
            rows.append(DiagnosticsRow("DDC", ctx.ddc.isAvailable(d.key) ? "available" : "not available"))
            let live = ctx.runtime.runtime(for: d.key)
            if let status = live.statusText { rows.append(DiagnosticsText.scrub(label: "Status", value: status)) }
            sections.append(DiagnosticsSection(title: DiagnosticsText.displayTitle(number: index + 1, isBuiltin: d.isBuiltin),
                                               rows: rows))
        }
        return sections
    }

    /// Every name a display goes by: connected ones' system names and the names Snaptic remembers.
    private static func displayNames(context: DisplaysContext?, runtime: DisplaysRuntimeState) -> [String] {
        var names = runtime.displays.map(\.name)
        if let config = context?.config.value {
            for identity in config.perDisplay.values.values.map(\.identity) {
                names += [identity.customName, identity.lastKnownName].compactMap { $0 }
            }
        }
        return names
    }

    private static func availabilitySection(_ runtime: DisplaysRuntimeState) -> DiagnosticsSection {
        let rows = DisplayFeature.allCases.compactMap { feature -> DiagnosticsRow? in
            guard case .unavailable(let reason)? = runtime.availability[feature] else { return nil }
            return DiagnosticsText.scrub(label: feature.rawValue, value: reason)
        }
        return DiagnosticsSection(title: "Unavailable features", rows: rows)
    }

    private static func privateAPISection(_ ctx: DisplaysContext) -> DiagnosticsSection {
        let missing = ctx.privateAPI.unavailableFeatures()
        let rows = DisplayFeature.allCases.compactMap { feature -> DiagnosticsRow? in
            guard let reason = missing[feature] else { return nil }
            return DiagnosticsText.scrub(label: feature.rawValue, value: reason)
        }
        return DiagnosticsSection(title: "Private API", rows: rows.isEmpty ? [DiagnosticsRow("Missing symbols", "none")] : rows)
    }

    /// The event tail: the newest `eventCount` exported entries (0.3 §3.6: Awake's events never leave the app this
    /// way; they have their own counted summary), read from the whole ring so the filter doesn't shorten the tail.
    private static func eventLines() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        let entries = DiagnosticsText.exportedEvents(EventLog.shared.recent(ringSize), category: { $0.category },
                                                     limit: eventCount)
        return entries.map { entry in
            DiagnosticsText.scrubText("\(formatter.string(from: entry.date)) [\(entry.category.rawValue)] \(entry.message)")
        }
    }

    /// The same persistent-domain keys DisplaysModule reads (`Displays.disable.<feature>`).
    private static func killSwitches() -> [DisplayFeature] {
        let set = KillSwitches.read(UserDefaults.standard.persistentDomain(
            forName: ConfigStore<DisplaysConfig>.persistentDomainName), prefix: "Displays", as: DisplayFeature.self)
        return DisplayFeature.allCases.filter { set.contains($0) }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 4096 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix(min(size, buffer.count)).prefix { $0 != 0 }
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

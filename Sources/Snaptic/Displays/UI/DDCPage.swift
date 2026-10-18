import SwiftUI
import SnapticKit

/// Monitor Controls (PLAN §7, parity §6): DDC status and capabilities per display,
/// timing, per-control tuning and readback, the input list (rename, hide, reorder,
/// LG alternate), standby / power-on, custom VCP controls, raw get/set and manufacturer
/// unlocks. Every write goes through DDCController (VCP policy + confirmation).
struct DDCPage: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State private var selected: DisplayKey?
    @State private var capsLoading = false
    @State private var rawCode = ""
    @State private var rawValue = ""
    @State private var rawResult: String?
    @State private var unlockText = ""
    @State private var unlockMessage: String?
    @State private var newCustomName = ""
    @State private var newCustomCode = ""
    @State private var newCustomKind = DDCCustomControl.Kind.range
    @State private var newCustomValue = ""

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            Section {
                ForEach([DisplayFeature.ddcControls, .ddcInput, .ddcPower, .ddcCustom], id: \.self) {
                    CFeatureNote(env: env, feature: $0)
                }
            }
            globalSection
            if let ctx = env.context, !ddcDisplays.isEmpty {
                Section(L("Display")) {
                    CDisplayPicker(env: env, selection: $selected, filter: { !$0.isBuiltin })
                    if let key = selectedKey { statusRows(ctx, key) }
                }
                if let key = selectedKey, ctx.ddc.isAvailable(key) {
                    if env.runtime.isEffective(.ddcControls) { controlsSection(ctx, key) }
                    if env.runtime.isEffective(.ddcInput) { inputsSection(ctx, key) }
                    if env.runtime.isEffective(.ddcPower) { powerSection(ctx, key) }
                    if env.runtime.isEffective(.ddcCustom) {
                        customSection(ctx, key)
                        rawSection(ctx, key)
                    }
                    timingSection(key)
                    allowedSection(ctx, key)
                }
            } else if env.context != nil {
                Section { Text(L("No external display is connected.")).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private var ddcDisplays: [DisplayInfo] { env.runtime.displays.filter { $0.isOnline && !$0.isBuiltin } }

    private var selectedKey: DisplayKey? {
        if let selected, ddcDisplays.contains(where: { $0.key == selected }) { return selected }
        return ddcDisplays.first?.key
    }

    private var controller: DDCController? { env.context?.ddc.controller }

    // MARK: Global

    @ViewBuilder
    private var globalSection: some View {
        Section(L("All monitors")) {
            Toggle(L("Read values back periodically"), isOn: CBind.global(env, \.ddc.readback))
            if env.config.value.ddc.readback {
                CSlider(title: L("Every"), value: CBind.global(env, \.ddc.defaultReadbackInterval), range: 0.5...60, step: 0.5,
                        format: { String(format: "%.1f s", $0) })
            }
            Toggle(L("Re-send values after wake when the monitor reports something different"),
                   isOn: CBind.global(env, \.ddc.restoreOnWake))
            Text(L("Readback notices changes made with the monitor's own buttons (needed for syncing those). DDC writes pause during sleep, display changes and while you're switched out; Safe Mode skips automatic writes."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Status

    @ViewBuilder
    private func statusRows(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        Toggle(L("Use DDC with this display"), isOn: CBind.display(env, key, \.ddc.enabled))
        let ddc = ctx.ddc
        LabeledContent(L("Status")) {
            switch ddc.linkStatus(key) {
            case .ok: Text(L("Responding"))
            case .failed: Text(L("No reply"))
            case .unknown: Text(L("Not checked yet"))
            }
        }
        if let transport = ddc.transportDescription(key) { LabeledContent(L("Connection")) { Text(transport) } }
        if let framing = ddc.framing(key) { LabeledContent(L("Framing")) { Text(framing.rawValue) } }
        LabeledContent(L("Writes today")) { Text(String(ddc.writesToday(key))) }
        if let caps = ddc.cachedCapabilities(key) {
            if let model = caps.model { LabeledContent(L("Model")) { Text(TextSanitizer.clean(model, maxScalars: 64)) } }
            if let mccs = caps.mccsVersion { LabeledContent(L("MCCS")) { Text(TextSanitizer.clean(mccs, maxScalars: 16)) } }
            Text(L("Supported codes: ") + caps.vcp.keys.sorted().map { VCPPolicy.hex($0) }.joined(separator: " "))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        HStack {
            Button(capsLoading ? L("Reading…") : L("Read Capabilities")) {
                capsLoading = true
                ctx.lifetime.spawn {
                    _ = await ddc.capabilities(of: key, refresh: true)
                    capsLoading = false
                    env.objectWillChange.send()
                }
            }
            .disabled(capsLoading)
            Button(L("Check Connection")) {
                ctx.lifetime.spawn {
                    _ = await ddc.probe(key)
                    env.objectWillChange.send()
                }
            }
        }
        if !ddc.isAvailable(key) {
            Text(L("This display didn't answer DDC. Many TVs, DisplayLink adapters, some docks and the HDMI port on some Macs don't pass DDC; Snaptic dims these in software."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Controls

    private func knownCodes(_ ctx: DisplaysContext, _ key: DisplayKey) -> [UInt8] {
        let base: [UInt8] = [VCPPolicy.brightness, VCPPolicy.contrast, VCPPolicy.volume]
        let listed = ctx.ddc.cachedCapabilities(key)?.vcp.keys.filter { VCPPolicy.continuousCodes.contains($0) } ?? []
        return Array(Set(base).union(listed)).sorted()
    }

    @ViewBuilder
    private func controlsSection(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        Section(L("Controls")) {
            let live = env.runtime.runtime(for: key)
            if let controller {
                if controller.isControlEnabled(VCPPolicy.volume, for: key) {
                    CLiveSlider(title: L("Volume"), live: live, value: \.volume) {
                        controller.setFraction(VCPPolicy.volume, $0, for: key)
                    }
                }
                if controller.isControlEnabled(VCPPolicy.contrast, for: key) {
                    CLiveSlider(title: L("Contrast"), live: live, value: \.contrast) {
                        controller.setFraction(VCPPolicy.contrast, $0, for: key)
                    }
                }
            }
            ForEach(knownCodes(ctx, key), id: \.self) { code in
                DisclosureGroup(VCPPolicy.name(code) + " (" + VCPPolicy.hex(code) + ")") {
                    tuningRows(ctx, key, code)
                }
            }
            Text(L("Tuning maps 0–100% onto the monitor's raw range. Brightness, contrast and volume show in the menu by default."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tuning(_ key: DisplayKey, _ code: UInt8) -> Binding<DDCControlTuning> {
        Binding(get: { env.config.value.perDisplay[key]?.ddc.tuning(code) ?? DDCControlTuning() },
                set: { value in
                    var config = env.config.value
                    var per = config.perDisplay[key] ?? PerDisplayConfig()
                    per.ddc.controls[VCPKey(code)] = value.sanitized()
                    config.perDisplay[key] = per
                    env.config.value = config
                })
    }

    @ViewBuilder
    private func tuningRows(_ ctx: DisplaysContext, _ key: DisplayKey, _ code: UInt8) -> some View {
        let t = tuning(key, code)
        let reportedMax = ctx.ddc.lastReading(code, of: key)?.max
        Picker(L("Use"), selection: Binding(get: { t.wrappedValue.enabled }, set: { t.wrappedValue.enabled = $0 })) {
            Text(L("Automatic")).tag(Bool?.none)
            Text(L("On")).tag(Optional(true))
            Text(L("Off")).tag(Optional(false))
        }
        LabeledContent(L("Raw value for 0%")) {
            TextField(L("Minimum"), value: Binding(get: { Int(t.wrappedValue.minimum) },
                                                    set: { t.wrappedValue.minimum = UInt16(clamping: $0) }), format: .number)
                .frame(width: 80)
        }
        LabeledContent(L("Raw value for 100%")) {
            HStack {
                TextField(L("Maximum"), value: Binding(get: { Int(t.wrappedValue.maximum ?? reportedMax ?? 100) },
                                                        set: { t.wrappedValue.maximum = UInt16(clamping: $0) }), format: .number)
                    .frame(width: 80)
                if t.wrappedValue.maximum != nil {
                    Button(L("Reported")) { t.wrappedValue.maximum = nil }
                }
            }
        }
        Toggle(L("Invert"), isOn: Binding(get: { t.wrappedValue.inverted }, set: { t.wrappedValue.inverted = $0 }))
        Picker(L("Show in menu"), selection: Binding(get: { t.wrappedValue.showInMenu }, set: { t.wrappedValue.showInMenu = $0 })) {
            Text(L("Default")).tag(Bool?.none)
            Text(L("Yes")).tag(Optional(true))
            Text(L("No")).tag(Optional(false))
        }
        LabeledContent(L("Read back every (s, 0 = default)")) {
            TextField(L("Seconds"), value: Binding(get: { t.wrappedValue.readbackInterval },
                                                    set: { t.wrappedValue.readbackInterval = $0 }), format: .number)
                .frame(width: 80)
        }
    }

    // MARK: Inputs

    private func savedInputs(_ key: DisplayKey) -> Binding<[DDCInputEntry]> {
        Binding(get: {
            // Start from the controller's merged list (saved + listed by capabilities).
            controller?.inputList(for: key, includeHidden: true) ?? (env.config.value.perDisplay[key]?.ddc.inputs ?? [])
        }, set: { value in
            var config = env.config.value
            var per = config.perDisplay[key] ?? PerDisplayConfig()
            per.ddc.inputs = Array(value.prefix(PerDisplayDDC.maxInputs))
            config.perDisplay[key] = per
            env.config.value = config
        })
    }

    @ViewBuilder
    private func inputsSection(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        Section(L("Inputs")) {
            let list = savedInputs(key)
            let live = env.runtime.runtime(for: key)
            ForEach(Array(list.wrappedValue.enumerated()), id: \.element.id) { index, entry in
                HStack {
                    Image(systemName: live.input == entry.value && !entry.lgAlt ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField(VCPPolicy.inputName(entry.value),
                              text: Binding(get: { entry.name }, set: { name in
                                  var l = list.wrappedValue
                                  guard l.indices.contains(index) else { return }
                                  l[index].name = String(name.prefix(64))
                                  list.wrappedValue = l
                              }))
                    Text(String(format: entry.lgAlt ? "LG %02X" : "%02X", Int(entry.value)))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    Toggle(L("Hide"), isOn: Binding(get: { entry.hidden }, set: { hidden in
                        var l = list.wrappedValue
                        guard l.indices.contains(index) else { return }
                        l[index].hidden = hidden
                        list.wrappedValue = l
                    }))
                    .toggleStyle(.checkbox)
                    Button { move(list, index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(index == 0)
                        .accessibilityLabel(L("Move up"))
                    Button { move(list, index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).disabled(index == list.wrappedValue.count - 1)
                        .accessibilityLabel(L("Move down"))
                    Button(L("Switch")) { controller?.setInput(entry, on: key) }
                }
            }
            HStack {
                Menu(L("Add Input")) {
                    ForEach([UInt16](DisplaysUIText.commonInputs), id: \.self) { value in
                        Button(VCPPolicy.inputName(value)) { add(list, DDCInputEntry(value: value, name: "")) }
                    }
                    Divider()
                    ForEach([UInt16](DisplaysUIText.commonInputs), id: \.self) { value in
                        Button(L("LG alternate: ") + VCPPolicy.inputName(value)) {
                            add(list, DDCInputEntry(value: value, name: "", lgAlt: true))
                        }
                    }
                }
                Spacer()
                Button(L("Reset List")) {
                    var config = env.config.value
                    var per = config.perDisplay[key] ?? PerDisplayConfig()
                    per.ddc.inputs = []
                    config.perDisplay[key] = per
                    env.config.value = config
                }
            }
            Text(L("Switching input asks first, because this Mac may lose the picture. LG alternate inputs use LG's own command (some LG monitors need it for USB-C and DisplayPort). Assign inputs to shortcuts under Keys & Shortcuts → Input slots."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func move(_ list: Binding<[DDCInputEntry]>, _ index: Int, by delta: Int) {
        var l = list.wrappedValue
        let target = index + delta
        guard l.indices.contains(index), l.indices.contains(target) else { return }
        l.swapAt(index, target)
        list.wrappedValue = l
    }

    private func add(_ list: Binding<[DDCInputEntry]>, _ entry: DDCInputEntry) {
        var l = list.wrappedValue
        guard !l.contains(where: { $0.id == entry.id }) else { return }
        l.append(entry)
        list.wrappedValue = l
    }

    // MARK: Power

    @ViewBuilder
    private func powerSection(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        Section(L("Power")) {
            let live = env.runtime.runtime(for: key)
            LabeledContent(L("State")) {
                Text(live.powerOn.map { $0 ? L("On") : L("Standby") } ?? L("Unknown"))
            }
            Picker(L("Standby sends"), selection: CBind.display(env, key, \.ddc.standbyValue)) {
                Text(L("Standby (2)")).tag(UInt16(2))
                Text(L("Suspend (3)")).tag(UInt16(3))
                Text(L("Off (4)")).tag(UInt16(4))
            }
            HStack {
                Button(L("Turn On")) { controller?.setPower(true, on: key) }
                Button(L("Standby…")) { controller?.setPower(false, on: key) }
                    .disabled(!ctx.registry.displays.contains { $0.key != key && $0.isOnline && $0.isStronglyVisible })
            }
            Text(L("Standby asks first and is refused for the only display you can see. Some monitors only wake with their power button."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Custom controls

    private func customList(_ key: DisplayKey) -> Binding<[DDCCustomControl]> {
        Binding(get: { env.config.value.perDisplay[key]?.ddc.customControls ?? [] },
                set: { value in
                    var config = env.config.value
                    var per = config.perDisplay[key] ?? PerDisplayConfig()
                    per.ddc.customControls = Array(value.prefix(PerDisplayDDC.maxCustom))
                    config.perDisplay[key] = per
                    env.config.value = config
                })
    }

    @ViewBuilder
    private func customSection(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        Section(L("Custom controls")) {
            let list = customList(key)
            ForEach(list.wrappedValue) { control in
                customRow(key, list, control)
            }
            HStack {
                TextField(L("Name"), text: $newCustomName).frame(minWidth: 100)
                TextField(L("Code (hex)"), text: $newCustomCode).frame(width: 80)
                Picker(L("Kind"), selection: $newCustomKind) {
                    Text(L("Slider")).tag(DDCCustomControl.Kind.range)
                    Text(L("Command")).tag(DDCCustomControl.Kind.command)
                }
                .labelsHidden()
                .frame(width: 110)
                if newCustomKind == .command {
                    TextField(L("Value"), text: $newCustomValue).frame(width: 70)
                }
                Button(L("Add")) {
                    guard let code = VCPPolicy.parseCode(newCustomCode) else { return }
                    let value = UInt16(newCustomValue) ?? 0
                    var l = list.wrappedValue
                    l.append(DDCCustomControl(name: String(newCustomName.prefix(64)), code: code, kind: newCustomKind, value: value))
                    list.wrappedValue = l
                    newCustomName = ""
                    newCustomCode = ""
                    newCustomValue = ""
                }
                .disabled(VCPPolicy.parseCode(newCustomCode) == nil)
            }
            Text(L("Commands that can switch the picture away or change power ask first; codes 0xE0–0xFF must be unlocked below; reset and factory codes are never sent."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func customRow(_ key: DisplayKey, _ list: Binding<[DDCCustomControl]>, _ control: DDCCustomControl) -> some View {
        HStack {
            Text((control.name.isEmpty ? VCPPolicy.name(control.code) : control.name) + " (" + VCPPolicy.hex(control.code) + ")")
            Spacer()
            if control.kind == .command {
                Text("= \(control.value)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Button(L("Send")) { controller?.runCustom(control, on: key) }
            }
            Toggle(L("In menu"), isOn: Binding(get: { control.showInMenu }, set: { on in
                var l = list.wrappedValue
                if let i = l.firstIndex(where: { $0.id == control.id }) { l[i].showInMenu = on }
                list.wrappedValue = l
            }))
            .toggleStyle(.checkbox)
            Button { list.wrappedValue = list.wrappedValue.filter { $0.id != control.id } } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("Remove"))
        }
        if control.kind == .range {
            CustomSliderRow(controller: controller, control: control, key: key)
        }
    }

    // MARK: Raw get/set and unlocks

    @ViewBuilder
    private func rawSection(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        Section(L("Raw VCP")) {
            HStack {
                TextField(L("Code (hex)"), text: $rawCode).frame(width: 90)
                TextField(L("Value"), text: $rawValue).frame(width: 90)
                Button(L("Read")) {
                    guard let code = VCPPolicy.parseCode(rawCode) else { rawResult = L("Not a VCP code"); return }
                    let ddc = ctx.ddc
                    rawResult = L("Reading…")
                    ctx.lifetime.spawn {
                        if let r = await ddc.read(code, from: key) {
                            rawResult = "\(VCPPolicy.hex(code)) = \(r.current) / \(r.max)"
                        } else {
                            rawResult = L("No reply")
                        }
                    }
                }
                Button(L("Send")) {
                    guard let code = VCPPolicy.parseCode(rawCode),
                          let value = UInt16(rawValue) ?? UInt16(rawValue.replacingOccurrences(of: "0x", with: ""), radix: 16) else {
                        rawResult = L("Enter a code and a value")
                        return
                    }
                    let controller = controller
                    rawResult = L("Sending…")
                    ctx.lifetime.spawn {
                        let ok = await controller?.write(code, value, to: key) ?? false
                        rawResult = ok ? L("Sent") : L("Refused, not confirmed, or no reply")
                    }
                }
            }
            if let rawResult { Text(rawResult).font(.callout.monospaced()) }
            HStack {
                TextField(L("Manufacturer code to unlock (E0–FF)"), text: $unlockText)
                Button(L("Unlock")) { unlock(key) }
            }
            if let unlockMessage { Text(unlockMessage).font(.caption) }
            let unlocked = env.config.value.perDisplay[key]?.ddc.unlockedCodes ?? []
            if !unlocked.isEmpty {
                HStack {
                    Text(L("Unlocked: ") + unlocked.map(\.rawValue).joined(separator: " ")).font(.caption.monospaced())
                    Spacer()
                    Button(L("Lock All")) {
                        var config = env.config.value
                        var per = config.perDisplay[key] ?? PerDisplayConfig()
                        per.ddc.unlockedCodes = []
                        config.perDisplay[key] = per
                        env.config.value = config
                    }
                }
            }
            Text(L("Manufacturer codes do different things on every monitor; an unlocked code still asks before each write."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func unlock(_ key: DisplayKey) {
        guard let code = VCPPolicy.parseCode(unlockText),
              VCPPolicy.tier(code: code, value: 0, capabilities: nil) == .unlockable else {
            unlockMessage = L("Only manufacturer codes E0–FF (other than the ones Snaptic always asks about) can be unlocked.")
            return
        }
        var config = env.config.value
        var per = config.perDisplay[key] ?? PerDisplayConfig()
        if !per.ddc.isUnlocked(code) { per.ddc.unlockedCodes.append(VCPKey(code)) }
        config.perDisplay[key] = per
        env.config.value = config
        unlockText = ""
        unlockMessage = L("Unlocked \(VCPPolicy.hex(code)) for this display.")
    }

    // MARK: Timing

    @ViewBuilder
    private func timingSection(_ key: DisplayKey) -> some View {
        Section(L("Timing")) {
            Stepper(value: CBind.display(env, key, \.ddc.replyDelayMs), in: 10...200, step: 10) {
                LabeledContent(L("Reply delay")) { Text("\(env.config.value.perDisplay[key]?.ddc.replyDelayMs ?? DDCPacket.defaultReplyDelayMs) ms") }
            }
            Stepper(value: CBind.display(env, key, \.ddc.retries), in: 0...8) {
                LabeledContent(L("Retries")) { Text(String(env.config.value.perDisplay[key]?.ddc.retries ?? DDCPacket.defaultRetries)) }
            }
            Toggle(L("Send every write twice (flaky monitors)"), isOn: Binding(
                get: { (env.config.value.perDisplay[key]?.ddc.writeCount ?? 1) > 1 },
                set: { CBind.display(env, key, \.ddc.writeCount).wrappedValue = $0 ? 2 : 1 }))
            Toggle(L("Ignore reply checksums"), isOn: CBind.display(env, key, \.ddc.ignoreChecksum))
            Button(L("Forget Learned Framing")) { CBind.display(env, key, \.ddc.framing).wrappedValue = nil }
        }
    }

    // MARK: Allowed without asking

    @ViewBuilder
    private func allowedSection(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        let entries = env.config.value.safety.preConfirmAllowed[key]?.entries ?? []
        if !entries.isEmpty {
            Section(L("Allowed without asking")) {
                Text(entries.joined(separator: "  ")).font(.caption.monospaced())
                Button(L("Ask Again for Everything")) { ctx.preConfirm.revokeAll(for: key) }
            }
        }
    }
}

/// A custom range control: a slider that sends on release-coalesced changes.
private struct CustomSliderRow: View {
    let controller: DDCController?
    let control: DDCCustomControl
    let key: DisplayKey
    @State private var value: Double = 0.5

    var body: some View {
        CSlider(title: control.name.isEmpty ? VCPPolicy.name(control.code) : control.name,
                value: Binding(get: { value }, set: { v in
                    value = v
                    controller?.runCustom(control, on: key, fraction: v)
                }), range: 0...1)
    }
}

import AppKit
import CoreGraphics
import SwiftUI
import SnapticKit

// The rule editor's condition rows (owner: G; PLAN 0.3 §4.3 "Rule editor sheet", §1.1 criterion kinds, §2.7):
// "[kind ▾] [is ▾ / is not ▾] [kind-specific fields] [−]". Choices come from what is there now: running apps, the
// connected displays, mounted drives, USB devices and the current network. Names are local UI only.

/// One connected display for "When this display is connected" (salted record, as DisplayPresence computes it).
struct AwakeDisplayChoice: Equatable {
    let record: FingerprintRecord
    let name: String
    let isBuiltin: Bool
}

/// What the condition pickers list while the rule editor is open (owner: G). The picker sources a rule doesn't
/// already use are activated for the editor and deactivated when it closes, unless the module needs them by then
/// (`AwakeFeatureGraph.requiredServices` is the module's own rule, so the editor never stops a service in use).
@MainActor final class AwakePickerSources: ObservableObject {
    /// Bumped when a source reports a change.
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var displays: [AwakeDisplayChoice] = []

    /// Strong while borrowing: the borrowed services are released even if the module stops meanwhile.
    private var context: AwakeContext?
    private var borrowed: Set<AwakeServiceID> = []
    private var lifetime: Lifetime?
    static let pickerServices: [AwakeServiceID] = [.usb, .volumes, .network, .bluetooth]

    func begin(_ ctx: AwakeContext?) {
        displays = Self.readDisplays()
        guard let ctx, context == nil else { return }
        context = ctx
        let life = Lifetime()
        lifetime = life
        let needed = Self.needed(ctx)
        for id in Self.pickerServices where !needed.contains(id) {
            ctx.service(id).activate(ctx, lifetime: life)
            borrowed.insert(id)
        }
        let sources: [any CriterionSource] = [ctx.usb, ctx.volumes, ctx.network, ctx.bluetooth]
        for source in sources {
            source.observe(life) { [weak self] in self?.revision &+= 1 }
        }
        ctx.sessions.appPickerOpen = true
    }

    func end() {
        guard let ctx = context else { return }
        let needed = Self.needed(ctx)
        for id in Self.pickerServices where borrowed.contains(id) && !needed.contains(id) {
            ctx.service(id).deactivate()
        }
        borrowed = []
        lifetime?.end()
        lifetime = nil
        ctx.sessions.appPickerOpen = false
        context = nil
    }

    /// The module's own need rule (AwakeModule.apply).
    private static func needed(_ ctx: AwakeContext) -> Set<AwakeServiceID> {
        AwakeFeatureGraph.requiredServices(effective: ctx.runtime.effectiveFeatures,
                                           criteria: TriggerEngine.requiredKinds(ctx.config.value.triggers.triggers),
                                           dynamic: ctx.sessions.dynamicNeeds)
    }

    // MARK: Lists

    /// Running apps (regular and accessory), by name.
    var apps: [(bundleID: String, name: String)] {
        AppMonitor().choices().filter { AwakeBundleID.isValid($0.bundleID) }.map { (bundleID: $0.bundleID, name: $0.name) }
    }

    /// Mounted drives that have a volume UUID.
    var volumes: [(uuid: String, name: String)] {
        var out: [(uuid: String, name: String)] = []
        for v in context?.volumes.volumes ?? [] {
            if let uuid = v.uuid { out.append((uuid: uuid.rawValue, name: v.name)) }
        }
        return out
    }

    var usbDevices: [USBWatcher.USBDevice] { context?.usb.connected ?? [] }

    /// Connected Bluetooth audio and input devices (J's BluetoothPresence; Beta).
    var bluetoothDevices: [BluetoothPresence.Device] { context?.bluetooth.devices ?? [] }

    /// The current router's salted hash ("Connected to this network").
    var currentRouterHash: String? { context?.network.currentRouterHash }

    /// The first thing to pick for a kind that needs a choice (nil: nothing there now).
    func firstCriterion(_ choice: AwakeCriterionChoice) -> AwakeCriterion? {
        if let c = choice.defaultCriterion { return c }
        switch choice {
        case .app:
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let list = apps
            guard let pick = list.first(where: { $0.bundleID == front }) ?? list.first else { return nil }
            return .app(bundleID: pick.bundleID, name: pick.name, frontmost: false)
        case .volume:
            return volumes.first.map { .volumeMounted(uuid: $0.uuid, name: $0.name) }
        case .usb:
            return usbDevices.first.map {
                .usbDevice(vendor: $0.fact.vendor, product: $0.fact.product, serialHash: $0.fact.serialHash, name: $0.name)
            }
        case .router:
            return currentRouterHash.map { .network(.router(hash: $0, label: L("This network"))) }
        default:
            return nil
        }
    }

    /// Online displays with salted records, read now (the same facts DisplayPresence uses).
    static func readDisplays() -> [AwakeDisplayChoice] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(min(count, 64)))
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        let salt = DisplayIdentity.salt()
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            names[CGDirectDisplayID(n.uint32Value)] = screen.localizedName
        }
        return ids.prefix(Int(count)).map { (id: CGDirectDisplayID) -> AwakeDisplayChoice in
            let builtin = CGDisplayIsBuiltin(id) != 0
            var uuid: String?
            if let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                uuid = CFUUIDCreateString(kCFAllocatorDefault, cf) as String?
            }
            let facts = DisplayIdentityFacts(uuid: uuid, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                             serial: CGDisplaySerialNumber(id), isBuiltin: builtin)
            let name = TextSanitizer.clean(names[id] ?? (builtin ? L("Built-in Display") : L("Display")), maxScalars: 64)
            return AwakeDisplayChoice(record: DisplayIdentity.record(for: facts, salt: salt), name: name, isBuiltin: builtin)
        }
    }
}

// MARK: - One condition row

/// `.focused(_:)` only when a binding is given.
private struct OptionalFocus: ViewModifier {
    let focus: FocusState<Bool>.Binding?

    @ViewBuilder func body(content: Content) -> some View {
        if let focus {
            content.focused(focus)
        } else {
            content
        }
    }
}

struct CriterionEditors: View, ControlDeclaring {
    typealias Controls = TriggerEditorSheetControls

    let entry: Binding<AwakeCriterionEntry>
    @ObservedObject var sources: AwakePickerSources
    let remove: (@MainActor () -> Void)?
    let anchored: Bool
    /// The new rule's first row: its kind pop-up takes focus (§4.3).
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        let choice = AwakeCriterionChoice(entry.wrappedValue.criterion)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(L("Condition"), selection: kind) {
                    ForEach(AwakeCriterionChoice.allCases, id: \.self) { c in
                        Text(c.kind == .bluetooth && BluetoothPresence.isBeta ? c.title + L(" (Beta)") : c.title)
                            .tag(c)
                            .disabled(c != choice && c.defaultCriterion == nil && sources.firstCriterion(c) == nil)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help(L("What this condition looks at."))
                .modifier(OptionalFocus(focus: focus))
                .modifier(OptionalSettingsAnchor(anchored ? ControlID("awake.rule.condition.kind") : nil))
                if choice.allowsNegation {
                    Picker(L("Is or is not"), selection: entry.negated) {
                        Text(L("is")).tag(false)
                        Text(L("is not")).tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .modifier(OptionalSettingsAnchor(anchored ? ControlID("awake.rule.condition.negated") : nil))
                }
                CriterionValueEditor(criterion: criterion, sources: sources)
                    .modifier(OptionalSettingsAnchor(anchored ? ControlID("awake.rule.condition.value") : nil))
                Spacer(minLength: 4)
                if let remove {
                    Button {
                        remove()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Remove this condition"))
                    .accessibilityLabel(L("Remove this condition"))
                    .modifier(OptionalSettingsAnchor(anchored ? ControlID("awake.rule.condition.remove") : nil))
                }
            }
            CriterionDetailEditor(criterion: criterion)
            Text(Self.sentence(TriggerEngine.phrase(entry.wrappedValue, text: AwakeFormat.text)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// "An external display is connected."
    private static func sentence(_ phrase: String) -> String {
        guard let first = phrase.first else { return phrase }
        return String(first).uppercased() + phrase.dropFirst() + "."
    }

    private var criterion: Binding<AwakeCriterion> {
        Binding(get: { entry.wrappedValue.criterion }, set: { c in
            if entry.wrappedValue.criterion != c { entry.wrappedValue.criterion = c }
        })
    }

    private var kind: Binding<AwakeCriterionChoice> {
        let sources = self.sources
        return Binding(get: { AwakeCriterionChoice(entry.wrappedValue.criterion) }, set: { choice in
            guard choice != AwakeCriterionChoice(entry.wrappedValue.criterion),
                  let first = sources.firstCriterion(choice) else { return }
            var e = entry.wrappedValue
            e.criterion = first
            if !choice.allowsNegation { e.negated = false }
            entry.wrappedValue = e
        })
    }
}

// MARK: - Values on the row

/// The value right after is / is not: an app, a display, a power state, a drive, a USB device, a number…
private struct CriterionValueEditor: View {
    let criterion: Binding<AwakeCriterion>
    @ObservedObject var sources: AwakePickerSources

    var body: some View {
        switch criterion.wrappedValue {
        case .app(let bundleID, let name, let frontmost):
            appPicker(bundleID: bundleID, name: name, frontmost: frontmost)
        case .display(let match):
            displayPicker(match)
        case .power(let condition):
            powerEditor(condition)
        case .schedule:
            Text(L("between")).foregroundStyle(.secondary)
        case .cpuAbove(let p):
            Text(L("above")).foregroundStyle(.secondary)
            number(Double(p), range: AwakeCriterion.cpuRange, step: 5, format: .percent(of: 100), title: L("CPU use")) {
                .cpuAbove(percent: $0)
            }
        case .audio(let condition):
            Picker(L("Audio"), selection: Binding(get: { condition }, set: { criterion.wrappedValue = .audio($0) })) {
                Text(L("playing")).tag(AudioCondition.outputActive)
                Text(L("using the microphone")).tag(AudioCondition.microphoneActive)
            }
            .labelsHidden()
            .fixedSize()
        case .idle(let m):
            Text(L("at least")).foregroundStyle(.secondary)
            number(Double(m), range: AwakeCriterion.idleRange, step: 5, format: .minutes, title: L("Idle time")) {
                .idle(atLeastMinutes: $0)
            }
        case .volumeMounted(let uuid, let name):
            volumePicker(uuid: uuid, name: name)
        case .usbDevice(let vendor, let product, let serialHash, let name):
            usbPicker(vendor: vendor, product: product, serialHash: serialHash, name: name)
        case .network(let condition):
            networkEditor(condition)
        case .networkActivity(let k):
            Text(L("at least")).foregroundStyle(.secondary)
            number(Double(k), range: AwakeCriterion.networkActivityRange, step: 10, format: .plain(digits: 0),
                   title: L("Network activity in KB/s")) { .networkActivity(atLeastKBps: $0) }
            Text(L("KB/s")).foregroundStyle(.secondary)
        case .bluetooth(let match):
            bluetoothPicker(match)
        }
    }

    /// Any Bluetooth audio device, or one of the connected devices (a saved one that isn't connected stays listed).
    @ViewBuilder private func bluetoothPicker(_ match: BluetoothMatch) -> some View {
        let devices = sources.bluetoothDevices
        let current: Int = match == .anyAudio ? -1 : (devices.firstIndex { $0.match == match } ?? -2)
        Picker(L("Bluetooth device"), selection: Binding(get: { current }, set: { tag in
            if tag == -1 {
                criterion.wrappedValue = .bluetooth(.anyAudio)
            } else if devices.indices.contains(tag) {
                criterion.wrappedValue = .bluetooth(devices[tag].match)
            }
        })) {
            Text(L("any audio device")).tag(-1)
            if current == -2 {
                Text(L("a saved device (not connected)")).tag(-2)
            }
            if !devices.isEmpty { Divider() }
            ForEach(Array(devices.enumerated()), id: \.offset) { i, d in
                Text("“" + d.name + "”").tag(i)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
        Text(L("connected")).foregroundStyle(.secondary)
    }

    private func number(_ value: Double, range: ClosedRange<Int>, step: Double, format: ValueFormat, title: String,
                        make: @escaping (Int) -> AwakeCriterion) -> some View {
        let binding = criterion
        return NumberField(title, value: Binding(get: { value }, set: { v in
            guard v.isFinite else { return }
            binding.wrappedValue = make(AwakeMath.clamp(Int(v.rounded()), range))
        }), in: Double(range.lowerBound)...Double(range.upperBound), step: step, format: format)
    }

    // MARK: App

    @ViewBuilder private func appPicker(bundleID: String, name: String, frontmost: Bool) -> some View {
        let apps = sources.apps
        let listed = apps.contains { $0.bundleID == bundleID }
        Picker(L("App"), selection: Binding(get: { bundleID }, set: { id in
            let n = apps.first { $0.bundleID == id }?.name ?? name
            criterion.wrappedValue = .app(bundleID: id, name: n, frontmost: frontmost)
        })) {
            if !listed {
                Text(name.isEmpty ? bundleID : name).tag(bundleID)
            }
            ForEach(apps, id: \.bundleID) { app in
                Text(app.name).tag(app.bundleID)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 180)
        Picker(L("Open or in front"), selection: Binding(get: { frontmost }, set: { f in
            criterion.wrappedValue = .app(bundleID: bundleID, name: name, frontmost: f)
        })) {
            Text(L("open")).tag(false)
            Text(L("in front")).tag(true)
        }
        .labelsHidden()
        .fixedSize()
    }

    // MARK: Display

    /// -1 any external, -2 mirroring, -3 the saved display (not connected), ≥ 0 a connected display.
    @ViewBuilder private func displayPicker(_ match: DisplayMatch) -> some View {
        let displays = sources.displays
        let current: Int = {
            switch match {
            case .anyExternal: return -1
            case .mirroring: return -2
            case .specific(let record, _): return displays.firstIndex { $0.record == record } ?? -3
            }
        }()
        Picker(L("Display"), selection: Binding(get: { current }, set: { tag in
            switch tag {
            case -1: criterion.wrappedValue = .display(.anyExternal)
            case -2: criterion.wrappedValue = .display(.mirroring)
            case let i where displays.indices.contains(i):
                criterion.wrappedValue = .display(.specific(record: displays[i].record, name: displays[i].name))
            default: break
            }
        })) {
            Text(L("any external display")).tag(-1)
            Text(L("mirroring")).tag(-2)
            if current == -3, case .specific(_, let name) = match {
                Text(L("“\(name)” (not connected)")).tag(-3)
            }
            if !displays.isEmpty { Divider() }
            ForEach(Array(displays.enumerated()), id: \.offset) { i, d in
                Text("“" + d.name + "”").tag(i)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
        Text(L("connected")).foregroundStyle(.secondary)
    }

    // MARK: Power

    @ViewBuilder private func powerEditor(_ condition: PowerCondition) -> some View {
        let tag: Int = {
            switch condition {
            case .onAdapter: return 0
            case .onBattery: return 1
            case .charging: return 2
            case .batteryAtLeast: return 3
            }
        }()
        Picker(L("Power"), selection: Binding(get: { tag }, set: { t in
            switch t {
            case 0: criterion.wrappedValue = .power(.onAdapter)
            case 1: criterion.wrappedValue = .power(.onBattery)
            case 2: criterion.wrappedValue = .power(.charging)
            default: criterion.wrappedValue = .power(.batteryAtLeast(50))
            }
        })) {
            Text(L("on the power adapter")).tag(0)
            Text(L("on battery")).tag(1)
            Text(L("charging")).tag(2)
            Text(L("battery at least")).tag(3)
        }
        .labelsHidden()
        .fixedSize()
        if case .batteryAtLeast(let p) = condition {
            number(Double(p), range: AwakeCriterion.batteryRange, step: 5, format: .percent(of: 100),
                   title: L("Battery level")) { .power(.batteryAtLeast($0)) }
        }
    }

    // MARK: Drives and USB

    @ViewBuilder private func volumePicker(uuid: String, name: String) -> some View {
        let volumes = sources.volumes
        Picker(L("Drive"), selection: Binding(get: { uuid }, set: { id in
            let n = volumes.first { $0.uuid == id }?.name ?? name
            criterion.wrappedValue = .volumeMounted(uuid: id, name: n)
        })) {
            if !volumes.contains(where: { $0.uuid == uuid }) {
                Text(L("“\(name)” (not mounted)")).tag(uuid)
            }
            ForEach(volumes, id: \.uuid) { v in
                Text("“" + v.name + "”").tag(v.uuid)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
        Text(L("mounted")).foregroundStyle(.secondary)
    }

    @ViewBuilder private func usbPicker(vendor: Int, product: Int, serialHash: String?, name: String) -> some View {
        let devices = sources.usbDevices
        let currentIndex = devices.firstIndex {
            $0.fact.vendor == vendor && $0.fact.product == product && $0.fact.serialHash == serialHash
        } ?? -1
        Picker(L("USB device"), selection: Binding(get: { currentIndex }, set: { i in
            guard devices.indices.contains(i) else { return }
            let d = devices[i]
            criterion.wrappedValue = .usbDevice(vendor: d.fact.vendor, product: d.fact.product,
                                                serialHash: d.fact.serialHash, name: d.name)
        })) {
            if currentIndex < 0 {
                Text(L("“\(name)” (not connected)")).tag(-1)
            }
            ForEach(Array(devices.enumerated()), id: \.offset) { i, d in
                Text("“" + d.name + "”").tag(i)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
        Text(L("connected")).foregroundStyle(.secondary)
    }

    // MARK: Network

    @ViewBuilder private func networkEditor(_ condition: NetworkCondition) -> some View {
        switch condition {
        case .subnet(let cidr):
            Text(L("in")).foregroundStyle(.secondary)
            TextField(L("Subnet"), text: Binding(get: { cidr }, set: { text in
                let trimmed = String(text.trimmingCharacters(in: .whitespaces).prefix(49))
                criterion.wrappedValue = .network(.subnet(cidr: trimmed))
            }), prompt: Text("192.168.1.0/24"))
            .labelsHidden()
            .frame(width: 160)
        case .router(let hash, let label):
            TextField(L("Network name"), text: Binding(get: { label }, set: { text in
                criterion.wrappedValue = .network(.router(hash: hash, label: String(text.prefix(AwakeCriterion.maxNameScalars))))
            }), prompt: Text(L("Name, for example Home")))
            .labelsHidden()
            .frame(width: 160)
            if let current = sources.currentRouterHash, current != hash {
                Button(L("Use Current Network")) {
                    criterion.wrappedValue = .network(.router(hash: current, label: label))
                }
            }
        case .vpnConnected:
            Text(L("connected")).foregroundStyle(.secondary)
        }
    }
}

// MARK: - A second line for conditions with more fields

/// Schedules: the days and the time range; subnets: whether the address looks right.
private struct CriterionDetailEditor: View {
    let criterion: Binding<AwakeCriterion>

    var body: some View {
        switch criterion.wrappedValue {
        case .schedule(let days, let start, let end):
            HStack(spacing: 8) {
                DaysEditor(days: days) { criterion.wrappedValue = .schedule(days: $0, startMinute: start, endMinute: end) }
                Spacer(minLength: 8)
                DatePicker(L("From"), selection: minuteBinding(start) { m in
                    criterion.wrappedValue = .schedule(days: days, startMinute: m, endMinute: end)
                }, displayedComponents: .hourAndMinute)
                .labelsHidden()
                Text(L("to")).foregroundStyle(.secondary)
                DatePicker(L("To"), selection: minuteBinding(end) { m in
                    criterion.wrappedValue = .schedule(days: days, startMinute: start, endMinute: m)
                }, displayedComponents: .hourAndMinute)
                .labelsHidden()
            }
            if end <= start {
                Text(end == start ? L("Lasts 24 hours from the start time.") : L("Ends the next day."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .network(.subnet(let cidr)) where !AwakeCriterion.looksLikeCIDR(cidr):
            SettingsRowNote(L("Enter an address and prefix, for example 192.168.1.0/24 or fd00::/8."))
        case .bluetooth:
            HStack(spacing: 6) {
                SettingsBadgeView(.beta)
                Text(BluetoothPresence.scopeNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .network(.router(let hash, _)) where !Fingerprint.isHexDigest(hash):
            SettingsRowNote(L("Connect to the network, then choose Use Current Network."))
        default:
            EmptyView()
        }
    }

    /// A time of day as a Date today, written back as minutes since midnight.
    private func minuteBinding(_ minute: Int, _ apply: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(get: {
            var c = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: Date())
            c.hour = AwakeMath.clamp(minute, 0...1_439) / 60
            c.minute = AwakeMath.clamp(minute, 0...1_439) % 60
            return Calendar.autoupdatingCurrent.date(from: c) ?? Date()
        }, set: { date in
            let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
            apply((c.hour ?? 0) * 60 + (c.minute ?? 0))
        })
    }
}

/// Seven day toggles in the calendar's order (Sunday or Monday first); at least one stays on.
private struct DaysEditor: View {
    let days: WeekdaySet
    let apply: (WeekdaySet) -> Void

    var body: some View {
        let symbols = Calendar.autoupdatingCurrent.veryShortWeekdaySymbols
        let full = Calendar.autoupdatingCurrent.weekdaySymbols
        let first = Calendar.autoupdatingCurrent.firstWeekday - 1
        HStack(spacing: 2) {
            ForEach(Array(0..<7), id: \.self) { (offset: Int) in
                let day = (first + offset) % 7
                let on = days.contains(day: day)
                Toggle(isOn: Binding(get: { on }, set: { new in
                    var d = days
                    if new { d.insert(.day(day)) } else { d.remove(.day(day)) }
                    if !d.isEmpty { apply(d) }
                })) {
                    Text(symbols.indices.contains(day) ? symbols[day] : "")
                        .frame(minWidth: 14)
                }
                .toggleStyle(.button)
                .accessibilityLabel(full.indices.contains(day) ? full[day] : "")
            }
        }
    }
}

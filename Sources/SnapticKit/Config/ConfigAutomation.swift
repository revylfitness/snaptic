import Foundation

/// Display events that can run a hook (PLAN §11).
package enum HookEvent: String, Codable, CaseIterable, Sendable {
    /// The display appeared (plugged in, woke up as a new connection).
    case connect
    /// The display went away.
    case disconnect
    /// Snaptic (or another app) turned the display back on without replugging.
    case softConnect
    /// The display was turned off without unplugging it.
    case softDisconnect
    case sleep
    case wake
    /// Wake, then the hook's delay.
    case wakeDelayed

    /// The editor's "When" choice, sentence case (0.3 §4.2 copy rules).
    package var title: String {
        switch self {
        case .connect: return L("A display connects")
        case .disconnect: return L("A display disconnects")
        case .softConnect: return L("A display turns on")
        case .softDisconnect: return L("A display turns off")
        case .sleep: return L("Your Mac goes to sleep")
        case .wake: return L("Your Mac wakes")
        case .wakeDelayed: return L("Your Mac wakes, after a delay")
        }
    }

    /// One line under the "When" choice where the title alone is ambiguous; nil otherwise.
    package var help: String? {
        switch self {
        case .softConnect: return L("A display that stayed plugged in is turned back on, by Snaptic or another app.")
        case .softDisconnect: return L("A display is turned off without being unplugged.")
        case .wakeDelayed: return L("Waits after waking, so displays and drives have time to come back.")
        case .connect, .disconnect, .sleep, .wake: return nil
        }
    }

    /// The verb after a display's name in a hook's summary ("“DELL U2720Q” connects").
    fileprivate var displayVerb: String {
        switch self {
        case .connect: return L("connects")
        case .disconnect: return L("disconnects")
        case .softConnect: return L("turns on")
        case .softDisconnect: return L("turns off")
        case .sleep, .wake, .wakeDelayed: return ""
        }
    }

    /// Sleep and wake are Mac-wide; the others belong to one display.
    package var isPerDisplay: Bool {
        switch self {
        case .connect, .disconnect, .softConnect, .softDisconnect: return true
        case .sleep, .wake, .wakeDelayed: return false
        }
    }
}

/// An executable with a fixed argument list (no shell, no placeholders).
package struct CommandSpec: Codable, Equatable, Sendable {
    package var executable: String
    package var arguments: [String]

    package init(executable: String = "", arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }

    private enum CodingKeys: String, CodingKey { case executable, arguments }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        executable = c.lossy(.executable, "")
        arguments = c.lossy(.arguments, [])
    }

    /// The program's file name ("dock.sh"), or "" when no program is set.
    package var programName: String {
        let trimmed = executable.hasSuffix("/") ? String(executable.dropLast()) : executable
        guard let slash = trimmed.lastIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: slash)...])
    }

    package func sanitized() -> CommandSpec {
        CommandSpec(executable: executable.utf8.count <= KitHookPolicy.maxPathBytes ? executable : "",
                    arguments: Array(arguments.prefix(KitHookPolicy.maxArguments)).map {
                        TextSanitizer.clean($0, maxScalars: KitHookPolicy.maxArgumentScalars)
                    })
    }
}

/// "When display X connects, run Y" (PLAN §11).
package struct HookSpec: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var name: String
    package var enabled: Bool
    package var event: HookEvent
    /// Per-display events: nil = any display.
    package var display: DisplayKey?
    /// `wakeDelayed` only: seconds after wake (1–600).
    package var delaySeconds: Double
    package var command: CommandSpec

    package init(id: StableID = StableID(), name: String = "", enabled: Bool = true, event: HookEvent = .connect,
                 display: DisplayKey? = nil, delaySeconds: Double = 10, command: CommandSpec = CommandSpec()) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.event = event
        self.display = display
        self.delaySeconds = delaySeconds
        self.command = command
    }

    private enum CodingKeys: String, CodingKey { case id, name, enabled, event, display, delaySeconds, command }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(StableID.self, forKey: .id)   // an entry without an id is dropped
        name = c.lossy(.name, "")
        enabled = c.lossy(.enabled, false)
        event = try c.decode(HookEvent.self, forKey: .event)   // unknown events are dropped, not guessed
        display = c.lossy(.display, nil)
        delaySeconds = c.lossy(.delaySeconds, 10)
        command = c.lossy(.command, CommandSpec())
    }

    /// What the hook waits for, as a sentence: "When “DELL U2720Q” connects", "When a display disconnects", "When your
    /// Mac wakes, after 1 min 30 s". `displayName` names `display` (nil, or no display set: "a display"). Shown as the
    /// list row's subtitle and as the name field's placeholder.
    package func summary(displayName: String?) -> String {
        switch event {
        case .connect, .disconnect, .softConnect, .softDisconnect:
            let name = display == nil ? nil : displayName.map { TextSanitizer.clean($0, maxScalars: 64) }
            if let name, !name.isEmpty {
                return L("When “\(name)” \(event.displayVerb)")
            }
            return L("When a display \(event.displayVerb)")
        case .sleep:
            return L("When your Mac goes to sleep")
        case .wake:
            return L("When your Mac wakes")
        case .wakeDelayed:
            return L("When your Mac wakes, after \(Self.durationText(sanitized().delaySeconds))")
        }
    }

    /// "10 s", "1 min", "1 min 30 s" (whole seconds; the editor clamps to 1…600).
    package static func durationText(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded())) : 0
        let minutes = total / 60, rest = total % 60
        if minutes == 0 { return L("\(rest) s") }
        if rest == 0 { return L("\(minutes) min") }
        return L("\(minutes) min \(rest) s")
    }

    /// A hook without a program never runs (a new hook is on before its program is chosen).
    package var hasProgram: Bool { !command.executable.isEmpty }

    package func sanitized() -> HookSpec {
        var h = self
        h.name = TextSanitizer.clean(name, maxScalars: 64)
        h.delaySeconds = delaySeconds.isFinite ? min(600, max(1, delaySeconds)) : 10
        if !event.isPerDisplay { h.display = nil }
        h.command = command.sanitized()
        return h
    }
}

/// A named command shown in the menu, as a shortcut and (if allowed) to the CLI.
package struct CustomActionSpec: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var name: String
    package var command: CommandSpec
    /// `snaptic action run <name>` may run it. Off by default.
    package var cliAllowed: Bool
    package var showInMenu: Bool
    package var shortcut: HotkeyCombo?

    package init(id: StableID = StableID(), name: String = "", command: CommandSpec = CommandSpec(),
                 cliAllowed: Bool = false, showInMenu: Bool = true, shortcut: HotkeyCombo? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.cliAllowed = cliAllowed
        self.showInMenu = showInMenu
        self.shortcut = shortcut
    }

    private enum CodingKeys: String, CodingKey { case id, name, command, cliAllowed, showInMenu, shortcut }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(StableID.self, forKey: .id)
        name = c.lossy(.name, "")
        command = c.lossy(.command, CommandSpec())
        cliAllowed = c.lossy(.cliAllowed, false)
        showInMenu = c.lossy(.showInMenu, true)
        shortcut = c.lossy(.shortcut, nil)
    }

    package func sanitized() -> CustomActionSpec {
        var a = self
        a.name = TextSanitizer.clean(name, maxScalars: 64)
        a.command = command.sanitized()
        if let combo = shortcut {
            let normalized = HotkeyRules.normalized(combo)
            a.shortcut = HotkeyRules.problem(normalized) == nil ? normalized : nil
        }
        return a
    }

    /// The CLI name: lowercased, spaces to dashes ("Dim Office" → "dim-office").
    package var cliName: String {
        let lowered = name.lowercased().map { $0 == " " ? "-" : $0 }
        return String(lowered.filter { $0.isLetter || $0.isNumber || $0 == "-" })
    }
}

/// Hooks and custom actions (PLAN §11), in `DisplaysConfig.automation`. Protected: never
/// changed by the CLI, never exported, a toast when changed outside Snaptic.
package struct AutomationConfig: ConfigModel {
    package var hooks: [HookSpec]
    package var actions: [CustomActionSpec]

    package static let maxHooks = 16
    package static let maxActions = 16

    package init() {
        hooks = []
        actions = []
    }

    private enum CodingKeys: String, CodingKey { case hooks, actions }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hooks = c.lossy(.hooks, LossyArray<HookSpec>()).items
        actions = c.lossy(.actions, LossyArray<CustomActionSpec>()).items
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hooks, forKey: .hooks)
        try c.encode(actions, forKey: .actions)
    }

    package func sanitized() -> AutomationConfig {
        var c = self
        var seen = Set<StableID>()
        c.hooks = Array(hooks.filter { seen.insert($0.id).inserted }.prefix(Self.maxHooks)).map { $0.sanitized() }
        c.actions = Array(actions.filter { seen.insert($0.id).inserted }.prefix(Self.maxActions)).map { $0.sanitized() }
        return c
    }

    package func hooks(for event: HookEvent, display: DisplayKey?) -> [HookSpec] {
        hooks.filter { hook in
            hook.enabled && hook.hasProgram && hook.event == event && (hook.display == nil || hook.display == display)
        }
    }

    /// The action a CLI name refers to (exact `cliName` match).
    package func action(cliName: String) -> CustomActionSpec? {
        let wanted = cliName.lowercased()
        return actions.first { $0.cliName == wanted }
    }
}

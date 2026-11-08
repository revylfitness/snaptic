import Foundation

// `snaptic icons …` (lead; PLAN 0.4 §4.14, X-21). A closed grammar: four verbs, two flags, no free-form string. The
// status line and JSON carry an engine, a state and counts, never an app's name or bundle id (§4.15). Never traps
// (seeded fuzz). Exit codes are the house `ControlExit` ones (PLAN §R3).

package enum IconsCLICommand: Equatable, Sendable {
    /// `all`: include Always Hidden (the ⌥ expand).
    case show(all: Bool)
    case hide
    case toggle(all: Bool)
    case status(json: Bool)

    /// The visibility command it submits (from `.cli`); nil for `status`.
    package var command: IconsCommand? {
        switch self {
        case .show(let all): return all ? .showAll : .show
        case .hide: return .hide
        case .toggle(let all): return all ? .toggleAll : .toggle
        case .status: return nil
        }
    }
}

/// `engine=` of `icons status`.
package enum IconsCLIEngine: String, CaseIterable, Sendable {
    case native, length, unavailable
}

/// `state=` of `icons status`.
package enum IconsCLIState: String, CaseIterable, Sendable {
    case collapsed, expanded, needsPermission, paused, unavailable
}

package struct IconsStatusFacts: Equatable, Sendable {
    package var engine: IconsCLIEngine
    package var state: IconsCLIState
    package var hidden: Int
    package var alwaysHidden: Int
    package var shown: Int
    /// Seconds since the layout was read; nil when there is none.
    package var layoutAgeSeconds: Double?

    package init(engine: IconsCLIEngine, state: IconsCLIState, hidden: Int = 0, alwaysHidden: Int = 0, shown: Int = 0,
                 layoutAgeSeconds: Double? = nil) {
        self.engine = engine
        self.state = state
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
        self.shown = shown
        self.layoutAgeSeconds = layoutAgeSeconds
    }
}

/// Why `show`, `hide` or `toggle` did nothing: one line, exit `ControlExit.unavailable`.
package enum IconsCLIRefusal: String, CaseIterable, Sendable {
    case paused, needsPermission, unavailable, arrangement

    package var message: String {
        switch self {
        case .paused: return L("Hidden Icons is paused while another menu bar app hides icons.")
        case .needsPermission:
            return L("Hidden Icons needs Device Control and Data Access. Open Snaptic Settings › Permissions.")
        case .unavailable: return L("Hidden Icons isn’t available on this version of macOS.")
        case .arrangement: return L("Drag the | divider to the left of the arrow (hold ⌘).")
        }
    }

    package var exitCode: Int32 { ControlExit.unavailable }

    /// A state that refuses every change; nil while collapsed or expanded.
    package init?(state: IconsCLIState) {
        switch state {
        case .collapsed, .expanded: return nil
        case .needsPermission: self = .needsPermission
        case .paused: self = .paused
        case .unavailable: self = .unavailable
        }
    }

    /// The engine's refusal of a collapse, when the CLI has a line for it; nil: the app answers with the status row.
    package init?(_ refusal: IconsRefusal) {
        switch refusal {
        case .arrangement: self = .arrangement
        case .needsPermission: self = .needsPermission
        default: return nil
        }
    }
}

package enum IconsCommandGrammar {
    /// The verbs after "icons", in help order, with their help lines (§4.14).
    package static let verbs: [(verb: String, summary: String)] = [
        ("show", L("Show hidden icons (--all includes Always Hidden)")),
        ("hide", L("Hide icons again")),
        ("toggle", L("Show or hide icons")),
        ("status", L("Engine, state and icon counts (never names)")),
    ]

    /// The longest layout age reported, in seconds (a week); older reads report this.
    package static let maxLayoutAgeSeconds = 7 * 86_400

    /// verb is the word after "icons"; flags "--all" (show, toggle) and "--json" (status), each at most once.
    /// nil = usage error (exit `ControlExit.usage`).
    package static func parse(verb: String, args: [String]) -> IconsCLICommand? {
        guard args.count <= 2, args.allSatisfy({ $0.utf8.count <= 16 }) else { return nil }
        switch verb {
        case "show", "toggle":
            guard args.isEmpty || args == ["--all"] else { return nil }
            let all = !args.isEmpty
            return verb == "show" ? .show(all: all) : .toggle(all: all)
        case "hide":
            return args.isEmpty ? .hide : nil
        case "status":
            if args.isEmpty { return .status(json: false) }
            return args == ["--json"] ? .status(json: true) : nil
        default:
            return nil
        }
    }

    /// `engine=<…> state=<…> hidden=<n> alwaysHidden=<n> shown=<n>`.
    package static func statusLine(_ s: IconsStatusFacts) -> String {
        "engine=\(s.engine.rawValue) state=\(s.state.rawValue) hidden=\(count(s.hidden)) "
            + "alwaysHidden=\(count(s.alwaysHidden)) shown=\(count(s.shown))"
    }

    /// One JSON object with a fixed key order: engine, state, hidden, alwaysHidden, shown, layoutAgeSeconds (null
    /// without a layout).
    package static func statusJSON(_ s: IconsStatusFacts) -> String {
        var parts: [String] = []
        parts.append("\"engine\":\"" + s.engine.rawValue + "\"")
        parts.append("\"state\":\"" + s.state.rawValue + "\"")
        parts.append("\"hidden\":" + String(count(s.hidden)))
        parts.append("\"alwaysHidden\":" + String(count(s.alwaysHidden)))
        parts.append("\"shown\":" + String(count(s.shown)))
        parts.append("\"layoutAgeSeconds\":" + (layoutAge(s.layoutAgeSeconds).map { String($0) } ?? "null"))
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// Whole seconds, 0...maxLayoutAgeSeconds; nil for no layout or a non-finite age.
    package static func layoutAge(_ seconds: Double?) -> Int? {
        guard let seconds, seconds.isFinite else { return nil }
        if seconds <= 0 { return 0 }
        if seconds >= Double(maxLayoutAgeSeconds) { return maxLayoutAgeSeconds }
        return Int(seconds)
    }

    private static func count(_ n: Int) -> Int { max(0, min(n, 9_999)) }
}

/// The app's side of `snaptic icons …` (A9): the status facts and the replies, so the handlers stay thin.
package enum IconsCLIRules {
    package static func engine(_ kind: IconsEngineKind?) -> IconsCLIEngine {
        switch kind {
        case .native: return .native
        case .length: return .length
        case nil: return .unavailable
        }
    }

    /// `state=`: unavailable first, then paused (another menu bar hider), then Native's missing permission, then the
    /// bar. A collapsed bar can report needsPermission or paused; showing its icons is still allowed.
    package static func state(engine: IconsEngineKind?, state: IconsEngineState, needsPermission: Bool,
                              paused: Bool) -> IconsCLIState {
        guard let engine else { return .unavailable }
        if case .unavailable = state { return .unavailable }
        if paused { return .paused }
        if engine == .native, needsPermission { return .needsPermission }
        return state.isCollapsed ? .collapsed : .expanded
    }

    /// Counts by section of the last read (Snaptic's own items left out); zero without one.
    package static func facts(engine: IconsEngineKind?, state: IconsEngineState, needsPermission: Bool, paused: Bool,
                              layout: IconsLayout?, ownBundleID: String, now: Double) -> IconsStatusFacts {
        var facts = IconsStatusFacts(engine: Self.engine(engine),
                                     state: Self.state(engine: engine, state: state, needsPermission: needsPermission,
                                                       paused: paused))
        guard let layout else { return facts }
        for (bundle, section) in layout.sections where bundle != ownBundleID {
            switch section {
            case .shown: facts.shown += 1
            case .hidden: facts.hidden += 1
            case .alwaysHidden: facts.alwaysHidden += 1
            }
        }
        if layout.readAt > 0 { facts.layoutAgeSeconds = max(now - layout.readAt, 0) }
        return facts
    }

    /// The refusal before `show`, `hide` or `toggle` runs. A collapsed bar never refuses: an expand always runs and
    /// `hide` changes nothing.
    package static func refusal(state: IconsCLIState, collapsed: Bool) -> IconsCLIRefusal? {
        collapsed ? nil : IconsCLIRefusal(state: state)
    }

    /// The failure line after a collapse finished; nil: success. `statusText` is the Settings status row, for a
    /// refusal the CLI has no line of its own for.
    package static func failure(after result: IconsCollapseResult,
                                statusText: String) -> (exit: Int32, message: String)? {
        switch result {
        case .collapsed, .superseded:
            return nil
        case .refused(let refusal):
            if let line = IconsCLIRefusal(refusal) { return (line.exitCode, line.message) }
            return (ControlExit.unavailable, statusText)
        case .failed:
            return (ControlExit.unavailable, statusText)
        case .unavailable:
            return (IconsCLIRefusal.unavailable.exitCode, IconsCLIRefusal.unavailable.message)
        }
    }
}

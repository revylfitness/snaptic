import SwiftUI
import SnapticKit

/// The row search just revealed (one at a time). A shared object rather than an environment value, so anchored
/// rows highlight in sheets and outside the shell too (PLAN 0.3 §4.1; written by `SettingsShell`).
@MainActor final class SettingsHighlight: ObservableObject {
    static let shared = SettingsHighlight()

    /// The highlighted anchor (a `ControlID.rawValue`), nil when none.
    @Published private(set) var anchor: String?
    /// Bumped on every request, so revealing the same row twice scrolls twice.
    @Published private(set) var token = 0
    /// Anchors on screen now (rows of a grouped form appear lazily, so a row scrolled to registers once it shows).
    /// Not published: nothing renders from it.
    private var visible: [String: Int] = [:]

    private init() {}

    func show(_ anchor: String?) {
        self.anchor = anchor
        token &+= 1
    }

    /// Whether a row with this anchor is on screen (in the window or one of its sheets).
    func isVisible(_ anchor: String) -> Bool { (visible[anchor] ?? 0) > 0 }

    fileprivate func appeared(_ anchor: String) { visible[anchor, default: 0] += 1 }

    fileprivate func disappeared(_ anchor: String) {
        guard let n = visible[anchor] else { return }
        visible[anchor] = n > 1 ? n - 1 : nil
    }
}

/// `.modifier(SettingsAnchor(ControlID("awake.page.batteryFloor")))`: the row's scroll id plus the search highlight
/// (accent tint for 1.2 s, faded in and out; static with Reduce Motion). A ViewModifier, not a `View` extension
/// (lint rule 10). Rows that take `anchor:` apply it themselves. The ControlID literal must be in the view's control
/// table (lint L15, §4.8).
struct SettingsAnchor: ViewModifier {
    let id: ControlID
    @ObservedObject private var highlight = SettingsHighlight.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ id: ControlID) { self.id = id }

    func body(content: Content) -> some View {
        let on = highlight.anchor == id.rawValue
        content
            .id(id.rawValue)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(on ? 0.2 : 0))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: on)
            .onAppear { highlight.appeared(id.rawValue) }
            .onDisappear { highlight.disappeared(id.rawValue) }
    }
}

/// `SettingsAnchor` when an id is given, nothing otherwise (rows with an optional `anchor:`).
struct OptionalSettingsAnchor: ViewModifier {
    let id: ControlID?

    init(_ id: ControlID?) { self.id = id }

    func body(content: Content) -> some View {
        if let id {
            content.modifier(SettingsAnchor(id))
        } else {
            content
        }
    }
}

/// Scrolls its scroll view (a grouped `Form`) to the highlighted anchor when it appears and on every new reveal.
/// Used by `SettingsPageScaffold` and `AdvancedSheet`.
struct SettingsAnchorScroller<Content: View>: View {
    @ObservedObject private var highlight = SettingsHighlight.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onAppear { scroll(proxy) }
                .onChange(of: highlight.token) { _, _ in scroll(proxy) }
        }
    }

    /// Scrolls now and once more a moment later: a row inside a disclosure that just expanded for it, or in a sheet
    /// still laying out, exists only after the first pass.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let anchor = highlight.anchor else { return }
        let animated = !reduceMotion
        Self.move(proxy, to: anchor, animated: animated)
        let token = highlight.token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [highlight] in
            MainActor.assumeIsolated {
                guard highlight.token == token, highlight.anchor == anchor else { return }
                Self.move(proxy, to: anchor, animated: animated)
            }
        }
    }

    private static func move(_ proxy: ScrollViewProxy, to anchor: String, animated: Bool) {
        if !animated {
            proxy.scrollTo(anchor, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(anchor, anchor: .center) }
        }
    }
}

/// Expands a disclosure when search reveals one of its rows: `DisclosureGroup(…, isExpanded: $open) { … }
/// .modifier(SettingsRevealExpansion([ControlID("displays.resolution.slider")], isExpanded: $open))`. The ids are
/// the anchors of the rows inside it (each literal in the view's control table, lint L15).
struct SettingsRevealExpansion: ViewModifier {
    let ids: Set<String>
    @Binding var isExpanded: Bool
    @ObservedObject private var highlight = SettingsHighlight.shared

    init(_ ids: [ControlID], isExpanded: Binding<Bool>) {
        self.ids = Set(ids.map(\.rawValue))
        _isExpanded = isExpanded
    }

    func body(content: Content) -> some View {
        content
            .onAppear(perform: expandIfRevealed)
            .onChange(of: highlight.token) { _, _ in expandIfRevealed() }
    }

    private func expandIfRevealed() {
        guard let anchor = highlight.anchor, ids.contains(anchor), !isExpanded else { return }
        isExpanded = true
    }
}

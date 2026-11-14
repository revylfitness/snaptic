import AppKit
import SwiftUI
import SnapticKit

/// One window card (§4.3): what the view draws for one window of the read, in card order.
struct DockPreviewCard: Identifiable, Equatable {
    let id: CGWindowID
    /// The card's text: the title, the app name, “Private window” or “Window on another Space” (§4.3, §4.10).
    let text: String
    /// One badge at most (§4.3): “Minimized”, “Full screen”, “On another Space” or the display's name.
    let badge: String?
    /// A card without an AX element offers only Bring Forward (§4.4, D2-25): no hover buttons and no named actions.
    let hasAXElement: Bool
    /// The yellow hover button restores a minimized window; the green one exits full screen (§4.4).
    let minimized: Bool
    let fullScreen: Bool
    /// The VoiceOver label, which is also the card's tooltip (§4.16).
    let label: String
}

/// What the panel shows. The controller owns it; the view only reads it.
@MainActor
final class DockPreviewModel: ObservableObject {
    /// K2's grid for the cards; nil while the small card shows.
    @Published var layout: DockPanelLayout?
    @Published var cards: [DockPreviewCard] = []
    @Published var small: DockSmallCard?
    @Published var icon: NSImage?
    @Published var appName = ""
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    /// “More windows…” was clicked and the longer read is running.
    @Published var readingMore = false
    /// The app is hidden: the header's Hide button reads Show (§4.4, G2-1).
    @Published var appHidden = false
    /// Finder has no Quit (§4.4).
    @Published var isFinder = false
    /// Keys work (§4.5), so the tooltips name them.
    @Published var keysWork = false

    func reset() {
        layout = nil
        cards = []
        small = nil
        icon = nil
        appName = ""
        thumbnails = [:]
        readingMore = false
        appHidden = false
        isFinder = false
        keysWork = false
    }
}

/// What the panel's clicks, menus, hovers and VoiceOver focus do (§4.4, §4.16). Cards are named by window id.
struct DockPreviewActions {
    /// A card was clicked: left raises, middle closes (§4.4).
    var card: @MainActor (_ id: CGWindowID, _ button: DockMouseButton) -> Void
    /// “No open windows”, “No windows shown” or “Windows can’t be read right now” was clicked.
    var smallCard: @MainActor () -> Void
    var moreWindows: @MainActor () -> Void
    /// The scroll offset along the layout's scroll axis, as K2 measures it.
    var scrolled: @MainActor (_ offset: Double) -> Void
    /// A card's hover button, or the VoiceOver action of the same name.
    var hoverButton: @MainActor (_ id: CGWindowID, _ button: DockHoverButton) -> Void
    /// A header button.
    var header: @MainActor (_ button: DockHeaderButton) -> Void
    /// The card's and the header's right-click menus, built as they open; nil shows none.
    var cardMenu: @MainActor (_ id: CGWindowID) -> NSMenu?
    var headerMenu: @MainActor () -> NSMenu?
    /// The pointer entered or left a card (A5's keys act on the card under the pointer).
    var hovered: @MainActor (_ id: CGWindowID, _ inside: Bool) -> Void
    /// VoiceOver's focus entered or left the panel's elements (§4.16).
    var voiceOverFocus: @MainActor (_ inPanel: Bool) -> Void
}

/// The panel's SwiftUI content (§4.3): the header strip, then K2's card grid in a scroll view, or one small card.
/// Cards sit at K2's frames; K2 already mirrored them for right-to-left, so the grid itself is laid out
/// left-to-right and only the text follows the app's direction.
/// - §4.7: Increase Contrast adds 1 pt borders on the cards and around the panel, and a header separator. Reduce
///   Transparency makes the panel opaque in `windowBackgroundColor`. Nothing moves, so Reduce Motion has no branch.
/// - §4.16: the panel is a group labelled “Safari windows”. Each element's VoiceOver focus feeds the policy's
///   `voiceOverFocusInPanel` through `actions.voiceOverFocus`.
struct DockPreviewView: View {
    @ObservedObject var model: DockPreviewModel
    let actions: DockPreviewActions

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var focus: DockFocus?

    private static let metrics = DockPanelMetrics.standard
    private static let scrollSpace = "dockPreviewScroll"

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backdrop }
            .overlay { border }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(DockPreviewRules.panelLabel(app: model.appName))
            .accessibilityFocused($focus, equals: .panel)
            .onChange(of: focus != nil) { _, inPanel in actions.voiceOverFocus(inPanel) }
    }

    @ViewBuilder
    private var content: some View {
        if let small = model.small {
            smallCard(small)
        } else if let layout = model.layout {
            panel(layout)
        }
    }

    /// §4.7: Reduce Transparency puts an opaque `windowBackgroundColor` over the panel's material.
    @ViewBuilder
    private var backdrop: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: DockPreviewPanel.cornerRadius, style: .circular)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// §4.7: Increase Contrast draws a 1 pt border around the panel.
    @ViewBuilder
    private var border: some View {
        if contrast == .increased {
            RoundedRectangle(cornerRadius: DockPreviewPanel.cornerRadius, style: .circular)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    // MARK: Cards

    private func panel(_ layout: DockPanelLayout) -> some View {
        VStack(spacing: 0) {
            header
                .frame(width: layout.panel.width, height: layout.header.height)
                .overlay(alignment: .bottom) {
                    if contrast == .increased {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 1)
                    }
                }
            grid(layout)
                .frame(width: layout.viewport.width, height: layout.viewport.height)
                .padding(Self.metrics.padding)
        }
        .frame(width: layout.panel.width, height: layout.panel.height, alignment: .top)
    }

    /// The header strip (§4.4): icon, name and window count, then Minimize All, Hide (Show while the app is hidden)
    /// and Quit (none for Finder). Its right-click menu adds Close All. A click anywhere else on it does nothing (M23).
    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                if let icon = model.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                Text(model.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(DockPreviewRules.windowCount(model.cards.count))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($focus, equals: .headerTitle)
            Spacer(minLength: 0)
            headerButton(.minimizeAll, symbol: "minus.square")
            headerButton(DockPreviewRules.hideButton(appHidden: model.appHidden),
                         symbol: model.appHidden ? "eye" : "eye.slash")
            if !model.isFinder {
                headerButton(.quitApp, symbol: "power")
            }
        }
        .padding(.horizontal, Self.metrics.padding)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .overlay(DockMouseCatcher(menu: actions.headerMenu))
    }

    /// Tooltip “Hide Safari”, plus “(⌘H)” while keys work; the label is the bare words (§4.4).
    private func headerButton(_ button: DockHeaderButton, symbol: String) -> some View {
        Button {
            actions.header(button)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(DockPreviewRules.headerHelp(button, app: model.appName, keysWork: model.keysWork))
        .accessibilityLabel(DockPreviewRules.headerLabel(button, app: model.appName))
        .accessibilityFocused($focus, equals: .header(button))
    }

    @ViewBuilder
    private func grid(_ layout: DockPanelLayout) -> some View {
        switch layout.scrollAxis {
        case nil:
            cells(layout)
        case .horizontal?:
            ScrollView(.horizontal) {
                cells(layout).background(offsetReader(.horizontal))
            }
            .coordinateSpace(name: Self.scrollSpace)
            .defaultScrollAnchor(layout.rightToLeft ? .trailing : .leading)
            .onPreferenceChange(DockScrollOffsetKey.self, perform: reporter(layout))
            .accessibilityFocused($focus, equals: .scroll)
        case .vertical?:
            ScrollView(.vertical) {
                cells(layout).background(offsetReader(.vertical))
            }
            .coordinateSpace(name: Self.scrollSpace)
            .defaultScrollAnchor(.top)
            .onPreferenceChange(DockScrollOffsetKey.self, perform: reporter(layout))
            .accessibilityFocused($focus, equals: .scroll)
        }
    }

    /// Every cell at its K2 frame. K2's content coordinates have y up from the bottom; SwiftUI's go down from the top.
    private func cells(_ layout: DockPanelLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(layout.cells.enumerated()), id: \.offset) { index, cell in
                let frame = layout.frames[index]
                cellView(cell, size: CGSize(width: frame.width, height: frame.height), rtl: layout.rightToLeft)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: layout.content.height - frame.maxY)
            }
        }
        .frame(width: layout.content.width, height: layout.content.height, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
    }

    /// A card (§4.4, §4.16): click raises, middle-click closes, right-click opens the card menu. For VoiceOver it's
    /// one button whose label is its tooltip, with Close, Minimize and Full Screen as named actions in place of the
    /// hover buttons.
    @ViewBuilder
    private func cellView(_ cell: DockCell, size: CGSize, rtl: Bool) -> some View {
        switch cell {
        case .window(let index):
            if model.cards.indices.contains(index) {
                let card = model.cards[index]
                DockCardView(card: card, size: size, thumbnail: model.thumbnails[card.id], icon: model.icon,
                             keysWork: model.keysWork,
                             onHover: { id, inside in actions.hovered(id, inside) },
                             onButton: { button in actions.hoverButton(card.id, button) })
                    .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                    .contentShape(Rectangle())
                    .onTapGesture { actions.card(card.id, .left) }
                    .overlay(DockMouseCatcher(middleClick: { actions.card(card.id, .middle) },
                                              menu: { actions.cardMenu(card.id) }))
                    .help(card.label)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(card.label)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.card(card.id, .left) }
                    .accessibilityActions {
                        if card.hasAXElement {
                            Button(Self.hoverLabel(.close, card)) { actions.hoverButton(card.id, .close) }
                            Button(Self.hoverLabel(.minimize, card)) { actions.hoverButton(card.id, .minimize) }
                            Button(Self.hoverLabel(.fullScreen, card)) { actions.hoverButton(card.id, .fullScreen) }
                        }
                    }
                    .accessibilityFocused($focus, equals: .card(card.id))
            }
        case .moreWindows:
            DockMoreWindowsView(busy: model.readingMore)
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                .contentShape(Rectangle())
                .onTapGesture { actions.moreWindows() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(DockMoreWindowsView.title)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { actions.moreWindows() }
                .accessibilityFocused($focus, equals: .more)
        }
    }

    private static func hoverLabel(_ button: DockHoverButton, _ card: DockPreviewCard) -> String {
        DockPreviewRules.hoverLabel(button, minimized: card.minimized, fullScreen: card.fullScreen)
    }

    private func offsetReader(_ axis: DockScrollAxis) -> some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .named(Self.scrollSpace)).origin
            Color.clear.preference(key: DockScrollOffsetKey.self,
                                   value: Double(axis == .horizontal ? -origin.x : -origin.y))
        }
    }

    /// Reports SwiftUI's offset from the left (or top) end as K2's offset from the scroll axis's start (the right
    /// end in right-to-left). Preference changes arrive on the main thread.
    private func reporter(_ layout: DockPanelLayout) -> @Sendable (Double) -> Void {
        let scrolled = actions.scrolled
        let maxOffset = layout.maxScrollOffset
        let flipped = layout.scrollAxis == .horizontal && layout.rightToLeft
        return { offset in
            let fromStart = flipped ? maxOffset - offset : offset
            MainActor.assumeIsolated { scrolled(min(max(fromStart, 0), maxOffset)) }
        }
    }

    // MARK: Small card

    /// §4.16: VoiceOver reads “No windows shown, Safari”, with §4.3's tooltip as its help.
    private func smallCard(_ small: DockSmallCard) -> some View {
        let size = DockPreviewRules.smallCard
        let help = small == .noWindowsShown ? L("Its windows are minimized, hidden, or on other Spaces.") : ""
        return HStack(spacing: 10) {
            if let icon = model.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 40, height: 40)
            }
            Text(Self.text(small))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .help(help)
        .onTapGesture { actions.smallCard() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DockPreviewRules.smallCardLabel(small, app: model.appName))
        .accessibilityHint(help)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.smallCard() }
        .accessibilityFocused($focus, equals: .small)
        .padding(Self.metrics.padding)
    }

    static func text(_ small: DockSmallCard) -> String {
        switch small {
        case .noOpenWindows: return L("No open windows")
        case .noWindowsShown: return L("No windows shown")
        case .cantRead: return L("Windows can’t be read right now")
        }
    }
}

/// Where VoiceOver's focus is in the panel (§4.16). Every element the panel offers binds a value, so a nil focus
/// means VoiceOver is elsewhere.
private enum DockFocus: Hashable {
    case panel
    case headerTitle
    case header(DockHeaderButton)
    case card(CGWindowID)
    case small
    case more
    /// The scroll area itself: VoiceOver resting on it is still in the panel (M22).
    case scroll
}

/// One window card: the thumbnail letterboxed in the card's 16:10 frame (K2), or the app icon; the text along the
/// bottom and the badge at the top. While the pointer is over a card with an AX element, Close, Minimize and Full
/// Screen show top-left (§4.4). The hover buttons are hidden from VoiceOver, which offers them as named actions.
private struct DockCardView: View {
    let card: DockPreviewCard
    let size: CGSize
    let thumbnail: NSImage?
    let icon: NSImage?
    let keysWork: Bool
    let onHover: @MainActor (_ id: CGWindowID, _ inside: Bool) -> Void
    let onButton: @MainActor (DockHoverButton) -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.14 : 0.07))
            picture
            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    if let badge = card.badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: Capsule())
                            .padding(6)
                    }
                }
                Spacer(minLength: 0)
                Text(card.text)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial)
            }
        }
        .overlay(alignment: .topLeading) {
            if hovered, card.hasAXElement { hoverButtons }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
        .onHover { inside in
            hovered = inside
            onHover(card.id, inside)
        }
        // A refresh can put another window's card under the pointer at this cell; A5's keys follow it.
        .onChange(of: card.id) { old, new in
            guard hovered else { return }
            onHover(old, false)
            onHover(new, true)
        }
    }

    private var hoverButtons: some View {
        HStack(spacing: 6) {
            hoverButton(.close, color: .red, symbol: "xmark")
            hoverButton(.minimize, color: .yellow, symbol: card.minimized ? "arrow.up" : "minus")
            hoverButton(.fullScreen, color: .green,
                        symbol: card.fullScreen ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right")
        }
        .padding(6)
        .accessibilityHidden(true)
    }

    private func hoverButton(_ button: DockHoverButton, color: Color, symbol: String) -> some View {
        Button {
            onButton(button)
        } label: {
            ZStack {
                Circle().fill(color)
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.6))
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(DockPreviewRules.hoverHelp(button, minimized: card.minimized, fullScreen: card.fullScreen,
                                         keysWork: keysWork))
    }

    @ViewBuilder
    private var picture: some View {
        let cardRect = DockRect(x: 0, y: 0, width: size.width, height: size.height)
        if let thumbnail,
           let fit = DockGeometry.letterbox(image: DockSize(width: thumbnail.size.width, height: thumbnail.size.height),
                                            in: cardRect) {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .frame(width: fit.width, height: fit.height)
        } else if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 48, height: 48)
                .opacity(0.8)
        }
    }
}

/// “More windows…” (§4.8): always the last cell. A click reads the app again with the whole budget.
private struct DockMoreWindowsView: View {
    static let title = L("More windows…")

    let busy: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Text(Self.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A card's or the header's other clicks (§4.4): a middle click (the card's closes its window), and a right click or
/// Control-click (opens the menu). The view claims only those events, so every other click and hover goes through to
/// SwiftUI.
private struct DockMouseCatcher: NSViewRepresentable {
    var middleClick: (@MainActor () -> Void)?
    var menu: (@MainActor () -> NSMenu?)?

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.middleClick = middleClick
        view.menuProvider = menu
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.middleClick = middleClick
        view.menuProvider = menu
    }

    final class CatcherView: NSView {
        var middleClick: (@MainActor () -> Void)?
        var menuProvider: (@MainActor () -> NSMenu?)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
                return middleClick == nil ? nil : super.hitTest(point)
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return menuProvider == nil ? nil : super.hitTest(point)
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
                return menuProvider != nil && event.modifierFlags.contains(.control) ? super.hitTest(point) : nil
            default:
                return nil
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func otherMouseDown(with event: NSEvent) {
            guard event.buttonNumber != 2 else { return }
            super.otherMouseDown(with: event)
        }

        override func otherMouseUp(with event: NSEvent) {
            guard event.buttonNumber == 2, let middleClick else {
                super.otherMouseUp(with: event)
                return
            }
            middleClick()
        }

        override func rightMouseDown(with event: NSEvent) {
            showMenu(event)
        }

        override func mouseDown(with event: NSEvent) {
            guard event.modifierFlags.contains(.control) else {
                super.mouseDown(with: event)
                return
            }
            showMenu(event)
        }

        private func showMenu(_ event: NSEvent) {
            guard let menu = menuProvider?() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

private struct DockScrollOffsetKey: PreferenceKey {
    static let defaultValue: Double = 0

    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

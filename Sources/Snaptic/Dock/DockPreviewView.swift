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
    /// A card without an AX element offers only Bring Forward (§4.4); A4b's hover buttons read this.
    let hasAXElement: Bool
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

    func reset() {
        layout = nil
        cards = []
        small = nil
        icon = nil
        appName = ""
        thumbnails = [:]
        readingMore = false
    }
}

/// What the panel's clicks and scrolls do. A4b adds the hover buttons, the header's buttons and the menus here.
struct DockPreviewActions {
    /// A card was clicked (`index` into `DockPreviewModel.cards`).
    var card: @MainActor (_ index: Int, _ button: DockMouseButton) -> Void
    /// “No open windows”, “No windows shown” or “Windows can’t be read right now” was clicked.
    var smallCard: @MainActor () -> Void
    var moreWindows: @MainActor () -> Void
    /// The scroll offset along the layout's scroll axis, as K2 measures it.
    var scrolled: @MainActor (_ offset: Double) -> Void
}

/// The panel's SwiftUI content (§4.3): the header strip, then K2's card grid in a scroll view, or one small card.
/// Cards sit at K2's frames; K2 already mirrored them for right-to-left, so the grid itself is laid out
/// left-to-right and only the text follows the app's direction.
struct DockPreviewView: View {
    @ObservedObject var model: DockPreviewModel
    let actions: DockPreviewActions

    private static let metrics = DockPanelMetrics.standard
    private static let scrollSpace = "dockPreviewScroll"

    var body: some View {
        if let small = model.small {
            smallCard(small)
        } else if let layout = model.layout {
            panel(layout)
        }
    }

    // MARK: Cards

    private func panel(_ layout: DockPanelLayout) -> some View {
        VStack(spacing: 0) {
            header
                .frame(width: layout.panel.width, height: layout.header.height)
            grid(layout)
                .frame(width: layout.viewport.width, height: layout.viewport.height)
                .padding(Self.metrics.padding)
        }
        .frame(width: layout.panel.width, height: layout.panel.height, alignment: .top)
    }

    /// The header strip (§4.4). A4b adds its buttons and menus; until then it names the app.
    private var header: some View {
        HStack(spacing: 6) {
            if let icon = model.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(model.appName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.metrics.padding)
        .padding(.top, 8)
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
        case .vertical?:
            ScrollView(.vertical) {
                cells(layout).background(offsetReader(.vertical))
            }
            .coordinateSpace(name: Self.scrollSpace)
            .defaultScrollAnchor(.top)
            .onPreferenceChange(DockScrollOffsetKey.self, perform: reporter(layout))
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

    @ViewBuilder
    private func cellView(_ cell: DockCell, size: CGSize, rtl: Bool) -> some View {
        switch cell {
        case .window(let index):
            if model.cards.indices.contains(index) {
                let card = model.cards[index]
                DockCardView(card: card, size: size, thumbnail: model.thumbnails[card.id], icon: model.icon)
                    .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                    .contentShape(Rectangle())
                    .onTapGesture { actions.card(index, .left) }
                    .overlay(DockMiddleClickCatcher { actions.card(index, .middle) })
            }
        case .moreWindows:
            DockMoreWindowsView(busy: model.readingMore)
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                .contentShape(Rectangle())
                .onTapGesture { actions.moreWindows() }
        }
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

    private func smallCard(_ small: DockSmallCard) -> some View {
        let size = DockPreviewRules.smallCard
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
        .help(small == .noWindowsShown ? L("Its windows are minimized, hidden, or on other Spaces.") : "")
        .onTapGesture { actions.smallCard() }
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

/// One window card: the thumbnail letterboxed in the card's 16:10 frame (K2), or the app icon; the text along the
/// bottom and the badge at the top. A4b adds the hover buttons and the VoiceOver label.
private struct DockCardView: View {
    let card: DockPreviewCard
    let size: CGSize
    let thumbnail: NSImage?
    let icon: NSImage?

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
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovered = $0 }
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
    let busy: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Text(L("More windows…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A middle click on a card (§4.4: it closes the window). The view claims only middle-button events, so every other
/// click and hover goes through to SwiftUI.
private struct DockMiddleClickCatcher: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: (@MainActor () -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .otherMouseDown?, .otherMouseUp?, .otherMouseDragged?: return super.hitTest(point)
            default: return nil
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func otherMouseDown(with event: NSEvent) {
            guard event.buttonNumber != 2 else { return }
            super.otherMouseDown(with: event)
        }

        override func otherMouseUp(with event: NSEvent) {
            guard event.buttonNumber == 2 else {
                super.otherMouseUp(with: event)
                return
            }
            action?()
        }
    }
}

private struct DockScrollOffsetKey: PreferenceKey {
    static let defaultValue: Double = 0

    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

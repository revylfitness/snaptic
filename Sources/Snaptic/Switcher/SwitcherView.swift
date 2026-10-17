import AppKit
import SwiftUI
import SnapticKit

struct SwitcherActions {
    var select: (Int) -> Void
    var activate: (Int) -> Void
    var close: (CGWindowID) -> Void
    var minimize: (CGWindowID) -> Void
    var fullscreen: (CGWindowID) -> Void
}

@MainActor
struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let actions: SwitcherActions

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SearchHeader(
                query: model.query,
                hint: model.hint,
                searching: model.searching,
                shown: model.filtered.count,
                total: model.allItems.count
            )
            .frame(height: Metrics.headerHeight)

            if !model.loaded {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filtered.isEmpty {
                Text(model.allItems.isEmpty ? "No open windows" : "No windows match “\(model.query)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        content.frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.never)
                    .onAppear {
                        if let id = model.selected?.id { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: model.selectedIndex) {
                        if let id = model.selected?.id { proxy.scrollTo(id) }
                    }
                }
                // New identity every time the switcher opens: no leftover hover
                // highlights or scroll position from last time.
                .id(model.session)
            }
        }
        .padding(Metrics.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        if model.style == .titles {
            titleList
        } else {
            grid
        }
    }

    private var titleList: some View {
        VStack(spacing: Metrics.titleRowGap) {
            ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, item in
                TitleRow(
                    item: item,
                    index: index,
                    selected: index == model.selectedIndex,
                    hoverButtons: model.showHoverButtons,
                    actionsOn: model.enabledActions,
                    actions: actions
                )
                .frame(width: model.layout.rowWidths.first ?? Metrics.titleRowWidth, height: Metrics.titleRowHeight)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: Metrics.gap) {
            ForEach(Array(model.layout.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Metrics.gap) {
                    ForEach(row, id: \.windowID) { tile in
                        tileView(tile)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tileView(_ tile: Tile) -> some View {
        if tile.index < model.filtered.count {
            let item = model.filtered[tile.index]
            TileView(
                item: item,
                index: tile.index,
                size: tile.size,
                visualHeight: model.layout.thumbHeight,
                style: model.style,
                hoverButtons: model.showHoverButtons,
                actionsOn: model.enabledActions,
                image: model.thumbnails[item.id],
                selected: tile.index == model.selectedIndex,
                actions: actions
            )
        }
    }
}

struct SearchHeader: View {
    let query: String
    let hint: String
    let searching: Bool
    let shown: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            if !searching {
                Text(hint)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if query.isEmpty {
                Text("Type to search")
                    .foregroundStyle(.tertiary)
            } else {
                Text(query)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(countText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 13))
    }

    private var countText: String {
        if query.isEmpty { return total == 1 ? "1 window" : "\(total) windows" }
        return "\(shown) of \(total)"
    }
}

@MainActor
struct TileView: View {
    let item: WindowItem
    let index: Int
    let size: CGSize
    let visualHeight: CGFloat
    let style: SwitcherStyle
    let hoverButtons: Bool
    let actionsOn: Set<SwitcherFeature>
    let image: NSImage?
    let selected: Bool
    let actions: SwitcherActions

    @State private var hovering = false

    private var innerWidth: CGFloat { size.width - Metrics.tilePadding * 2 }

    var body: some View {
        VStack(spacing: Metrics.labelSpacing) {
            ZStack(alignment: .topLeading) {
                visual
                    .frame(width: innerWidth, height: visualHeight)
                if hoverButtons && hovering && item.axElement != nil {
                    WindowControls(item: item, actions: actions, enabled: actionsOn)
                        .padding(6)
                }
            }
            .frame(width: innerWidth, height: visualHeight)

            label
        }
        .padding(Metrics.tilePadding)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : (hovering ? Color.primary.opacity(0.07) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .background(HoverTracker(onHover: { hovering = $0 }, onMove: { actions.select(index) }))
        .contentShape(Rectangle())
        .onTapGesture { actions.activate(index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.appName), \(item.displayTitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var visual: some View {
        if style == .thumbnails, let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                .overlay(alignment: .bottomTrailing) { badge }
        } else {
            let dimension = style == .icons ? Metrics.iconSize : min(96, visualHeight * 0.55)
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: dimension, height: dimension)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) { badge }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let text = item.badge {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
                .padding(4)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if style == .thumbnails {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(item.displayTitle)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.labelHeight)
    }
}

@MainActor
struct TitleRow: View {
    let item: WindowItem
    let index: Int
    let selected: Bool
    let hoverButtons: Bool
    let actionsOn: Set<SwitcherFeature>
    let actions: SwitcherActions

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 20, height: 20)
            Text(item.appName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .lineLimit(1)
                .fixedSize()
            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let badge = item.badge {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if hoverButtons && hovering && item.axElement != nil {
                WindowControls(item: item, actions: actions, enabled: actionsOn)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.25) : (hovering ? Color.primary.opacity(0.07) : Color.clear))
        )
        .background(HoverTracker(onHover: { hovering = $0 }, onMove: { actions.select(index) }))
        .contentShape(Rectangle())
        .onTapGesture { actions.activate(index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.appName), \(item.displayTitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Close / minimize / full-screen buttons shown when hovering a window.
@MainActor
struct WindowControls: View {
    let item: WindowItem
    let actions: SwitcherActions
    /// Window actions that are turned on; the others' buttons are omitted.
    let enabled: Set<SwitcherFeature>

    var body: some View {
        HStack(spacing: 6) {
            if enabled.contains(.actionClose) {
                control("xmark", Color(red: 1.0, green: 0.37, blue: 0.34), "Close window") { actions.close(item.id) }
            }
            if enabled.contains(.actionMinimize) {
                control("minus", Color(red: 1.0, green: 0.74, blue: 0.18), "Minimize window") { actions.minimize(item.id) }
            }
            if enabled.contains(.actionFullscreen) {
                control("arrow.up.left.and.arrow.down.right", Color(red: 0.16, green: 0.79, blue: 0.25), "Toggle full screen") {
                    actions.fullscreen(item.id)
                }
            }
        }
    }

    private func control(_ symbol: String, _ color: Color, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Color.black.opacity(0.55))
                .frame(width: 14, height: 14)
                .background(Circle().fill(color))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Mouse tracking that works even though Snaptic is never the active app.
/// Placed behind content, so it never intercepts clicks.
struct HoverTracker: NSViewRepresentable {
    var onHover: (Bool) -> Void
    var onMove: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = onHover
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = onHover
        view.onMove = onMove
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        var onMove: (() -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
        // Only real mouse movement selects, so a cursor resting where the
        // panel appears doesn't steal the keyboard selection.
        override func mouseMoved(with event: NSEvent) { onMove?() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

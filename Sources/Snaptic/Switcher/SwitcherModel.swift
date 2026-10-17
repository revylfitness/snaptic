import AppKit
import Combine
import SnapticKit

enum Metrics {
    static let panelPadding: CGFloat = 16
    static let headerHeight: CGFloat = 22
    static let headerSpacing: CGFloat = 10
    static let gap: CGFloat = 10
    static let tilePadding: CGFloat = 8
    static let labelHeight: CGFloat = 20
    static let labelSpacing: CGFloat = 6
    static let iconSize: CGFloat = 64
    static let iconTile = CGSize(width: 116, height: 116)
    static let titleRowHeight: CGFloat = 34
    static let titleRowGap: CGFloat = 2
    static let titleRowWidth: CGFloat = 720
    static let minPanelContent = CGSize(width: 360, height: 90)
}

struct Tile {
    let index: Int          // index into the filtered window list
    let windowID: CGWindowID
    let size: CGSize        // outer size, including padding and label
}

struct GridLayout {
    var rows: [[Tile]] = []
    var rowWidths: [CGFloat] = []
    var rowHeights: [CGFloat] = []
    var contentSize: CGSize = .zero
    var thumbHeight: CGFloat = 0

    static let empty = GridLayout()
}

enum LayoutEngine {
    static func compute(
        items: [WindowItem],
        style: SwitcherStyle,
        maxContent: CGSize,
        autoSize: Bool,
        baseHeight: CGFloat
    ) -> GridLayout {
        guard !items.isEmpty else { return .empty }

        switch style {
        case .thumbnails:
            // Auto-size: try big previews first and shrink until everything fits.
            let candidates: [CGFloat] = autoSize
                ? Array(stride(from: CGFloat(300), through: CGFloat(60), by: -10))
                : [baseHeight]
            var result = GridLayout.empty
            for height in candidates {
                result = pack(items, maxWidth: maxContent.width) { thumbnailTile($0, height: height) }
                result.thumbHeight = height
                if result.contentSize.height <= maxContent.height { break }
            }
            return result

        case .icons:
            var result = pack(items, maxWidth: maxContent.width) { _ in Metrics.iconTile }
            result.thumbHeight = Metrics.iconSize
            return result

        case .titles:
            let width = min(Metrics.titleRowWidth, maxContent.width)
            let size = CGSize(width: width, height: Metrics.titleRowHeight)
            var result = GridLayout.empty
            result.rows = items.enumerated().map { [Tile(index: $0.offset, windowID: $0.element.id, size: size)] }
            result.rowWidths = Array(repeating: width, count: items.count)
            result.rowHeights = Array(repeating: Metrics.titleRowHeight, count: items.count)
            let count = CGFloat(items.count)
            result.contentSize = CGSize(
                width: width,
                height: count * Metrics.titleRowHeight + (count - 1) * Metrics.titleRowGap
            )
            return result
        }
    }

    private static func thumbnailTile(_ item: WindowItem, height: CGFloat) -> CGSize {
        let width = min(max(height * item.aspectRatio, height * 0.75), height * 1.9)
        return CGSize(
            width: ceil(width + Metrics.tilePadding * 2),
            height: ceil(height + Metrics.labelSpacing + Metrics.labelHeight + Metrics.tilePadding * 2)
        )
    }

    private static func pack(
        _ items: [WindowItem],
        maxWidth: CGFloat,
        size: (WindowItem) -> CGSize
    ) -> GridLayout {
        var layout = GridLayout.empty
        var row: [Tile] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        func flush() {
            guard !row.isEmpty else { return }
            layout.rows.append(row)
            layout.rowWidths.append(rowWidth)
            layout.rowHeights.append(rowHeight)
            row = []
            rowWidth = 0
            rowHeight = 0
        }

        for (index, item) in items.enumerated() {
            let tileSize = size(item)
            if !row.isEmpty && rowWidth + Metrics.gap + tileSize.width > maxWidth {
                flush()
            }
            rowWidth = row.isEmpty ? tileSize.width : rowWidth + Metrics.gap + tileSize.width
            rowHeight = max(rowHeight, tileSize.height)
            row.append(Tile(index: index, windowID: item.id, size: tileSize))
        }
        flush()

        let width = layout.rowWidths.max() ?? 0
        let height = layout.rowHeights.reduce(0, +) + CGFloat(max(0, layout.rows.count - 1)) * Metrics.gap
        layout.contentSize = CGSize(width: width, height: height)
        return layout
    }

    /// The tile in the row above/below whose center is closest horizontally.
    static func verticalNeighbor(of index: Int, delta: Int, in layout: GridLayout) -> Int? {
        guard let row = layout.rows.firstIndex(where: { $0.contains { $0.index == index } }) else { return nil }
        let count = layout.rows.count
        let target = ((row + delta) % count + count) % count
        let x = centerX(of: index, row: row, in: layout)
        return layout.rows[target].min { a, b in
            abs(centerX(of: a.index, row: target, in: layout) - x) < abs(centerX(of: b.index, row: target, in: layout) - x)
        }?.index
    }

    private static func centerX(of index: Int, row: Int, in layout: GridLayout) -> CGFloat {
        var x = (layout.contentSize.width - layout.rowWidths[row]) / 2
        for tile in layout.rows[row] {
            if tile.index == index { return x + tile.size.width / 2 }
            x += tile.size.width + Metrics.gap
        }
        return x
    }
}

/// Matches every space-separated word of the query against "App name + window title".
/// Substring matches rank above loose in-order letter matches.
enum Fuzzy {
    static func score(_ query: String, in text: String) -> Int? {
        let haystack = text.lowercased()
        var total = 0
        for word in query.lowercased().split(separator: " ") {
            guard let s = wordScore(String(word), in: haystack) else { return nil }
            total += s
        }
        return total
    }

    private static func wordScore(_ word: String, in text: String) -> Int? {
        if let range = text.range(of: word) {
            let position = text.distance(from: text.startIndex, to: range.lowerBound)
            let atWordStart = range.lowerBound == text.startIndex
                || !text[text.index(before: range.lowerBound)].isLetter
            return 1000 + (atWordStart ? 200 : 0) - min(position, 200)
        }
        var cursor = text.startIndex
        var previous: String.Index?
        var score = 0
        for character in word {
            guard let found = text[cursor...].firstIndex(of: character) else { return nil }
            if let previous, text.index(after: previous) == found { score += 10 } else { score += 1 }
            previous = found
            cursor = text.index(after: found)
        }
        return score
    }
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published private(set) var allItems: [WindowItem] = []
    @Published private(set) var filtered: [WindowItem] = []
    @Published private(set) var query = ""
    @Published private(set) var style: SwitcherStyle = .thumbnails
    @Published private(set) var layout = GridLayout.empty
    @Published var selectedIndex = 0
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    /// True once the user pressed S (or /) to start typing a search.
    @Published var searching = false
    /// False while the window list is still being read.
    @Published private(set) var loaded = false
    /// Changes on every open, so SwiftUI rebuilds views and forgets stale hover
    /// and scroll state from the previous session.
    @Published private(set) var session = 0
    /// Keys that work while open, for the header (turned-off features are left out).
    @Published private(set) var hint = ""
    /// Hover buttons, and which window actions they may offer.
    @Published private(set) var showHoverButtons = true
    @Published private(set) var enabledActions: Set<SwitcherFeature> = Set(SwitcherFeaturesConfig.actions)

    var selected: WindowItem? {
        filtered.indices.contains(selectedIndex) ? filtered[selectedIndex] : nil
    }

    func begin(style: SwitcherStyle, hint: String, hoverButtons: Bool, actions: Set<SwitcherFeature>) {
        session += 1
        self.style = style
        self.hint = hint
        showHoverButtons = hoverButtons
        enabledActions = actions
        allItems = []
        filtered = []
        query = ""
        searching = false
        loaded = false
        selectedIndex = 0
        thumbnails = [:]
        layout = .empty
    }

    func load(_ items: [WindowItem]) {
        allItems = items
        loaded = true
        // Keep anything typed into search while the list was loading.
        setQuery(query)
    }

    /// Drops everything (window titles, thumbnails, search text) when the switcher closes.
    func reset() {
        allItems = []
        filtered = []
        query = ""
        searching = false
        loaded = false
        selectedIndex = 0
        thumbnails = [:]
        layout = .empty
    }

    func setQuery(_ newQuery: String) {
        query = newQuery
        if newQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = allItems
        } else {
            var scored: [(order: Int, item: WindowItem, score: Int)] = []
            for (order, item) in allItems.enumerated() {
                if let score = Fuzzy.score(newQuery, in: item.searchText) {
                    scored.append((order, item, score))
                }
            }
            scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            filtered = scored.map { $0.item }
        }
        selectedIndex = 0
    }

    func remove(_ id: CGWindowID) {
        let previous = selectedIndex
        allItems.removeAll { $0.id == id }
        setQuery(query)
        selectedIndex = min(previous, max(0, filtered.count - 1))
    }

    func update(_ id: CGWindowID, _ change: (inout WindowItem) -> Void) {
        if let i = allItems.firstIndex(where: { $0.id == id }) { change(&allItems[i]) }
        if let i = filtered.firstIndex(where: { $0.id == id }) { change(&filtered[i]) }
    }

    func relayout(maxContent: CGSize, autoSize: Bool, baseHeight: CGFloat) {
        layout = LayoutEngine.compute(
            items: filtered,
            style: style,
            maxContent: maxContent,
            autoSize: autoSize,
            baseHeight: baseHeight
        )
    }

    func step(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    func moveVertically(_ delta: Int) {
        if style == .titles {
            step(delta)
        } else if let target = LayoutEngine.verticalNeighbor(of: selectedIndex, delta: delta, in: layout) {
            selectedIndex = target
        }
    }
}

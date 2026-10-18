import SwiftUI
import SnapticKit

struct DisplayTile: Identifiable, Hashable {
    let id: DisplayKey
    let name: String
    let isBuiltin: Bool
    let badges: [String]
}

/// The display a page's per-display rows apply to (System Settings › Displays). ≤ 4 displays: tiles; more: a
/// pop-up; hidden with one display. Group AX label "Display". The selection is shared across pages through
/// `SettingsShell.selectedDisplay` (design m9); a selection that isn't connected shows the first display.
/// Budget: counts toward a page's total, not toward its settings (design m13).
struct PerDisplayPicker: View {
    let displays: [DisplayTile]
    let selection: Binding<DisplayKey?>

    init(_ displays: [DisplayTile], selection: Binding<DisplayKey?>) {
        self.displays = displays
        self.selection = selection
    }

    var body: some View {
        if displays.count > 4 {
            Picker(L("Display"), selection: effective) {
                ForEach(displays) { tile in
                    Text(tile.name).tag(Optional(tile.id))
                }
            }
            .pickerStyle(.menu)
        } else if displays.count > 1 {
            HStack(alignment: .top, spacing: 20) {
                ForEach(displays) { tile in
                    tileView(tile)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .focusable()
            .onKeyPress(.leftArrow) { move(-1) }
            .onKeyPress(.rightArrow) { move(1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("Display"))
        }
    }

    /// The selection, or the first display when it names none of them.
    private var effective: Binding<DisplayKey?> {
        let ids = displays.map(\.id)
        return Binding(get: {
            if let s = selection.wrappedValue, ids.contains(s) { return s }
            return ids.first
        }, set: { selection.wrappedValue = $0 })
    }

    private func tileView(_ tile: DisplayTile) -> some View {
        let selected = tile.id == effective.wrappedValue
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            selection.wrappedValue = tile.id
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tile.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 32, weight: .light))
                    .frame(width: 76, height: 52)
                    .background(shape.fill(selected ? Color.accentColor.opacity(0.15) : Color.clear))
                    .overlay(shape.strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
                Text(tile.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(selected ? .primary : .secondary)
                if !tile.badges.isEmpty {
                    Text(tile.badges.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.name)
        .accessibilityValue(tile.badges.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let ids = displays.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let i = effective.wrappedValue.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(ids.count - 1, max(0, i + delta))
        selection.wrappedValue = ids[next]
        return .handled
    }
}

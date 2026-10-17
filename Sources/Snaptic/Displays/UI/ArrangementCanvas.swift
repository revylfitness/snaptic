import SwiftUI
import SnapticKit

/// Drag-to-arrange canvas (PLAN §9.6, parity §7.4). Drops snap to edges and alignments
/// (ArrangementMath) and apply as one low-risk origin change. The Position/Align form on the
/// Arrangement page is the keyboard path.
struct ArrangementCanvas: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State private var dragging: DisplayKey?
    @State private var translation: CGSize = .zero

    private var displays: [DisplayInfo] { env.runtime.displays.filter { $0.isActive && $0.mirrorOf == nil } }

    var body: some View {
        GeometryReader { geo in
            let layout = CanvasLayout(rects: displays.map { ($0.key, ManagedDisplays.rect($0)) }, size: geo.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(displays, id: \.key) { d in
                    tile(d, layout: layout)
                }
            }
        }
        .frame(minHeight: 220, idealHeight: 260)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Display arrangement"))
    }

    private func tile(_ d: DisplayInfo, layout: CanvasLayout) -> some View {
        let frame = layout.frame(ManagedDisplays.rect(d))
        let isDragging = dragging == d.key
        let dx = isDragging ? translation.width : 0
        let dy = isDragging ? translation.height : 0
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4)
                .fill(d.isMain ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.25))
            RoundedRectangle(cornerRadius: 4)
                .stroke(isDragging ? Color.accentColor : Color.secondary.opacity(0.6), lineWidth: isDragging ? 2 : 1)
            if d.isMain {
                Rectangle().fill(Color.primary.opacity(0.5)).frame(height: 4).padding(.horizontal, 3).padding(.top, 3)
            }
            VStack(spacing: 2) {
                Text(d.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                Text("\(Int(d.bounds.width)) × \(Int(d.bounds.height))").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(6)
            .frame(maxHeight: .infinity)
        }
        .frame(width: max(24, frame.width), height: max(18, frame.height))
        .offset(x: frame.minX + dx, y: frame.minY + dy)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    dragging = d.key
                    translation = value.translation
                }
                .onEnded { value in
                    finish(d, translation: value.translation, scale: layout.scale)
                    dragging = nil
                    translation = .zero
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.isMain ? L("\(d.name), main display") : d.name)
        .accessibilityValue(L("at \(Int(d.bounds.minX)), \(Int(d.bounds.minY))"))
        .accessibilityHint(L("Drag to move. Use Position and Align below to move it with the keyboard."))
    }

    private func finish(_ d: DisplayInfo, translation: CGSize, scale: CGFloat) {
        guard scale > 0, let c = env.context?.connectPlanner.arrangement, abs(translation.width) + abs(translation.height) > 3 else { return }
        var rects = c.currentRects()
        guard let start = rects[d.key] else { return }
        let x = Int64(start.x) + Int64((translation.width / scale).rounded())
        let y = Int64(start.y) + Int64((translation.height / scale).rounded())
        let moved = start.moved(x: Int32(clamping: x), y: Int32(clamping: y))
        let others = rects.filter { $0.key != d.key }.map(\.value)
        let threshold = env.config.value.management.snapArrangement ? 48 : 0
        rects[d.key] = ArrangementMath.snap(moved, others: others, threshold: threshold)
        c.arrange(rects)
    }
}

/// Maps global display rects into the canvas.
private struct CanvasLayout {
    let scale: CGFloat
    let originX: CGFloat
    let originY: CGFloat
    let minX: CGFloat
    let minY: CGFloat

    init(rects: [(DisplayKey, ArrangeRect)], size: CGSize) {
        let r = rects.map(\.1)
        let minX = CGFloat(r.map { Int64($0.x) }.min() ?? 0)
        let minY = CGFloat(r.map { Int64($0.y) }.min() ?? 0)
        let maxX = CGFloat(r.map(\.maxX).max() ?? 1)
        let maxY = CGFloat(r.map(\.maxY).max() ?? 1)
        let w = max(1, maxX - minX), h = max(1, maxY - minY)
        let pad: CGFloat = 24
        let s = max(0.001, min((size.width - pad * 2) / w, (size.height - pad * 2) / h))
        scale = s
        self.minX = minX
        self.minY = minY
        originX = (size.width - w * s) / 2
        originY = (size.height - h * s) / 2
    }

    func frame(_ r: ArrangeRect) -> CGRect {
        CGRect(x: originX + (CGFloat(r.x) - minX) * scale, y: originY + (CGFloat(r.y) - minY) * scale,
               width: CGFloat(r.width) * scale, height: CGFloat(r.height) * scale)
    }
}

import SwiftUI
import SnapticKit

/// How to Arrange Your Icons (lead; PLAN 0.4 §4.17, §4.0, A7): a small drawing of the menu bar with its sections,
/// then the ⌘-drag rules for this engine. Opened by How to Arrange…, the first-run status action, and turning
/// Hidden Icons on. It has no settings, so no controls.
struct IconsArrangeSheet: View {
    let engine: IconsEngineKind
    let alwaysHidden: Bool
    @Environment(\.dismiss) private var dismiss

    /// The engine this Mac would use, for the sheet opened before the module has started.
    @MainActor static var engineForThisMac: IconsEngineKind {
        IconsModule.osMajor >= IconsEngineFactory.nativeMajor ? .native : .length
    }

    var body: some View {
        let lines = IconsPageRules.arrangeLines(engine: engine, alwaysHidden: alwaysHidden)
        VStack(alignment: .leading, spacing: 14) {
            Text(IconsPageRules.arrangeTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            diagram
            Text(IconsPageRules.arrangeIntro)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines.bullets, id: \.self) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(bullet).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(lines.closing)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { SettingsShell.shared.sheetDidAppear() }
        .onExitCommand { dismiss() }
    }

    // MARK: Diagram

    /// ⋮ [A] [B] | [C] [D] ‹ [E] [S] with brackets under each section (no | on macOS 27).
    private var diagram: some View {
        HStack(alignment: .top, spacing: 10) {
            if alwaysHidden {
                Text("⋮").font(.title3.weight(.semibold))
                group(["a.circle", "b.circle"], label: L("Always Hidden"))
            }
            if engine == .length {
                group(["c.circle", "d.circle"], label: L("Hidden"))
                Text("|").font(.title3.weight(.semibold))
            } else {
                group(["c.circle", "d.circle"], label: L("Hidden"))
            }
            Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            group(["e.circle", "s.circle"], label: L("Shown"))
            Text(verbatim: "9:41").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("A menu bar with the arrow, the dividers, and the icons on each side"))
    }

    private func group(_ symbols: [String], label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(symbols, id: \.self) { Image(systemName: $0).font(.title3) }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

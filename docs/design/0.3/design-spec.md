# Snaptic Settings and Menu Bar Design Spec

Target: macOS 14 through 27. Built with Xcode 16.4 / macOS 15 SDK, Swift 5 mode, `ObservableObject` (no `@Observable`, no `#Preview`). Modules: Window Switcher, Displays, Awake.

Guiding rules, taken from Apple's Settings HIG [S1]:
- "Aim to provide default settings that give the best experience to the largest number of people."
- "Minimize the number of settings you offer."
- Don't duplicate systemwide settings. For example, don't add a Snaptic "Reduce motion" switch; follow the system one.
- "Restore the most recently viewed pane," and "Update the window's title to reflect the currently visible pane."

Success test: each module page shows **at most about 8 controls** before the "Advanced…" button. Everything else sits one click deeper.

**0.3.1 amendments** (`docs/design/0.3.1/PLAN.md`) are marked "(0.3.1)": §1.5 (lid-closed mode in Awake's Advanced), §3.3 (tabs in the Snaptic menu and the attention-mark exception), §3.4 (the resize exception), §4.7 (terminology) and §5 (icons).

---

## 1. Information architecture

### 1.1 Window shell (System Settings model, macOS 13+)

- `NavigationSplitView` with a sidebar `List` and a detail `NavigationStack`, so sub-pages get a toolbar back button the way System Settings > General > About does.
- Size: about 715 pt wide. The sidebar column is 200–240 pt, and the detail column holds a grouped form about 480–500 pt wide. The window resizes vertically only.
- Remove the sidebar toggle with `.toolbar(removing: .sidebarToggle)` (macOS 14). Dim minimize and zoom, as the HIG says to for settings windows [S1].
- Set the window title with `.navigationTitle(pane.title)`. Save the last pane in `@AppStorage` and reopen to it.
- Put the search field at the top of the sidebar with `.searchable(text:placement: .sidebar)`. HIG: "Avoid putting critical information or actions at the bottom of a sidebar" [S2].
- Use at most two levels of hierarchy in the sidebar [S2]. Separate groups with spacing, not headers, as System Settings does. Each item gets a colored rounded-square icon tile with a white SF Symbol. Use a fixed tint per item; HIG allows fixed colors when they're used sparingly [S2], and macOS 27 brought sidebar icon color back [S8].

### 1.2 Sidebar

```
[ Search ]
General                gearshape          gray
Menu Bar               menubar.rectangle  blue
──
Window Switcher        rectangle.on.rectangle  indigo
Displays               sun.max.fill            blue
Awake                  cup.and.saucer.fill     orange
──
Permissions            hand.raised.fill   blue
About                  info.circle.fill   gray   (version, updates, acknowledgements)
```

**Modularity.** Every module always appears in the sidebar, so it stays discoverable. Each module page opens with a header that carries a master switch, the way Wi-Fi and Bluetooth do.

When a module is off:
- The page shows only the header, plus a short "what this does" block: 2–3 rows, each with a symbol, a bold title and one line of text. This follows the off state of Screen Time and Siri.
- The module adds nothing to the menu bar, registers no shortcuts and runs no background work.

Onboarding asks once which modules to turn on. Per HIG, people, not the app, decide what goes in the menu bar [S3].

### 1.3 Page anatomy (top to bottom)

1. **Header section** (`SettingsPageHeader`): a 40 pt icon tile, the title, a one-sentence description, an optional "Learn More…" link, and a trailing master switch on module pages. Top-level pages without a switch, such as General and About, can use the centered "hero" variant from macOS 14+ General.
2. **Target selector**, Displays only. A row of display tiles, like System Settings > Displays since Ventura. It's hidden when only one display is connected.
3. **Primary sections.** At most 3 `Section`s of common settings. Each control row has a title and, where it helps, a one-line subtitle.
4. **Navigation rows.** `NavigationLink` rows with a chevron lead to sub-pages for areas that are large but cohesive, such as Displays > Color.
5. **Footer button row.** "Restore Defaults…" on the leading edge. "Advanced…" and the `HelpLink` (?) on the trailing edge. This is the pattern on the Displays, Battery ("Options…") and Network pages.

### 1.4 Progressive disclosure, in order of preference

| Need | Pattern | Apple precedent |
|---|---|---|
| 1 extra line of explanation | Row subtitle (`Toggle { Text; Text }`) | Lock Screen, Battery |
| Per-item details (one display or rule) | `InfoButton` (i) popover, or a "Details…" button opening a sheet | Wi-Fi network "Details…" |
| Large cohesive area | Navigation row to a sub-page | General > About, Software Update |
| Rarely changed or expert settings | "Advanced…" sheet from the page footer | Displays "Advanced…" |
| 1–3 dependent options | Show them only when the parent switch is on, indented with mini switches [S4] | Lock Screen |
| Inline expert toggles | `DisclosureGroup("Advanced Options")` with a descriptive label [S5]. Use at most one per page. | Keynote export |

Avoid tabs inside pages and nested sheets.

### 1.5 Module pages

**Window Switcher.** "Switch between windows, not just apps, with a keyboard shortcut."
- Shortcut: recorder row.
- Show windows from: Picker with All Spaces / Current Space.
- Include minimized windows: switch.
- Style: segmented picker, Thumbnails / List.
- Advanced…: excluded apps, show delay, sort order, hidden-window behavior.

**Displays.** "Adjust brightness, resolution, and color on every connected display."
- Display tiles.
- Section: Brightness slider with sun symbols at both ends. Resolution uses Apple's "Larger Text … More Space" thumbnails, or a pop-up of scaled modes. Refresh rate pop-up. HDR switch where supported.
- Section: "Arrange…" button (sheet), and "Mirror or extend to" pop-up.
- Navigation rows: Color · Virtual Displays · Picture in Picture · Saved Layouts · Brightness Keys · Change Automatically.
- Advanced… sheet, in four groups:
  - Hardware control: DDC on/off per display, write rate.
  - Safety: confirm changes, recovery shortcut.
  - Display information: the diagnostics.
  - Show all resolutions.
- Safety is a behavior, not a page. Every resolution, refresh or mirroring change shows an alert with Keep Changes / Revert and a 15-second countdown, matching macOS. The only setting for it lives in Advanced.

**Awake.** "Keep your Mac awake for a while, or whenever certain conditions are met." (Apple says "sleep," not "insomnia.")
- Section "Default session":
  - Duration: pop-up with 15 Minutes, 30 Minutes, 1 Hour, 2 Hours, 5 Hours, Until Turned Off, Custom….
  - "Let the display turn off": switch with the subtitle "Your Mac stays awake, but the display can sleep to save energy."
- Section "End sessions automatically":
  - "When battery is below": a slider from 5 to 50%, step 5, with a value label.
  - "When the power adapter is disconnected": switch.
- Section "Start automatically" (modeled on Focus > "Turn On Automatically"): a list of conditions plus an "Add Condition…" button. Conditions are when an app is open, when a display is connected, while charging, and on a schedule.
- Advanced…: allow sleep when the lid is closed (with a warning about heat), prevent screen saver, and log sessions.
- **(0.3.1) Advanced… › "Lid closed"**, following the experimental pointer-movement pattern, on Macs with a battery only:
  - Toggle "Keep awake with the lid closed" (opt-in, off by default), help: "Choose Keep Awake with the Lid Closed in the Awake menu. Asks for an administrator password each time."
  - While it's on and Snaptic's bundle is writable by the user, a `SettingsRowNote`: "Your account can change this copy of Snaptic, so another app could change it and misuse the password prompt." with **Learn More…** (README › "Your password and what runs as root").
  - The heat warning is the section footer: "While lid-closed mode is on, your Mac can’t sleep for low battery or heat. Awake turns it off at the Awake page’s battery level (at least 10%), when your Mac gets hot, or after 24 hours. Use it on a hard surface, not in a bag. Learn More…"
  - No time-limit picker (the limit is a fixed 24 hours) and no separate battery setting (it's derived from Awake's).
  - From a translocated copy, the row is replaced by "Snaptic is running from a temporary location. Move it to Applications to use lid-closed mode."
  - The lid isn't a setting on the main page; the lid route line there points to Advanced or to the menu.

### 1.6 Search

- Maintain a static `SettingsIndex: [SettingEntry(id, title, keywords, pane, anchorID)]`, with synonyms such as "DDC", "monitor", "caffeinate", "insomnia", "alt-tab", "PIP".
- While the query is non-empty, the sidebar list shows matches as "Title / Pane" rows, like System Settings' search results.
- Choosing a result navigates to the pane, scrolls with `ScrollViewReader.scrollTo(anchorID, anchor: .center)` and highlights the row briefly with a 1.2 s accent-tinted background. With Reduce Motion on, use a static tint and no scroll animation.
- With no matches, show `ContentUnavailableView.search(text:)` (macOS 14).
- Search covers Advanced sheets too: the result opens the sheet.

---

## 2. Controls in `Form` + `.formStyle(.grouped)`

Platform facts we rely on:
- In a grouped form (macOS 13+), `LabeledContent`, `Toggle`, and `Picker` labels built from two `Text` views render as title + secondary subtitle.
- HIG: in a grouped form, use a mini switch for a single-row setting; use regular switches for primary settings and mini switches for subordinate ones [S4].
- Prefer a switch to emphasize a setting. Prefer checkboxes for hierarchies of related options [S4].
- Sliders: add a text field and a stepper when the range is wide or precision matters. Give live feedback. Put minimum values on the leading edge. Use tick marks for discrete values [S6].
- More than about five options: use a pop-up (`.menu`). Two to four short, visual options: `.segmented`. Two to five options that need descriptions: `.radioGroup`.

**Responsiveness.** Bind controls straight to `@Published` model properties so the UI never waits. The model, not the view, rate-limits hardware: brightness writes through DDC are coalesced to about 20–30 Hz, with the final value written on `onEditingChanged(false)`. Don't route a slider binding through async work.

**Reset.** Apple's own patterns:
1. A page-level "Restore Defaults…" button, with a confirmation that names the scope ("Restore Display settings to their defaults?").
2. A row context menu with "Reset to Default".
3. Optional for continuous values only (sliders and number fields): a small reset glyph that appears only when the value differs from the default. It always reserves its space, so the layout doesn't jump.

**Accessibility.**
- Each control has an `accessibilityLabel` equal to its visible title.
- Sliders set `accessibilityValue` to the formatted value with the unit spelled out ("70 percent").
- Icon tiles are `accessibilityHidden`.
- Custom tile pickers get the `.isSelected` trait.
- Use `.help()` tooltips for icon-only buttons. Begin with a verb and keep them to 60–75 characters [S7].

**Keyboard.**
- Use standard controls only, so Tab and full keyboard access work.
- The ⌘, shortcut opens the window. The default button in sheets is Return (`.keyboardShortcut(.defaultAction)`), and Esc cancels.
- Number fields commit on Return and when focus leaves.

### 2.1 Component sketches (macOS 14, Swift 5)

```swift
import SwiftUI

// System Settings–style icon tile
struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(tint.gradient)
            .overlay(Image(systemName: symbol)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(.white))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// Page header with optional master switch (Wi-Fi / Bluetooth pattern)
struct SettingsPageHeader: View {
    let title: LocalizedStringKey
    let summary: LocalizedStringKey
    let symbol: String
    let tint: Color
    var isOn: Binding<Bool>? = nil
    var learnMore: URL? = nil

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                SettingsIcon(symbol: symbol, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let learnMore { Link("Learn More…", destination: learnMore) }
                }
                Spacer(minLength: 8)
                if let isOn {
                    Toggle(title, isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)          // regular size: primary setting
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
        }
    }
}

// Reset glyph that reserves space and appears only when changed
struct ResetButton: View {
    let isVisible: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Reset to default value")
        .accessibilityLabel("Reset to Default")
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(.easeOut(duration: 0.15), value: isVisible)   // fade only: OK with Reduce Motion
    }
}

// Generic row: title + optional subtitle + trailing control + reset
struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var isDefault: Bool = true
    var reset: (() -> Void)? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                control()
                if let reset { ResetButton(isVisible: !isDefault, action: reset) }
            }
        } label: {
            Text(title)
            if let subtitle { Text(subtitle) }      // rendered as secondary subtitle
        }
        .contextMenu {
            if let reset { Button("Reset to Default", action: reset).disabled(isDefault) }
        }
    }
}

// Switch with explanatory subtitle
struct ToggleSetting: View {
    let title: LocalizedStringKey
    var help: LocalizedStringKey? = nil
    @Binding var isOn: Bool
    var subordinate = false                       // mini switch for dependent rows [S4]
    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
            if let help { Text(help) }
        }
        .toggleStyle(.switch)
        .controlSize(subordinate ? .mini : .regular)
    }
}

// Inline numeric field with unit suffix, clamping, commit on Return/blur
struct NumberField: View {
    let label: LocalizedStringKey                 // accessibility only
    @Binding var value: Double
    let range: ClosedRange<Double>
    var fractionDigits = 0
    var unit: String? = nil
    var width: CGFloat = 48
    @State private var draft: Double = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, value: $draft,
                      format: .number.precision(.fractionLength(fractionDigits)).grouping(.never))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: width)
                .focused($focused)
                .onSubmit(commit)
                .onAppear { draft = value }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onChange(of: value) { _, newValue in if !focused { draft = newValue } }
            if let unit { Text(unit).foregroundStyle(.secondary) }
        }
    }
    private func commit() {
        let clamped = min(max(draft, range.lowerBound), range.upperBound)
        draft = clamped
        if clamped != value { value = clamped }
    }
}

// Slider row: live label OR number field (+ optional stepper), reset, a11y
struct SliderSetting: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var unit: String = ""                         // "%", "Hz", " min"
    var spokenUnit: String = ""                   // "percent"
    let defaultValue: Double
    var editableField = false                     // true only where precision matters
    var showsStepper = false
    var minSymbol: String? = nil                  // e.g. "sun.min"
    var maxSymbol: String? = nil                  // e.g. "sun.max"
    var format: (Double) -> String = { String(Int($0.rounded())) }
    var onEditingChanged: (Bool) -> Void = { _ in }

    private var isDefault: Bool { abs(value - defaultValue) < max(step ?? 0, 0.0001) / 2 }

    var body: some View {
        SettingRow(title: title, subtitle: subtitle, isDefault: isDefault,
                   reset: { value = defaultValue }) {
            slider.frame(minWidth: 160, idealWidth: 200)
            if editableField {
                NumberField(label: title, value: $value, range: range, unit: unit)
                if showsStepper, let step {
                    Stepper(title, value: $value, in: range, step: step).labelsHidden()
                }
            } else {
                Text(format(value) + unit)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
                    .accessibilityHidden(true)    // value is exposed on the slider
            }
        }
    }

    @ViewBuilder private var slider: some View {
        let minLabel = Group { if let s = minSymbol { Image(systemName: s) } }
        let maxLabel = Group { if let s = maxSymbol { Image(systemName: s) } }
        Group {
            if let step {
                Slider(value: $value, in: range, step: step,
                       label: { Text(title) },
                       minimumValueLabel: { minLabel }, maximumValueLabel: { maxLabel },
                       onEditingChanged: onEditingChanged)
            } else {
                Slider(value: $value, in: range,
                       label: { Text(title) },
                       minimumValueLabel: { minLabel }, maximumValueLabel: { maxLabel },
                       onEditingChanged: onEditingChanged)
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(format(value)) \(spokenUnit)"))
    }
}

// "(i)" per-item details popover
struct InfoButton: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @State private var shown = false
    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .help("Show details")
            .accessibilityLabel(Text(title))
            .accessibilityHint("Shows details")
            .popover(isPresented: $shown, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(message).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(width: 280, alignment: .leading)
            }
    }
}

// Display tiles (System Settings > Displays); hidden with one display
struct DisplayInfo: Identifiable, Hashable { let id: UInt32; let name: String; let isBuiltIn: Bool }

struct PerDisplayPicker: View {
    let displays: [DisplayInfo]
    @Binding var selection: UInt32
    var body: some View {
        if displays.count > 1 {
            HStack(spacing: 20) {
                ForEach(displays) { d in
                    let selected = d.id == selection
                    Button { selection = d.id } label: {
                        VStack(spacing: 6) {
                            Image(systemName: d.isBuiltIn ? "laptopcomputer" : "display")
                                .font(.system(size: 32, weight: .light))
                                .frame(width: 76, height: 52)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.accentColor.opacity(0.15) : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                            Text(d.name).font(.callout).lineLimit(1)
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(d.name))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}
// Compact variant for sub-pages: Picker("Display", selection:) { ForEach… }.pickerStyle(.menu)

// Footer row: Restore Defaults… | Advanced…  (?)
struct PageFooterButtons: View {
    var restoreDefaults: (() -> Void)? = nil
    var advanced: (() -> Void)? = nil
    var helpAction: (() -> Void)? = nil
    var body: some View {
        HStack {
            if let restoreDefaults { Button("Restore Defaults…", action: restoreDefaults) }
            Spacer()
            if let advanced { Button("Advanced…", action: advanced) }
            if let helpAction { HelpLink(action: helpAction) }        // macOS 14+
        }
    }
}

// Advanced… sheet scaffold
struct AdvancedSheet<Content: View>: View {
    let title: LocalizedStringKey
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section { content() } header: { Text(title).font(.headline) }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520)
        .frame(minHeight: 320, idealHeight: 460)
    }
}
// AdvancedDisclosure: DisclosureGroup("Advanced Options", isExpanded: $expanded),
// where $expanded is @AppStorage("disclosure.<page>"). Use at most one per page.
```

**Example page.** The footer sits in an empty `Section` with only a footer; verify spacing on 14, 15, 26 and 27.

```swift
struct AwakePane: View {
    @ObservedObject var awake: AwakeSettings
    @State private var showAdvanced = false
    var body: some View {
        Form {
            SettingsPageHeader(title: "Awake",
                summary: "Keep your Mac awake for a while, or whenever certain conditions are met.",
                symbol: "cup.and.saucer.fill", tint: .orange, isOn: $awake.isEnabled)
            if awake.isEnabled {
                Section("Default session") {
                    Picker("Duration", selection: $awake.defaultDuration) {
                        ForEach(AwakeDuration.presets) { Text($0.title).tag($0) }
                        Divider(); Text("Custom…").tag(AwakeDuration.custom)
                    }
                    ToggleSetting(title: "Let the display turn off",
                                  help: "Your Mac stays awake, but the display can sleep to save energy.",
                                  isOn: $awake.allowDisplaySleep)
                }
                Section("End sessions automatically") {
                    SliderSetting(title: "When battery is below", value: $awake.batteryFloor,
                                  range: 5...50, step: 5, unit: "%", spokenUnit: "percent",
                                  defaultValue: 20)
                }
                Section {} footer: {
                    PageFooterButtons(restoreDefaults: { awake.confirmRestore() },
                                      advanced: { showAdvanced = true })
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Awake")
        .sheet(isPresented: $showAdvanced) { AdvancedSheet(title: "Advanced") { /* … */ } }
    }
}
```

**Help text.**
- Per-setting explanation goes in the row subtitle: one sentence describing what happens when the setting is on. People infer the off state [S9].
- Section-level caveats go in the `Section` footer as plain `Text`, so the form applies its secondary small style. They may end with a "Learn More…" link.
- Never stack more than two lines of help under one row. If you need more, use an (i) popover.

---

## 3. Menu bar

### 3.1 NSMenu vs. SwiftUI popover or panel

HIG: "Display a menu — not a popover — when people click your menu bar extra," unless the functionality is too complex for a menu [S3].

| | `NSStatusItem` + `NSMenu` (recommended) | `MenuBarExtra(.window)` / `NSPopover` / custom `NSPanel` |
|---|---|---|
| Appearance on 14–27 | Drawn by AppKit, so it follows the running OS's menu look automatically | Our own window. Built with the 15 SDK, it won't match Tahoe and Golden Gate Liquid Glass Control Center modules, and an imitation goes stale |
| Keyboard, VoiceOver, type-select | Free for native items | Must be built by hand |
| Dismissal and focus | Correct by default | `.window` gives no programmatic open/close. Panels need custom outside-click handling. macOS 27 adds `NSStatusItem.expandedInterfaceDelegate` for custom windows (27 SDK only), and developers report hover, highlight and touch-dismiss problems there [S10] |
| Rich layouts (grids, previews) | Limited: use `NSHostingView` rows | Flexible |

**Decision.** Use an `NSMenu` for every Snaptic extra. Put custom `NSHostingView` rows only where a native item can't express the control: sliders, and header rows with a switch. Keep clickable rows native.

Revisit when the SDK moves to 26 or later:
- **Control Center controls.** WidgetKit `ControlWidget` on macOS 26 fits "Keep Awake" and "Brightness". People could place them in Control Center or the menu bar, matching Tahoe's configuration model [S11].
- **`expandedInterfaceDelegate`** (macOS 27), for the Displays item only.

### 3.2 Apple's menu extra anatomy (Wi-Fi, Bluetooth, Sound, Display, Battery, Focus)

1. **Header row.** The module name in bold on the leading edge. A switch (Wi-Fi, Bluetooth) or a value (Battery percentage) on the trailing edge.
2. **Primary control.** A full-width slider with symbols at each end (Sound, Display), or a short list.
3. **Sections with small secondary headers.** Device rows with 26 pt circular icon tiles: filled with the accent color when active, gray otherwise.
4. **Separator, then "*Module* Settings…"** at the bottom.
5. **Option-click** reveals extra detail; Option-click on Wi-Fi shows diagnostics.
6. Width is about 280–320 pt when the menu holds sliders. Menu text is the system menu font (`NSFont.menuFont(ofSize: 0)`, 13 pt). Labels in menus use title case [S12].

### 3.3 Snaptic menus

There's one Snaptic item by default. The Menu Bar page offers "Show Awake as a separate item" and "Show Displays as a separate item". Sections for disabled modules don't appear.

**(0.3.1) Tabs.** The Menu Bar page now has one placement pop-up per module (0.3). When two or more modules are set to Show in Snaptic Menu, the shared menu shows a tab bar, one segment per module in the order Window Switcher, Displays, Awake, and only the selected module's items below it. With one module there is no tab bar and the section keeps its header (the sketch further down); own-icon menus don't change.

```
┌──────────────────────────────────────┐
│ Safe Mode Is On / Leave Safe Mode…    │  first group, any tab
│ Sleep Is Turned Off                   │  host-level leftover rows, any tab
│ Turn Sleep Back On…                   │
├──────────────────────────────────────┤
│ [ Window Switcher | Displays | Awake ]│  tab bar: only with 2+ modules in the menu
├──────────────────────────────────────┤
│ …the selected module's items…         │  no section header (the tab names it)
├──────────────────────────────────────┤
│ More Display Features…                │  only while Displays is off
│ Recent Notices         ›              │  when any
│ Update Available: Snaptic 0.3.2…      │  when an update is waiting
│ Snaptic Settings…               ⌘,    │  restores the last Settings pane
│ Quit Snaptic                    ⌘Q    │
└──────────────────────────────────────┘
```

- **Control.** An `NSSegmentedControl` (`.selectOne`, small) in a 28 pt view row that never draws the selection fill. Labels are module titles; the fallbacks, in order, are equal widths with full titles, equal widths with short titles ("Switcher"), then fitted short titles, measured with the attention image. Each segment's accessibility label is the full title, and its tooltip is "<Title> (⌘n)" ("Awake, on (⌘3)" while Awake governs). Segment labels are Title Case, like other segmented options (§4.1).
- **Keyboard.** ⌘1–⌘n choose a tab by position. Hidden native "Show … Tab" items carry them, and show above Snaptic Settings… while VoiceOver, Switch Control or Full Keyboard Access is on. A key choice closes the menu and the next open shows the tab.
- **Remembered.** The last tab is a plain `UserDefaults` value, kept across relaunches and never reset. A missing module falls back to the first tab without losing the choice.
- **Awake's tab** shows the full Awake rows minus "Awake Settings…"; the compact section stays only for Awake as the single shared module.
- **Attention marks: a deliberate exception.** The HIG says to prefer either text or images in a segmented control. A segment whose module needs attention still shows a 10 pt `exclamationmark.circle` next to its label, and VoiceOver adds ", needs attention". Without it, someone who stays on one tab would never see another module's warnings, a regression from 0.3's stacked menu. There is no "active" image: Awake's segment gets only the VoiceOver suffix ", on" and the tooltip, because the menu bar glyph already shows a session.
- **Width** is the widest tab's, measured when the menu is built, so switching never widens the menu or moves a segment under the pointer.
- **Row budget** (restating 0.3 PLAN §5.2 and HW-15): the tallest single tab ≤ 24 lines in the default setup.

0.3's stacked layout, still used with one module and as the general shape of sections:

```
Keep Awake                         [switch]   ← header row (hosting view)
  Ends at 3:45 PM                             ← secondary line, only when active
Keep Awake For                          ›     ← submenu: 15 Minutes … Until Turned Off, Custom…
───────────────
Displays                                       ← NSMenuItem.sectionHeader (macOS 14)
Studio Display                                 ← hosting row: name above slider
☀︎ ──────────●──── ☀︎
Built-in Retina Display
☀︎ ────●────────── ☀︎
Resolution                              ›     ← submenu per display, checkmarks
Arrange Displays…
───────────────
Show Window Switcher                  ⌥⇥
───────────────
Snaptic Settings…                     ⌘,
Quit Snaptic                          ⌘Q
```

Rules:
- Toggled items use a checkmark or a changeable label ("Turn Keep Awake Off") [S12].
- Use submenus sparingly, one level deep, with at most about five items [S12].
- Add an ellipsis only when more input follows.
- Menu item symbols: macOS 26 put icons on nearly every item. macOS 27 hides symbol images by default, but only for apps linked against the 26 SDK or later, via `NSMenuItem.preferredImageVisibility` [S13][S14]. Our 15-SDK build will **show** any symbol we attach, so attach none. The exception is device rows, where the image identifies the device (display type). HIG: icons go on all items in a group or none [S12].

### 3.4 Embedding SwiftUI in NSMenu

```swift
final class HostingMenuItem<Content: View>: NSMenuItem {
    init(width: CGFloat = 300, @ViewBuilder content: () -> Content) {
        super.init(title: "", action: nil, keyEquivalent: "")
        let root = content()
            .padding(.horizontal, 14)              // align with native item text
            .padding(.vertical, 4)
            .frame(width: width, alignment: .leading)
        let host = NSHostingView(rootView: root)
        host.frame.size = host.fittingSize
        view = host
    }
    required init(coder: NSCoder) { fatalError() }
}
```

- **Highlighting.** View-based items don't draw a selection highlight. Use hosting views only for non-actionable rows (sliders, header with switch), so nothing needs highlighting. If a custom row must be clickable, draw the selection yourself:
  - Track `menu(_:willHighlight:)`.
  - Fill a rounded rect (about 4–5 pt radius, inset 5 pt horizontally) with `NSColor.selectedContentBackgroundColor`.
  - Switch the text to `selectedMenuItemTextColor`.
  - Close the menu with `menu.cancelTracking()`.
- **Keyboard.** Native items get arrow keys, Return and type-select. Assume sliders in menu rows work with the mouse only. Make sure every slider action has a keyboard path: brightness keys, the Settings page, and native submenu presets such as Brightness › 25% / 50% / 75% / 100%.
- **Run loop.** Menus track events in event-tracking run loop mode. Schedule countdown and refresh timers with `RunLoop.main.add(timer, forMode: .common)`. Main-queue Combine updates still arrive.
- **Rebuilding.** Build the menu in `menuNeedsUpdate(_:)`, for example when the display list changes, and update values in place while it's open, so it doesn't flicker or resize.
  - **(0.3.1) Exception: a tab switch.** Choosing a tab replaces the selected section in the open menu, synchronously in the control's action (no timers, no `RunLoop.main.perform`), and the menu's height changes: it grows or shrinks downward, and Quit and Settings move. The width doesn't change (§3.3). Any other change while the menu is open still only marks it for a rebuild on the next open.
- **Accessibility.** Give header switches `accessibilityLabel("Keep Awake")`. Give sliders the display name as label and "70 percent" as value.

### 3.5 Status items

- **Glyph.** An SF Symbol as a **template image** (`image.isTemplate = true`) so it adapts to light, dark, tinted and transparent menu bars. Start at about 15 pt `.regular` and compare it optically with the Wi-Fi glyph. The menu bar is 24 pt tall, and taller on notched Macs [S3].
  - Awake: `cup.and.saucer` when idle, `cup.and.saucer.fill` when active. A filled glyph for the active state matches Focus.
  - Displays: `sun.max`.
  - Snaptic combined item: a custom symbol, exported as a template.
- **Countdown (Awake).**
  - Set `statusItem.length = NSStatusItem.variableLength` and `button.imagePosition = .imageLeading`.
  - Draw the title with `NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)` so digits don't jitter.
  - Format as `h:mm` and update on minute boundaries, with timer tolerance about 1 s. Show seconds only under 1 minute, and only if the user opted in.
  - Indefinite sessions show the glyph only.
  - The accessibility label reads like "Awake, 1 hour 42 minutes remaining."
  - Off by default: Menu Bar › "Show time remaining".
- **Multiple items.** Give each a stable `autosaveName` so macOS remembers its position. Set `behavior = .removalAllowed` so ⌘-drag removes it, and observe `isVisible` to keep the setting in sync. Never depend on an item being visible. The system hides extras when space runs out [S3], and macOS 27 occlusion reporting is unreliable [S10]. Every action must also be available from Settings or a keyboard shortcut.

---

## 4. Copy rules

1. **Capitalization** (checked by `scripts/lint03.py` where it can be).
   - **Sentence case** [S6][S7]: setting labels, help text, section headers and footers, status rows, tooltips,
     alert messages, toasts, and radio-group labels ("For new resolutions", "Run both"). An alert's title is a
     sentence too ("Turn off virtual displays?").
   - **Title case** [S12]: menu items, buttons, window, sheet and pane titles ("Restore Defaults…", "Keep Awake For"),
     and the options of pop-up buttons, segmented controls and pull-downs, which are menu items in macOS ("HiDPI
     and Standard Sizes", "Display with the Pointer", "Until Turned Off"). Lowercase only articles, coordinating
     conjunctions and short prepositions after the first word (a, an, the, and, but, or, for, as, at, by, in, of,
     on, to, up, via, with, from, into, over, than). Text in parentheses or quotes keeps its own case.
   - **Exceptions.** Apple's own wording stays as Apple writes it: the Arrange sheet's "Use as" pop-up ("Main
     display", "Extended display", "Mirror for “…”"), as in System Settings. Event-hook "When" clauses ("A display
     connects") and Awake rule-condition pop-ups ("Safari" "is not" "open", "on battery") are sentence fragments and
     stay sentence case. `lint03.py` checks `PickerSetting` options and native `Picker` `Text(L(…))` options; its
     comment lists what it can't see.
   - **Names inside sentences.** A feature's label is sentence case ("Virtual displays"), so mid-sentence its first
     letter is lowercased: "Turn off virtual displays?", "Needs saved layouts." Proper names and acronyms keep their
     case ("Picture in Picture", "Night Shift controls", "HDR virtual modes"). Use Kit `SentenceText.inSentence`
     and `DisplaysUIText.inSentence`; for a sentence whose verb depends on the name use `DisplaysUIText.isOff` /
     `notAvailableNow` ("Keyboard shortcuts are off."), never `"\(title) is off."`. A label that is a verb phrase
     ("Turn displays off and on", "Sync brightness") is never lowercased into a sentence ("Needs turn displays off
     and on."): such a feature has a noun phrase in `DisplaysUIText.sentenceName` ("Needs display power control.",
     "This also turns off brightness sync."), and a Kit test checks every feature.
   - **Switch actions** (Keyboard Shortcuts, command list): a shortcut that turns something on or off is titled
     "<menu item> On or Off" ("Sync Brightness On or Off", "Show in Picture in Picture On or Off"), so the name in
     the menu finds its shortcut. An action that does two named things says both ("Pause or Resume Rules", "Hide or
     Show All Pictures in Picture"). A menu that knows the current state names the change instead ("Turn On HiDPI" /
     "Turn Off HiDPI"). Never "Toggle …".
   - **Destructive and Restore buttons name what they do**: "Delete Virtual Display…", "Delete All Hooks and
     Actions…", "Restore Defaults" (not "Delete…", "Restore"). A delete alert names the item in curly quotes
     ("Delete “Desk dock”?").
2. **Labels name the thing or the on-state, not the mechanism.** Write "Hardware brightness", not "Enable DDC brightness control". Don't write "Enable", "Disable" or "Allow X to Y". Switches turn things on or off. Toggle labels avoid verbs; buttons start with one [S9].
3. **Describe the on state and its consequence**, in one sentence of at most about 90 characters. For example: "Your Mac stays awake, but the display can sleep to save energy." [S9]
4. **Voice.** Never say "we". Use "your" sparingly [S9]. Say "Mac", not "computer". Say "click" for the pointer and "press" for keys. Use key names (Option, Command) or their symbols.
5. **Errors say what to do.** "Snaptic can't control this display's brightness. Try connecting it with DisplayPort or USB-C." Not "DDC failed".
6. **Typography and numbers.** Use the real ellipsis character (…). Write "20%" with no space, "60 Hz", "15 minutes" in prose and "15 min" in compact value labels, and "3:45 PM".
   - **Curly apostrophes and quotes** in every user-visible string (`L(…)` text): "Don’t Show", "Snaptic’s", and
     “name” around names. Never ' or straight double quotes; lint03 fails on a straight apostrophe in `L(…)` text.
     Strings that don't go through `L()` (log lines, shell commands to copy) keep ASCII.
   - **Serial comma** in every list of three or more: "Brightness, color, and resolution"; "names, window titles, or
     serial numbers". Two items take "and" with no comma. Lists built in code use Kit `SentenceText.list` ("A", "A
     and B", "A, B, and C"), never `joined(separator: ", ")` in a sentence.
7. **Terminology** (Apple words first):

| Avoid | Use |
|---|---|
| Monitor, screen | Display |
| Virtual screen | Virtual display |
| PIP | Picture in Picture |
| OSD | Brightness indicator |
| Layouts | Saved layouts (with an "Arrange…" sheet) |
| Automation / triggers | Change automatically / Start automatically, with "Add Condition…" |
| Prevent sleep / caffeinate | Keep Awake |
| Closed-lid, clamshell, disablesleep, Power Protect (0.3.1) | Keep awake with the lid closed; the noun is **lid-closed mode** ("Keep Awake with the Lid Closed…" in menus, "Keep awake with the lid closed" as a setting) |
| Diagnostics | Display Information… (Advanced) |
| Safety mode | Confirm display changes |
| Preferences | Settings |

---

## 5. Visual polish

- **Grid.** Use multiples of 4 pt (4/8/12/16/20). Don't add padding inside form rows; let `.grouped` set row height. Only the header row gets 4 pt of extra vertical padding.
- **Type.** Use system text styles only. `.headline` (13 pt bold) for header titles, `.body` (13 pt) for rows, subtitles and footers left to the form's secondary style (about 11 pt), and `.monospacedDigit()` for every live value. Don't use custom fonts or custom colors for text.
- **Color.**
  - Use semantic colors (`.primary`, `.secondary`, `.accentColor`, `NSColor.separatorColor`). Icon tiles are the only fixed colors.
  - Don't convey state by color alone. Pair it with a switch, a filled glyph or text [S4].
  - Check every page in light and dark mode, at Increase Contrast, and with every accent color.
- **Materials.**
  - Don't put custom materials in the content layer. HIG: "Don't use Liquid Glass in the content layer," and use glass effects sparingly [S15].
  - Get chrome from standard components: `NavigationSplitView`, the toolbar, `NSMenu`.
  - If a custom surface needs blur (such as a brightness indicator HUD), use `NSVisualEffectView` with a semantic material (`.hudWindow`, `.popover`). Swap it for an opaque `windowBackgroundColor` when `accessibilityDisplayShouldReduceTransparency` (SwiftUI: `\.accessibilityReduceTransparency`) is true.
- **Liquid Glass without the 26 SDK.**
  - Apps linked against older SDKs keep most pre-Tahoe window chrome on macOS 26. System-drawn UI (menu bar, menus, Control Center) uses the current look.
  - On macOS 27, all windows share one corner radius, and sidebars are edge-to-edge again even for apps that haven't been updated [S8][S16]. Golden Gate also adds a systemwide clear-to-tinted slider [S17].
  - So: no hard-coded window-matching radii, no fake glass, no custom title bars. Standard components then look right on 14, 15, 26 and 27.
  - When the toolchain moves to Xcode 26 or later, gate new APIs with `#if compiler(>=6.2)` plus `if #available(macOS 26, *)`. Both work in Swift 5 language mode. Candidates: `glassEffect`, `backgroundExtensionEffect`, `preferredImageVisibility`, `ControlWidget`, and on 27 `expandedInterfaceDelegate`.
- **Motion.** Crossfades of 0.15–0.2 s only. No springs or slides in Settings. With `\.accessibilityReduceMotion` on, skip animated scrolling and search-highlight pulses. A live brightness preview is feedback, not motion, so it stays.
- **Icons.**
  - SF Symbols at a weight that matches adjacent text.
  - In menus, use no images except device rows and, from 0.3.1, the tab bar's attention marks (see 3.3).
  - Sidebar tiles: 20 pt. Header tiles: 40 pt. Menu device tiles: 26 pt circles.

---

## Sources

- [S1] Apple HIG, Settings: https://developer.apple.com/design/human-interface-guidelines/settings
- [S2] Apple HIG, Sidebars (updated June 8, 2026): https://developer.apple.com/design/human-interface-guidelines/sidebars
- [S3] Apple HIG, The menu bar, "Menu bar extras": https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
- [S4] Apple HIG, Toggles: https://developer.apple.com/design/human-interface-guidelines/toggles
- [S5] Apple HIG, Disclosure controls: https://developer.apple.com/design/human-interface-guidelines/disclosure-controls
- [S6] Apple HIG, Sliders: https://developer.apple.com/design/human-interface-guidelines/sliders
- [S7] Apple HIG, Offering help (tooltips): https://developer.apple.com/design/human-interface-guidelines/offering-help
- [S8] 9to5Mac, "macOS 27 Golden Gate includes these changes that Tahoe critics will appreciate": https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/
- [S9] Apple HIG, Writing: https://developer.apple.com/design/human-interface-guidelines/writing
- [S10] Apple Developer Forums, "Various menu bar NSStatusItem issues with macOS 27": https://developer.apple.com/forums/thread/836113
- [S11] heise, "macOS 26 Tahoe: Menu bar confuses with double configurability": https://heise.de/-10733613
- [S12] Apple HIG, Menus (updated June 8, 2026): https://developer.apple.com/design/human-interface-guidelines/menus
- [S13] Michael Tsai, Golden Gate menu icons and `preferredImageVisibility`: https://mjtsai.com/blog/?p=52164
- [S14] Apple Developer Forums, "How does the system decide on NSMenuItem.ImageVisibility?": https://developer.apple.com/forums/thread/832718
- [S15] Apple HIG, Materials (Liquid Glass): https://developer.apple.com/design/human-interface-guidelines/materials
- [S16] MacStories, macOS 27 Golden Gate public beta preview: https://www.macstories.net/stories/macos-27-golden-gate-the-macstories-public-beta-preview/
- [S17] 9to5Mac, "macOS 27 gives you more control over Liquid Glass": https://9to5mac.com/2026/09/22/macos-27-gives-you-more-control-over-liquid-glass/
- Also: Objective Development, "Evanesco Iconia!" (Tahoe menu icons): https://obdev.at/blog/evanesco-iconia/ · Cindori, "Hands-on menu bar" (MenuBarExtra and NSHostingView in NSMenu): https://cindori.com/developer/hands-on-menu-bar

**Unverified, check on device:**
- That the macOS 26 and 27 menu appearance applies to apps built with the 15 SDK.
- The exact grouped-form footer spacing for the empty-`Section` footer trick.
- Whether sliders in `NSMenuItem` views take keyboard input.
- Window and column widths, which are approximate measurements of System Settings.

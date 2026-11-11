import SwiftUI
import SnapticKit

/// Hidden Icons › Sections (lead; PLAN 0.4 §4.9 Sections, G-7, X-21, A7): the apps under Shown, Hidden and Always
/// Hidden, live or (Native while the read is limited) as of the last unrestricted read. On macOS 27 each app has a
/// Where It Is / Always Show / Always Hide pop-up; on 14–26 the list is read-only. Without the permission the page
/// says what it needs and offers Open Privacy Settings. The rows come from `IconsPageRules.sections`.
struct IconsSectionsPage: View, ControlDeclaring {
    typealias Controls = IconsSectionsPageControls

    /// The Hidden Icons page's **Sections ›** row pushes this route.
    static let route = SettingsRoute(IconsSectionsPageControls.surface)

    let module: IconsModule

    var body: some View {
        if let host = SettingsShell.shared.host {
            IconsSectionsContent(module: module, host: host)
        } else {
            UnavailablePage()
        }
    }
}

private struct IconsSectionsContent: View {
    let module: IconsModule
    @ObservedObject private var host: ModuleHost
    /// Every unrestricted read stores the layout cache here, so the list follows the menu bar.
    @ObservedObject private var apps: ConfigStore<IconsAppsState>

    init(module: IconsModule, host: ModuleHost) {
        self.module = module
        _host = ObservedObject(wrappedValue: host)
        _apps = ObservedObject(wrappedValue: module.apps)
    }

    var body: some View {
        let running = host.isRunning(.hiddenIcons) && module.state == .running
        let engine = module.engineKind
        SettingsPageScaffold(route: IconsSectionsPage.route) {
            SettingsPageHeader(L("Sections"), summary: L("Which apps’ icons are shown, hidden, and always hidden."),
                               symbol: "rectangle.split.3x1", tint: .teal)
            if !running || engine == nil {
                Section {
                    StatusRow(L("Turn on Hidden Icons to see its sections."))
                }
            } else if module.accessState.needsPermission {
                Section {
                    StatusRow(engine == .native ? IconsPageRules.needsPermissionText
                                                : IconsPageRules.sectionsNoPermissionLength,
                              style: .warning, actions: [
                                  StatusAction(title: IconsStatusAction.openPrivacy.title,
                                               control: ControlID("icons.sections.openPrivacy")) {
                                      module.openPrivacy()
                                  },
                              ])
                }
            } else if let engine {
                listSections(engine)
            }
            PageFooterButtons(advanced: nil, help: IconsSectionsPage.route)
        }
    }

    // MARK: List

    @ViewBuilder private func listSections(_ engine: IconsEngineKind) -> some View {
        let list = module.sectionsList()
        let limited = module.layoutLimited
        ForEach([IconsSection.shown, .hidden, .alwaysHidden], id: \.self) { section in
            let rows = list.rows(section)
            Section {
                if rows.isEmpty {
                    Text(L("No icons"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.bundleID) { row in
                        appRow(row, engine: engine)
                    }
                }
            } header: {
                Text(IconsPageRules.sectionTitle(section))
            }
            .modifier(SectionsListAnchor(first: section == .shown))
        }
        Section {
            refreshButton(engine: engine, limited: limited)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if engine == .native, limited { Text(IconsPageRules.sectionsCachedFooter) }
                if engine == .length { Text(IconsPageRules.sectionsLengthFooter) }
                if engine == .native {
                    Text(IconsPageRules.sectionsChoiceHelp)
                        .modifier(SettingsAnchor(ControlID("icons.sections.choice")))
                }
                Text(IconsPageRules.sectionsSystemFooter)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func appRow(_ row: IconsSectionsRow, engine: IconsEngineKind) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
            if row.isNew {
                Text(L("New"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        if engine == .native, row.canChoose {
            Picker(selection: choiceBinding(row.bundleID, current: row.choice)) {
                ForEach(IconsPageRules.choiceOptions, id: \.1) { option in
                    Text(option.1).tag(option.0)
                }
            } label: {
                label
            }
            .pickerStyle(.menu)
        } else {
            label
        }
    }

    private func choiceBinding(_ bundle: String, current: IconsAppChoice?) -> Binding<IconsAppChoice?> {
        let module = self.module
        return Binding(get: { current }, set: { choice in
            if choice != current { module.setChoice(choice, for: bundle) }
        })
    }

    @ViewBuilder private func refreshButton(engine: IconsEngineKind, limited: Bool) -> some View {
        let module = self.module
        let title = IconsPageRules.refreshTitle(engine: engine, limited: limited)
        if engine == .native, limited {
            ButtonRow(title, symbol: "arrow.clockwise", control: ControlID("icons.sections.showAllAndRefresh")) {
                module.refreshLayout()
            }
        } else {
            ButtonRow(title, symbol: "arrow.clockwise", control: ControlID("icons.sections.refresh")) {
                module.refreshLayout()
            }
        }
    }
}

/// Search's "Icons in each section" lands on the first section.
private struct SectionsListAnchor: ViewModifier {
    let first: Bool

    func body(content: Content) -> some View {
        if first {
            content.modifier(SettingsAnchor(ControlID("icons.sections.list")))
        } else {
            content
        }
    }
}

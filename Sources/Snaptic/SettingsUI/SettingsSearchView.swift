import SwiftUI
import SnapticKit

/// Search results in the sidebar while the field has text: "Title — Page" rows, best first; choosing one calls
/// `SettingsShell.reveal` (the results stay, as in System Settings). No match: `ContentUnavailableView.search`.
struct SettingsSearchView: View {
    @ObservedObject var shell: SettingsShell

    var body: some View {
        let results = shell.searchResults
        if results.isEmpty {
            ContentUnavailableView.search(text: shell.searchText)
        } else {
            List(selection: selection(results)) {
                ForEach(results, id: \.id) { entry in
                    ResultRow(title: entry.title, page: shell.pageTitle(for: entry))
                        .tag(entry.id as String?)
                }
            }
        }
    }

    private func selection(_ results: [SettingsSearchEntry]) -> Binding<String?> {
        Binding(get: { shell.selectedResult },
                set: { id in
                    shell.selectedResult = id
                    if let id, let entry = results.first(where: { $0.id == id }) { shell.reveal(entry) }
                })
    }
}

private struct ResultRow: View {
    let title: String
    let page: String

    var body: some View {
        (Text(title) + Text(" — " + page).foregroundStyle(.secondary))
            .lineLimit(2)
            .accessibilityLabel(L("\(title), in \(page)"))
    }
}

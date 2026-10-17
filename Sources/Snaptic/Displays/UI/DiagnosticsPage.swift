import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SnapticKit

/// The Diagnostics page (PLAN §12): the report on screen, Copy and Export. Identifiers are
/// masked; the report never holds window titles, app names, serial numbers or EDID bytes.
struct DiagnosticsPage: View {
    @ObservedObject private var env: DisplaysPageEnvironment
    @State private var report: DiagnosticsReport?
    @State private var copied = false

    init(env: DisplaysPageEnvironment) {
        _env = ObservedObject(wrappedValue: env)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Button(L("Copy Report")) { copy() }
                    Button(L("Export…")) { export() }
                    Button(L("Refresh")) { refresh() }
                    if copied {
                        Label(L("Copied"), systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    }
                }
                Text(L("Attach the report when you file an issue. It has no window titles, app names or serial numbers, and identifiers are masked."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if env.context == nil {
                    Text(L("Displays is off, so the report only has system facts and recent events."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let report {
                ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
                    Section(section.title) {
                        if section.rows.isEmpty {
                            Text(L("Nothing to report")).foregroundStyle(.secondary)
                        }
                        ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                            LabeledContent(row.label) {
                                Text(row.value)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                Section(L("Recent events (\(report.events.count))")) {
                    if report.events.isEmpty {
                        Text(L("No events yet")).foregroundStyle(.secondary)
                    } else {
                        Text(report.events.suffix(60).joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        if report.events.count > 60 {
                            Text(L("The copied report has all \(report.events.count) events."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
    }

    private func refresh() {
        report = DiagnosticsController.makeReport(context: env.context, runtime: env.runtime)
        copied = false
    }

    private func copy() {
        refresh()
        guard let report else { return }
        DiagnosticsController.copyToClipboard(report.text)
        copied = true
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: L("Diagnostics report copied"),
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }

    private func export() {
        refresh()
        guard let text = report?.text else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Snaptic Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                EventLog.shared.record(.modules, "Diagnostics export failed")
            }
        }
    }
}

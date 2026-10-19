import AppKit
import SwiftUI
import SnapticKit

/// Settings › Permissions (H; PLAN 0.3 §4.3): one row per permission (state, what it allows, who needs it, Open
/// Privacy Settings…), the Removable Volumes note while Drive Alive is on, and this copy of Snaptic: location with
/// Show in Finder, signer (0.2 R5.7) and Relaunch Snaptic.
struct PermissionsPage: View, ControlDeclaring {
    typealias Controls = PermissionsPageControls
    @ObservedObject var host: ModuleHost

    var body: some View {
        PermissionsPageContent(host: host, permissions: host.permissions, awake: host.awakeStore)
    }
}

private struct PermissionsPageContent: View {
    @ObservedObject var host: ModuleHost
    @ObservedObject var permissions: PermissionFlow
    @ObservedObject var awake: ConfigStore<AwakeConfig>
    /// Read once per appearance: the signer and folder checks touch the file system.
    @State private var copy: CopyFacts?

    private struct CopyFacts {
        let path: String
        let signer: String
        let userWritable: Bool
        let translocated: Bool
    }

    var body: some View {
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.permissions)) {
            SettingsPageHeader(L("Permissions"), summary: L("What Snaptic may do on your Mac, and which features need it."),
                               symbol: "hand.raised.fill", tint: .blue)
            Section {
                PermissionStateRow(permission: .accessibility, granted: permissions.granted.contains(.accessibility),
                                   neededBy: neededBy(.accessibility),
                                   open: { permissions.presentGuide(.accessibility) })
                    .modifier(SettingsAnchor(ControlID("permissions.page.accessibility")))
                PermissionStateRow(permission: .screenRecording, granted: permissions.granted.contains(.screenRecording),
                                   neededBy: neededBy(.screenRecording),
                                   open: { permissions.presentGuide(.screenRecording) })
                    .modifier(SettingsAnchor(ControlID("permissions.page.screenRecording")))
                if driveAliveOn {
                    LabeledContent {
                        EmptyView()
                    } label: {
                        Text(L("Removable volumes"))
                        Text(L("macOS asks the first time Snaptic writes to a drive. Needed by Awake."))
                    }
                }
            } footer: {
                Text(L("Snaptic asks only for what the features you turn on need. After you allow something, macOS may ask Snaptic to quit and reopen."))
                    .foregroundStyle(.secondary)
            }
            Section {
                if let copy {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(copy.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                            Button(L("Show in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: copy.path)])
                            }
                            .fixedSize()
                            .modifier(SettingsAnchor(ControlID("permissions.page.showInFinder")))
                        }
                    } label: {
                        Text(L("Location"))
                    }
                    LabeledContent(L("Signed by")) {
                        Text(copy.signer)
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                    if copy.translocated {
                        StatusRow(L("Snaptic is running from a temporary location. Move it to Applications before you allow anything."),
                                  style: .warning)
                    } else if copy.userWritable {
                        StatusRow(L("Your account can change this folder, so another app could replace Snaptic and keep its permissions. Use a signed release, or install Snaptic in /Applications with an administrator account."),
                                  style: .warning)
                    }
                }
                ButtonRow(L("Relaunch Snaptic"), help: L("Quits and opens Snaptic again, so macOS applies a new permission."),
                          control: ControlID("permissions.page.relaunch")) {
                    host.relauncher.relaunch(reason: "permissions page")
                }
            } header: {
                Text(L("This copy of Snaptic"))
            }
        }
        .onAppear {
            permissions.refresh()
            copy = CopyFacts(path: PermissionFlow.bundlePath, signer: PermissionFlow.signer,
                             userWritable: PermissionFlow.bundleIsUserWritable, translocated: PermissionFlow.isTranslocated)
        }
    }

    private var driveAliveOn: Bool {
        host.isRunning(.awake) && awake.value.features[.driveAlive] == true
    }

    /// The running modules whose current settings need `permission`.
    private func neededBy(_ permission: Permission) -> String {
        let names = host.modules.filter { host.isRunning($0.id) && $0.requiredPermissions.contains(permission) }.map { $0.title }
        return SettingsText.neededBy(names)
    }
}

/// A permission: its System Settings name, what it allows and who needs it; trailing "Allowed" or the button that
/// opens Snaptic's guide to the privacy pane.
private struct PermissionStateRow: View {
    let permission: Permission
    let granted: Bool
    let neededBy: String
    let open: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text(L("Allowed"))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(L("Open Privacy Settings…"), action: open)
                    .fixedSize()
            }
        } label: {
            Text(PermissionFlow.paneName(permission))
            Text(PermissionFlow.purpose(permission) + " " + neededBy)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(granted ? L("Allowed") : L("Not allowed"))
    }
}

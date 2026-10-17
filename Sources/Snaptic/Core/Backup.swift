import AppKit
import SnapticKit
import UniformTypeIdentifiers

/// Settings export and import (PLAN §3.4). Exports leave out hooks, actions, CLI settings,
/// the DisplayKey salt, DDC unlocks, "Allow without asking" flags, preset trust and the
/// sensitive toggles (Kit `KitBackup`); imports strip the same fields even if present, keep
/// the current values for them, show what would change, and apply only after a yes.
/// Picked files follow §4.10(6): O_NONBLOCK|O_NOFOLLOW, a regular file, ≤ 1 MB, read off main.
@MainActor enum Backup {
    static let fileExtension = "snapticbackup"

    // MARK: Export

    static func export(host: ModuleHost) {
        guard let document = makeDocument(host: host) else {
            host.toasts.show(L("The settings couldn't be exported."))
            return
        }
        let panel = NSSavePanel()
        panel.title = L("Export Snaptic Settings")
        panel.nameFieldStringValue = "Snaptic Settings." + fileExtension
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .json]
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try document.write(to: url, options: [.atomic])
            EventLog.shared.record(.modules, "Settings exported")
            host.toasts.show(L("Settings exported."))
        } catch {
            host.toasts.show(L("The settings couldn't be saved there."))
        }
    }

    static func makeDocument(host: ModuleHost) -> Data? {
        let encoder = JSONEncoder()
        var sections: [String: Data] = [:]
        if let data = try? encoder.encode(host.switcherSettings.config) { sections[KitBackup.switcherSection] = data }
        if let data = try? encoder.encode(host.modulesStore.value) { sections[KitBackup.modulesSection] = data }
        if let data = try? encoder.encode(host.displaysStore.value) { sections[KitBackup.displaysSection] = data }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let created = ISO8601DateFormatter().string(from: Date())
        return KitBackup.makeDocument(sections: sections, created: created, appVersion: version)
    }

    // MARK: Import

    static func `import`(host: ModuleHost) {
        let panel = NSOpenPanel()
        panel.title = L("Import Snaptic Settings")
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        Task { @MainActor [weak host] in
            let result = await Task.detached(priority: .userInitiated) { Backup.readPickedFile(path) }.value
            guard let host else { return }
            switch result {
            case .failure(let error):
                host.toasts.show(error.message)
            case .success(let data):
                preview(data, host: host)
            }
        }
    }

    /// §4.10(6): no symlinks, regular file only, ≤ 1 MB, never blocks on a FIFO.
    nonisolated static func readPickedFile(_ path: String) -> Result<Data, BackupFileError> {
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return .failure(BackupFileError(L("The file couldn't be opened."))) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            return .failure(BackupFileError(L("That isn't a regular file.")))
        }
        guard info.st_size <= off_t(KitBackup.maxBytes) else { return .failure(BackupFileError(BackupError.tooLarge.message)) }
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while data.count <= KitBackup.maxBytes {
            let n = chunk.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { break }
            data.append(contentsOf: chunk[0..<n])
        }
        guard data.count <= KitBackup.maxBytes else { return .failure(BackupFileError(BackupError.tooLarge.message)) }
        return .success(data)
    }

    /// Decodes, merges over the current settings, shows what changes, applies on a yes.
    private static func preview(_ data: Data, host: ModuleHost) {
        let sections: [String: Data]
        switch KitBackup.parseDocument(data) {
        case .success(let parsed): sections = parsed
        case .failure(let error):
            host.toasts.show(error.message)
            return
        }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var changes: [String] = []
        var newSwitcher: Config?
        var newModules: ModulesConfig?
        var newDisplays: DisplaysConfig?

        if let imported = sections[KitBackup.switcherSection], let current = try? encoder.encode(host.switcherSettings.config),
           let merged = KitBackup.merge(current: current, imported: imported),
           let value = try? decoder.decode(Config.self, from: merged) {
            let clean = value.sanitized()
            if let after = try? encoder.encode(clean) {
                changes += KitBackup.changedPaths(from: current, to: after).map { L("Window Switcher: ") + $0 }
            }
            newSwitcher = clean
        }
        if let imported = sections[KitBackup.modulesSection], let current = try? encoder.encode(host.modulesStore.value),
           let merged = KitBackup.merge(current: current, imported: imported),
           let value = try? decoder.decode(ModulesConfig.self, from: merged) {
            let clean = value.sanitized()
            if let after = try? encoder.encode(clean) {
                changes += KitBackup.changedPaths(from: current, to: after).map { L("Modules: ") + $0 }
            }
            newModules = clean
        }
        if let imported = sections[KitBackup.displaysSection], let current = try? encoder.encode(host.displaysStore.value),
           let merged = KitBackup.merge(current: current, imported: imported),
           let value = try? decoder.decode(DisplaysConfig.self, from: merged) {
            let clean = value.sanitized()
            if let after = try? encoder.encode(clean) {
                changes += KitBackup.changedPaths(from: current, to: after).map { L("Displays: ") + $0 }
            }
            newDisplays = clean
        }
        guard !changes.isEmpty else {
            host.toasts.show(L("The backup matches your current settings."))
            return
        }

        let alert = NSAlert()
        alert.messageText = L("Import these settings?")
        let shown = changes.prefix(15).joined(separator: "\n")
        let more = changes.count > 15 ? "\n" + L("…and ") + String(changes.count - 15) + L(" more") : ""
        alert.informativeText = L("These settings change:") + "\n\n" + shown + more + "\n\n"
            + L("Hooks, actions, command-line settings and protected display settings are never imported.")
        alert.addButton(withTitle: L("Import"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let newSwitcher { host.switcherSettings.config = newSwitcher }
        if let newModules { host.modulesStore.value = newModules }
        if let newDisplays { host.displaysStore.value = newDisplays }
        EventLog.shared.record(.modules, "Settings imported: \(changes.count) changes")
        host.toasts.show(L("Settings imported."))
    }
}

struct BackupFileError: Error, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
}

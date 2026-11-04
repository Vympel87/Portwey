import AppKit
import LauncherCore

/// Removes Portwey and everything it created. macOS doesn't let apps run code when they're dragged
/// to the Trash, so this is the only way to clean up properly.
@MainActor
enum Uninstaller {
    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Portwey"
    }

    /// Everything Portwey (or macOS on its behalf) creates outside the app itself.
    static var leftoverLocations: [URL] {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return [
            AppPaths.root,
            library.appendingPathComponent("Caches/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("Saved Application State/\(bundleID).savedState", isDirectory: true)
        ]
    }

    /// True for a copy installed from the DMG, false when running from Xcode.
    static var isInstalledCopy: Bool {
        let path = Bundle.main.bundleURL.path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/"
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications)
    }

    static func confirmAndUninstall(runner: GameRunner, setup: SetupManager) async {
        let size = await BottleManager.diskSize(of: AppPaths.root)
        let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Uninstall Portwey?"
        alert.informativeText = """
        This removes Portwey and everything it downloaded or created (\(sizeText)):

        • Wine, DXVK, DXMT, NW.js and Godot
        • All bottles, including game saves stored inside them
        • Games imported from .zip files, covers and your library
        • Portwey's settings and caches

        Games you added from other folders stay where they are. This can't be undone.
        """
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // 1. Stop the running game and every Wine process, so nothing is holding files open.
        await runner.stop()
        if let runtime = setup.runtime {
            for bottle in BottleManager.listBottles() {
                await BottleManager.killAll(in: bottle.url, runtime: runtime)
            }
        }

        // 2. Delete data, caches and settings.
        let fm = FileManager.default
        for location in leftoverLocations where fm.fileExists(atPath: location.path) {
            try? fm.removeItem(at: location)
        }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        // 3. Move the app itself to the Trash (not when running from Xcode).
        if isInstalledCopy {
            _ = try? await NSWorkspace.shared.recycle([Bundle.main.bundleURL])
        } else {
            let done = NSAlert()
            done.messageText = "Portwey's data was removed"
            done.informativeText = "This copy is running from Xcode, so the app itself wasn't moved to the Trash."
            done.runModal()
        }

        // 4. Quit immediately, so nothing (window positions, the library) gets written back after the cleanup.
        exit(0)
    }
}

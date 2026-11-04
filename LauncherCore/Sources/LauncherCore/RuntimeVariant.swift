import Foundation

/// Builds a modified copy of a Wine runtime without touching the original.
/// The copy is an APFS clone, so it's near-instant and barely uses extra disk space.
enum RuntimeVariant {
    static func make(
        base: RuntimeInfo,
        suffix: String,
        label: String,
        log: @Sendable (String) -> Void,
        customize: (_ wineLib: URL) throws -> Void
    ) async throws -> RuntimeInfo {
        let fm = FileManager.default
        let baseDirectory = URL(fileURLWithPath: base.installPath)
        let variantName = "\(baseDirectory.lastPathComponent)-\(suffix)"
        let variantDirectory = AppPaths.runtimes.appendingPathComponent(variantName, isDirectory: true)

        guard base.wineBinaryPath.hasPrefix(base.installPath) else {
            throw LauncherError.unexpectedRuntimeLayout(base.wineBinaryPath)
        }
        let relativeBinaryPath = String(base.wineBinaryPath.dropFirst(base.installPath.count))
        let variantBinary = URL(fileURLWithPath: variantDirectory.path + relativeBinaryPath)

        let variant = RuntimeInfo(
            tag: variantName,
            version: "\(base.version) + \(label)",
            installPath: variantDirectory.path,
            wineBinaryPath: variantBinary.path
        )

        // Already prepared earlier.
        let readyMarker = variantDirectory.appendingPathComponent(".portwey-ready")
        if fm.fileExists(atPath: readyMarker.path), fm.isExecutableFile(atPath: variantBinary.path) {
            return variant
        }

        log("Preparing a \(label) copy of Wine (one-time)…")
        if fm.fileExists(atPath: variantDirectory.path) {
            try fm.removeItem(at: variantDirectory)
        }

        // -c: APFS clone, -R: recursive, -p: keep timestamps (so Wine doesn't think the prefix needs updating).
        try await Shell.runChecked("/bin/cp", ["-cRp", baseDirectory.path, variantDirectory.path])

        // .../wine/bin/wine → .../wine/lib/wine
        let wineLib = variantBinary
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("lib/wine", isDirectory: true)
        guard fm.fileExists(atPath: wineLib.path) else {
            throw LauncherError.unexpectedRuntimeLayout(wineLib.path)
        }

        try customize(wineLib)

        // We changed files inside the app bundle, so re-sign it ad-hoc to keep macOS happy.
        let contents = (try? fm.contentsOfDirectory(at: variantDirectory, includingPropertiesForKeys: nil)) ?? []
        if let appBundle = contents.first(where: { $0.pathExtension == "app" }) {
            _ = try? await Shell.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appBundle.path])
        }

        try "ready".write(to: readyMarker, atomically: true, encoding: .utf8)
        log("\(label) copy of Wine is ready ✓")
        return variant
    }

    /// Copies files with the given extensions, replacing ones that already exist.
    static func copyFiles(from source: URL, to destination: URL, extensions: Set<String>) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let files = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for file in files where extensions.contains(file.pathExtension.lowercased()) {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: file, to: target)
        }
    }
}

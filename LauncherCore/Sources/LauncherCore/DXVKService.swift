import Foundation

public struct DXVKInfo: Codable, Sendable, Equatable {
    public let tag: String
    public let x64Path: String
    public let x32Path: String?
    public let dllNames: [String]

    public var x64URL: URL { URL(fileURLWithPath: x64Path) }
    public var x32URL: URL? { x32Path.map { URL(fileURLWithPath: $0) } }
}

public enum DXVKService {
    public static let owner = "Gcenx"
    public static let repo = "DXVK-macOS"

    static var rootDirectory: URL { AppPaths.runtimes.appendingPathComponent("dxvk", isDirectory: true) }
    static var infoFile: URL { AppPaths.runtimes.appendingPathComponent("dxvk.json") }

    private static let readyMarkerName = ".portwey-ready"
    private static let overridableDLLs = ["d3d9", "d3d10core", "d3d10", "d3d10_1", "d3d11", "dxgi"]

    // MARK: - Installed state

    public static func installed() -> DXVKInfo? {
        guard
            let data = try? Data(contentsOf: infoFile),
            let info = try? JSONDecoder().decode(DXVKInfo.self, from: data),
            FileManager.default.fileExists(atPath: info.x64Path)
        else { return nil }
        return info
    }

    public static func save(_ info: DXVKInfo) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(info)
        try data.write(to: infoFile, options: .atomic)
    }

    // MARK: - Download & extract

    public static func pickAsset(from release: GitHubRelease) throws -> GitHubRelease.Asset {
        let archives = release.assets.filter { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.xz") || name.hasSuffix(".zip")
        }
        let dxvkArchives = archives.filter { $0.name.lowercased().contains("dxvk") }

        // Prefer the regular build, but the async build is fine too.
        if let regular = dxvkArchives.first(where: { !$0.name.lowercased().contains("async") }) {
            return regular
        }
        if let any = dxvkArchives.first ?? archives.first {
            return any
        }
        throw LauncherError.noDXVKAssetFound
    }

    public static func extract(archive: URL, tag: String) async throws -> DXVKInfo {
        let destination = rootDirectory.appendingPathComponent(sanitize(tag), isDirectory: true)
        let fm = FileManager.default

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        try await Shell.runChecked("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path])
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])

        return try makeInfo(from: destination, tag: tag)
    }

    static func makeInfo(from directory: URL, tag: String) throws -> DXVKInfo {
        // Regular packages use x64/x32. "-builtin" packages mirror Wine's lib layout.
        guard let x64 = findDirectory(named: "x64", in: directory)
            ?? findDirectory(named: "x86_64-windows", in: directory) else {
            throw LauncherError.dxvkLayoutNotFound
        }
        let x32 = findDirectory(named: "x32", in: directory)
            ?? findDirectory(named: "i386-windows", in: directory)

        let names = try dllNames(in: x64).filter { overridableDLLs.contains($0) }
        guard !names.isEmpty else {
            throw LauncherError.dxvkLayoutNotFound
        }
        return DXVKInfo(tag: tag, x64Path: x64.path, x32Path: x32?.path, dllNames: names.sorted())
    }

    // MARK: - DXVK runtime variant

    /// Returns a copy of the Wine runtime with DXVK placed inside Wine's own DLL folders.
    /// The copy is an APFS clone, so it's near-instant and barely uses extra disk space.
    /// The original runtime stays untouched, so games can still choose WineD3D.
    public static func runtimeVariant(
        base: RuntimeInfo,
        dxvk: DXVKInfo,
        log: @Sendable (String) -> Void
    ) async throws -> RuntimeInfo {
        let fm = FileManager.default
        let baseDirectory = URL(fileURLWithPath: base.installPath)
        let variantName = "\(baseDirectory.lastPathComponent)-dxvk-\(sanitize(dxvk.tag))"
        let variantDirectory = AppPaths.runtimes.appendingPathComponent(variantName, isDirectory: true)

        guard base.wineBinaryPath.hasPrefix(base.installPath) else {
            throw LauncherError.unexpectedRuntimeLayout(base.wineBinaryPath)
        }
        let relativeBinaryPath = String(base.wineBinaryPath.dropFirst(base.installPath.count))
        let variantBinary = URL(fileURLWithPath: variantDirectory.path + relativeBinaryPath)

        let variant = RuntimeInfo(
            tag: variantName,
            version: "\(base.version) + DXVK \(dxvk.tag)",
            installPath: variantDirectory.path,
            wineBinaryPath: variantBinary.path
        )

        // Already prepared earlier.
        let readyMarker = variantDirectory.appendingPathComponent(readyMarkerName)
        if fm.fileExists(atPath: readyMarker.path), fm.isExecutableFile(atPath: variantBinary.path) {
            return variant
        }

        log("Preparing a DXVK copy of Wine (one-time)…")
        if fm.fileExists(atPath: variantDirectory.path) {
            try fm.removeItem(at: variantDirectory)
        }

        // -c: APFS clone, -R: recursive, -p: keep timestamps (so Wine doesn't think the prefix needs updating).
        try await Shell.runChecked("/bin/cp", ["-cRp", baseDirectory.path, variantDirectory.path])

        // .../wine/bin/wine → .../wine/lib/wine/{x86_64-windows,i386-windows}
        let wineRoot = variantBinary.deletingLastPathComponent().deletingLastPathComponent()
        let wineLib = wineRoot.appendingPathComponent("lib/wine", isDirectory: true)
        let x64Target = wineLib.appendingPathComponent("x86_64-windows", isDirectory: true)
        let i386Target = wineLib.appendingPathComponent("i386-windows", isDirectory: true)

        guard fm.fileExists(atPath: x64Target.path) else {
            throw LauncherError.unexpectedRuntimeLayout(x64Target.path)
        }

        try copyDLLs(from: dxvk.x64URL, to: x64Target)
        if let x32 = dxvk.x32URL, fm.fileExists(atPath: i386Target.path) {
            try copyDLLs(from: x32, to: i386Target)
        }

        // We changed files inside the app bundle, so re-sign it ad-hoc to keep macOS happy.
        if let appBundle = findAppBundle(in: variantDirectory) {
            _ = try? await Shell.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appBundle.path])
        }

        try "ready".write(to: readyMarker, atomically: true, encoding: .utf8)
        log("DXVK copy of Wine is ready ✓")
        return variant
    }

    /// Extra environment variables for games running with DXVK.
    public static func environment(for bottle: URL) -> [String: String] {
        let cache = bottle.appendingPathComponent("dxvk-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return [
            // "info" for now so we can confirm DXVK is really loaded. Switch to "warn" later.
            "DXVK_LOG_LEVEL": "info",
            "DXVK_STATE_CACHE_PATH": cache.path
        ]
    }

    // MARK: - Helpers

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "-")
    }

    private static func copyDLLs(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let files = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension.lowercased() == "dll" {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: file, to: target)
        }
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    private static func findDirectory(named name: String, in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        while let url = enumerator.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory && url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }

    private static func dllNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "dll" }
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() }
    }
}

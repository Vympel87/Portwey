import Foundation

public struct BottleInfo: Identifiable, Sendable, Hashable {
    public let name: String
    public let url: URL

    public var id: String { name }
}

public enum BottleManager {
    public static let defaultBottleName = "default"

    public static func bottleURL(named name: String) -> URL {
        AppPaths.bottles.appendingPathComponent(name, isDirectory: true)
    }

    /// Name for a bottle that belongs to a single game.
    public static func ownBottleName(for gameID: UUID) -> String {
        "game-" + gameID.uuidString.prefix(8).lowercased()
    }

    /// A bottle is considered ready once Wine has created its registry file.
    public static func isInitialized(_ bottle: URL) -> Bool {
        FileManager.default.fileExists(atPath: bottle.appendingPathComponent("system.reg").path)
    }

    public static func environment(for bottle: URL, extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.path
        env["WINEDEBUG"] = "fixme-all"
        // MoltenVK: only log errors (0 = none, 1 = errors, 2 = warnings, 3 = info).
        env["MVK_CONFIG_LOG_LEVEL"] = "1"
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }

    /// Creates the bottle on first use. Later calls return immediately.
    public static func ensureBottle(
        named name: String,
        runtime: RuntimeInfo,
        log: @Sendable (String) -> Void
    ) async throws -> URL {
        let bottle = bottleURL(named: name)
        if isInitialized(bottle) {
            return bottle
        }

        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        log("Creating Windows environment (bottle '\(name)'). The first time can take a minute…")

        // Disable the Mono/Gecko install prompts during first boot.
        try await Shell.runChecked(
            runtime.wineBinaryPath,
            ["wineboot", "--init"],
            environment: [
                "WINEPREFIX": bottle.path,
                "WINEDEBUG": "-all",
                "WINEDLLOVERRIDES": "mscoree=d;mshtml=d"
            ]
        )

        guard isInitialized(bottle) else {
            throw LauncherError.bottleCreationFailed
        }
        log("Bottle '\(name)' is ready ✓")
        return bottle
    }

    // MARK: - Management

    /// All bottles on disk, with the shared default bottle first.
    public static func listBottles() -> [BottleInfo] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: AppPaths.bottles,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { BottleInfo(name: $0.lastPathComponent, url: $0) }
            .sorted { lhs, rhs in
                if lhs.name == defaultBottleName { return true }
                if rhs.name == defaultBottleName { return false }
                return lhs.name < rhs.name
            }
    }

    /// Space the bottle takes on disk. Symlinks (like the Z: drive pointing at /) are not followed.
    public static func diskSize(of bottle: URL) async -> Int64 {
        await Task.detached(priority: .utility) {
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
            guard let enumerator = FileManager.default.enumerator(at: bottle, includingPropertiesForKeys: keys) else {
                return 0
            }
            var total: Int64 = 0
            while let url = enumerator.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == true {
                    total += Int64(values?.totalFileAllocatedSize ?? 0)
                }
            }
            return total
        }.value
    }

    /// Stops everything running in the bottle, then deletes it. It's recreated the next time a game needs it.
    public static func deleteBottle(named name: String, runtime: RuntimeInfo?) async throws {
        let url = bottleURL(named: name)
        if let runtime {
            await killAll(in: url, runtime: runtime)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Opens Wine's own settings window for the bottle.
    public static func openWinecfg(in bottle: URL, runtime: RuntimeInfo) throws {
        let process = Process()
        process.executableURL = runtime.wineBinaryURL
        process.arguments = ["winecfg"]
        process.environment = environment(for: bottle)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    public static func wineserverURL(for runtime: RuntimeInfo) -> URL {
        runtime.wineBinaryURL.deletingLastPathComponent().appendingPathComponent("wineserver")
    }

    /// Kills every Wine process running inside the bottle.
    public static func killAll(in bottle: URL, runtime: RuntimeInfo) async {
        _ = try? await Shell.run(
            wineserverURL(for: runtime).path,
            ["-k"],
            environment: ["WINEPREFIX": bottle.path]
        )
    }
}

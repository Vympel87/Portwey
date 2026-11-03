import Foundation

public enum BottleManager {
    public static let defaultBottleName = "default"

    public static func bottleURL(named name: String) -> URL {
        AppPaths.bottles.appendingPathComponent(name, isDirectory: true)
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

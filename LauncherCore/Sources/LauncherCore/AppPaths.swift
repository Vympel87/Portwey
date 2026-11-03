import Foundation

public enum AppPaths {
    public static let appName = "Portwey"

    public static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    public static var runtimes: URL { root.appendingPathComponent("runtimes", isDirectory: true) }
    public static var bottles: URL { root.appendingPathComponent("bottles", isDirectory: true) }
    public static var downloads: URL { root.appendingPathComponent("downloads", isDirectory: true) }
    public static var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    public static var runtimeInfoFile: URL { runtimes.appendingPathComponent("current.json") }
    public static var libraryFile: URL { root.appendingPathComponent("library.json") }

    public static func ensureDirectories() throws {
        for dir in [root, runtimes, bottles, downloads, logs] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

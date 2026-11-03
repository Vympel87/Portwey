import Foundation

public struct NWJSInfo: Codable, Sendable, Equatable {
    public let version: String
    public let appPath: String

    public var executableURL: URL {
        URL(fileURLWithPath: appPath).appendingPathComponent("Contents/MacOS/nwjs")
    }
}

public enum NWJSService {
    static let manifestURL = URL(string: "https://nwjs.io/versions.json")!
    static var rootDirectory: URL { AppPaths.runtimes.appendingPathComponent("nwjs", isDirectory: true) }
    static var infoFile: URL { AppPaths.runtimes.appendingPathComponent("nwjs.json") }

    static let compatShimFileName = "portwey-compat.js"
    static let backupSuffix = ".portwey-backup"

    static var platformTag: String {
        #if arch(arm64)
        return "osx-arm64"
        #else
        return "osx-x64"
        #endif
    }

    private struct Manifest: Decodable {
        let latest: String?
        let stable: String?
        let versions: [Version]

        struct Version: Decodable {
            let version: String
            let files: [String]?
        }
    }

    // MARK: - Installed state

    public static func installed() -> NWJSInfo? {
        guard
            let data = try? Data(contentsOf: infoFile),
            let info = try? JSONDecoder().decode(NWJSInfo.self, from: data),
            FileManager.default.isExecutableFile(atPath: info.executableURL.path)
        else { return nil }
        return info
    }

    /// Returns the installed NW.js, downloading it first if needed.
    public static func ensureInstalled(log: @escaping @Sendable (String) -> Void) async throws -> NWJSInfo {
        if let existing = installed() {
            return existing
        }

        try AppPaths.ensureDirectories()
        log("NW.js for macOS isn't installed yet, downloading it (one-time)…")
        let version = try await latestVersion()
        let fileName = "nwjs-\(version)-\(platformTag).zip"
        guard let url = URL(string: "https://dl.nwjs.io/\(version)/\(fileName)") else {
            throw LauncherError.nwjsUnavailable
        }
        log("NW.js \(version): \(url.absoluteString)")

        // Reuse the GitHub asset downloader. Size -1 means "unknown", so it always downloads.
        let asset = GitHubRelease.Asset(name: fileName, browserDownloadUrl: url, size: -1)
        let archive = AppPaths.downloads.appendingPathComponent(fileName)
        try await WineRuntimeService.download(asset: asset, to: archive) { value in
            let percent = Int(value * 100)
            if percent % 10 == 0 {
                log("Downloading NW.js… \(percent)%")
            }
        }

        log("Extracting NW.js…")
        let destination = rootDirectory.appendingPathComponent(version, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await Shell.runChecked("/usr/bin/ditto", ["-x", "-k", archive.path, destination.path])
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
        try? FileManager.default.removeItem(at: archive)

        guard let app = findNWJSApp(in: destination) else {
            throw LauncherError.nwjsAppNotFound
        }

        let info = NWJSInfo(version: version, appPath: app.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: infoFile, options: .atomic)
        log("NW.js \(version) is ready ✓")
        return info
    }

    /// Picks the stable (or latest) version that has a build for this Mac.
    static func latestVersion() async throws -> String {
        var request = URLRequest(url: manifestURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Portwey", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LauncherError.nwjsUnavailable
        }

        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            let preview = String(decoding: data.prefix(200), as: UTF8.self)
            throw LauncherError.downloadFailed("NW.js version list has an unexpected format: \(preview)")
        }

        func hasMacBuild(_ version: String) -> Bool {
            manifest.versions.first(where: { $0.version == version })?.files?.contains(platformTag) == true
        }

        for candidate in [manifest.stable, manifest.latest].compactMap({ $0 }) where hasMacBuild(candidate) {
            return candidate
        }
        if let any = manifest.versions.first(where: { $0.files?.contains(platformTag) == true }) {
            return any.version
        }
        throw LauncherError.nwjsUnavailable
    }

    // MARK: - Game folder

    /// Makes an old NW.js game (RPG Maker MV/MZ) run on a modern NW.js:
    /// 1. Fills in an empty "name" in package.json (newer NW.js refuses to start without it).
    /// 2. Adds a small compatibility script that runs before the game's own scripts.
    /// Every file we change is backed up once as "<file>.portwey-backup".
    public static func prepareGameFolder(
        _ folder: URL,
        fallbackName: String,
        log: (String) -> Void
    ) throws {
        let packageURL = folder.appendingPathComponent("package.json")
        guard
            let data = try? Data(contentsOf: packageURL),
            var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw LauncherError.packageJSONMissing(packageURL.path)
        }

        // 1. Name
        let currentName = (json["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        if currentName.isEmpty {
            try backupOnce(packageURL)
            json["name"] = slug(fallbackName)
            let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: packageURL, options: .atomic)
            log("Gave package.json a name so NW.js can start it (original saved as package.json\(backupSuffix))")
        }

        // 2. Compatibility shim next to the main HTML page ("www/index.html" for MV, "index.html" for MZ)
        let mainPath = (json["main"] as? String) ?? "index.html"
        try installCompatShim(nextTo: folder.appendingPathComponent(mainPath), log: log)
    }

    /// Writes portwey-compat.js and loads it from the game's HTML page before any other script.
    static func installCompatShim(nextTo htmlURL: URL, log: (String) -> Void) throws {
        guard
            htmlURL.pathExtension.lowercased().hasPrefix("htm"),
            var html = try? String(contentsOf: htmlURL, encoding: .utf8)
        else { return }

        // Always refresh the shim so games get the newest fixes.
        let shimURL = htmlURL.deletingLastPathComponent().appendingPathComponent(compatShimFileName)
        try compatShimSource.write(to: shimURL, atomically: true, encoding: .utf8)

        guard !html.contains(compatShimFileName) else { return }

        let tag = "<script type=\"text/javascript\" src=\"\(compatShimFileName)\"></script>\n        "
        if let firstScript = html.range(of: "<script", options: .caseInsensitive) {
            html.insert(contentsOf: tag, at: firstScript.lowerBound)
        } else if let headEnd = html.range(of: "</head>", options: .caseInsensitive) {
            html.insert(contentsOf: tag, at: headEnd.lowerBound)
        } else {
            return
        }

        try backupOnce(htmlURL)
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)
        log("Added Portwey's compatibility fixes for older NW.js games (original saved as \(htmlURL.lastPathComponent)\(backupSuffix))")
    }

    /// Fixes for APIs that old NW.js games use but modern NW.js removed or changed.
    static let compatShimSource = #"""
    // Portwey compatibility shim for games built on old NW.js (RPG Maker MV/MZ).
    // Loaded before the game's own scripts. Safe to delete; Portwey re-creates it on launch.

    // 1. Version checks done as text.
    // Old plugins do things like: process.versions['node-webkit'] >= "0.13.0"
    // Compared as text, "0.119.2" is "smaller" than "0.13.0", so modern NW.js gets treated as ancient.
    (function () {
      'use strict';
      if (typeof process === 'undefined' || !process.versions) {
        return;
      }
      var real = process.versions['node-webkit'] || process.versions.nw;
      if (!real || real >= '0.13.0') {
        return; // missing, or the text comparison already gives the right answer
      }
      var parts = String(real).split('.').map(Number);
      var isActuallyNew = parts[0] > 0 || parts[1] >= 13;
      if (!isActuallyNew) {
        return;
      }

      // Passes both text and number comparisons as "new NW.js". Only the legacy alias is changed;
      // process.versions.nw keeps the real version for modern code.
      var reported = '0.99.0';
      try {
        Object.defineProperty(process.versions, 'node-webkit', {
          value: reported, writable: true, enumerable: true, configurable: true
        });
      } catch (error) {}
      if (process.versions['node-webkit'] !== reported) {
        try {
          var copy = Object.assign({}, process.versions);
          copy['node-webkit'] = reported;
          Object.defineProperty(process, 'versions', {
            value: copy, writable: true, enumerable: true, configurable: true
          });
        } catch (error) {
          console.error('[Portwey] Could not adjust NW.js version string', error);
          return;
        }
      }
      console.log('[Portwey] Reporting NW.js ' + real + ' as ' + reported + ' to old version checks');
    })();

    // 2. nw.Window.open changes.
    (function () {
      'use strict';
      if (typeof nw === 'undefined' || !nw.Window || typeof nw.Window.open !== 'function') {
        return;
      }

      // Options accepted by nw.Window.open in modern NW.js. Anything else makes it throw.
      var supportedOptions = [
        'id', 'title', 'width', 'height', 'x', 'y', 'icon', 'position',
        'min_width', 'min_height', 'max_width', 'max_height',
        'frame', 'show', 'resizable', 'always_on_top', 'visible_on_all_workspaces',
        'fullscreen', 'show_in_taskbar', 'kiosk', 'transparent', 'focus',
        'new_instance', 'inject_js_start', 'inject_js_end', 'mixed_context'
      ];

      // Old NW.js used dashes ("always-on-top"); modern NW.js uses underscores ("always_on_top").
      function normalizeOptions(options) {
        var cleaned = {};
        var dropped = [];
        Object.keys(options).forEach(function (key) {
          var normalized = key.replace(/-/g, '_');
          if (supportedOptions.indexOf(normalized) !== -1) {
            cleaned[normalized] = options[key];
          } else {
            dropped.push(key);
          }
        });
        if (dropped.length > 0) {
          console.log('[Portwey] Dropped unsupported window options: ' + dropped.join(', '));
        }
        return cleaned;
      }

      // Old NW.js returned the new window right away. Modern NW.js only hands it to a callback.
      // This stand-in records calls made before the real window exists and replays them later.
      function createDeferredWindow() {
        var realWindow = null;
        var pending = [];

        var proxy = new Proxy({}, {
          get: function (target, property) {
            if (property === '__portweyResolve') {
              return function (win) {
                realWindow = win;
                pending.splice(0).forEach(function (action) {
                  try {
                    action(win);
                  } catch (error) {
                    console.error('[Portwey] Deferred window call failed', error);
                  }
                });
              };
            }
            if (realWindow) {
              var value = realWindow[property];
              return typeof value === 'function' ? value.bind(realWindow) : value;
            }
            if (property === 'then' || typeof property === 'symbol') {
              return undefined;
            }
            // Window not ready yet: queue the method call and return the proxy so calls can chain.
            return function () {
              var args = arguments;
              pending.push(function (win) {
                if (typeof win[property] === 'function') {
                  win[property].apply(win, args);
                }
              });
              return proxy;
            };
          },
          set: function (target, property, value) {
            if (realWindow) {
              realWindow[property] = value;
            } else {
              pending.push(function (win) {
                win[property] = value;
              });
            }
            return true;
          }
        });

        return proxy;
      }

      var originalOpen = nw.Window.open;

      var patchedOpen = function (url, options, callback) {
        if (typeof options === 'function') {
          callback = options;
          options = undefined;
        }
        options = (options && typeof options === 'object') ? normalizeOptions(options) : {};

        var deferred = createDeferredWindow();
        var result = originalOpen.call(this, url, options, function (win) {
          deferred.__portweyResolve(win);
          if (typeof callback === 'function') {
            callback(win);
          }
        });
        return result !== undefined ? result : deferred;
      };

      try {
        nw.Window.open = patchedOpen;
      } catch (error) {}
      if (nw.Window.open !== patchedOpen) {
        try {
          Object.defineProperty(nw.Window, 'open', { value: patchedOpen, configurable: true, writable: true });
        } catch (error) {
          console.error('[Portwey] Could not patch nw.Window.open', error);
          return;
        }
      }
      console.log('[Portwey] NW.js compatibility shim active');
    })();
    """#

    // MARK: - Helpers

    private static func backupOnce(_ url: URL) throws {
        let backupURL = URL(fileURLWithPath: url.path + backupSuffix)
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.copyItem(at: url, to: backupURL)
        }
    }

    private static func slug(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let lowered = value.lowercased().replacingOccurrences(of: " ", with: "-")
        let cleaned = String(lowered.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "portwey-game" : cleaned
    }

    private static func findNWJSApp(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == "nwjs.app" {
                return url
            }
        }
        return nil
    }
}

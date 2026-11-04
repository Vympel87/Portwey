import AppKit

/// Checks GitHub Releases of the Portwey repo for a newer version.
/// Each release uses a tag like "v0.2.0", with the DMG attached and release notes in the description.
enum UpdateChecker {
    static let repository = "Vympel87/Portwey"

    static let autoCheckKey = "autoCheckUpdates"
    private static let lastCheckKey = "lastUpdateCheck"

    private static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    struct Release {
        let version: String
        let downloadURL: URL
        let notes: String?
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlUrl: URL
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Portwey", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubRelease.self, from: data)

        // "v0.2.0" → "0.2.0"; prefer the attached DMG, otherwise the release page.
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }

        return Release(
            version: version,
            downloadURL: dmg?.browserDownloadUrl ?? release.htmlUrl,
            notes: release.body
        )
    }

    /// Compares versions as numbers, so "0.10.0" is newer than "0.9.0".
    /// (Comparing them as plain text is exactly the bug old RPG Maker plugins have.)
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    /// Runs at launch: at most once a day, only if automatic checks are on, and quietly unless there's an update.
    @MainActor
    static func checkAtLaunchIfNeeded() async {
        let defaults = UserDefaults.standard
        let autoCheck = defaults.object(forKey: autoCheckKey) as? Bool ?? true
        guard autoCheck else { return }

        if let last = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        defaults.set(Date(), forKey: lastCheckKey)
        await check(userInitiated: false)
    }

    @MainActor
    static func check(userInitiated: Bool) async {
        do {
            let release = try await fetchLatest()

            if isNewer(release.version, than: currentVersion) {
                let alert = NSAlert()
                alert.messageText = "Portwey \(release.version) is available"
                var info = "You have version \(currentVersion)."
                if let notes = release.notes, !notes.isEmpty {
                    info += "\n\n\(notes)"
                }
                alert.informativeText = info
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(release.downloadURL)
                }
            } else if userInitiated {
                showAlert(title: "You're up to date", message: "Portwey \(currentVersion) is the latest version.")
            }
        } catch {
            if userInitiated {
                showAlert(title: "Couldn't check for updates", message: "There's no published release yet, or you're offline.")
            }
        }
    }

    @MainActor
    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

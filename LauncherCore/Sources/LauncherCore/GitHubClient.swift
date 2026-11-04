import Foundation

public enum GitHubClient {
    /// Latest stable (non-prerelease) release. Returns 404 if a repo only has pre-releases.
    public static func latestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        return try await fetch(GitHubRelease.self, from: url)
    }

    /// All recent releases, newest first, including pre-releases.
    public static func releases(owner: String, repo: String, perPage: Int = 20) async throws -> [GitHubRelease] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=\(perPage)")!
        return try await fetch([GitHubRelease].self, from: url)
    }

    /// A specific release by its tag, e.g. "4.3-stable".
    public static func release(owner: String, repo: String, tag: String) async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(tag)")!
        return try await fetch(GitHubRelease.self, from: url)
    }

    private static func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Portwey", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LauncherError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

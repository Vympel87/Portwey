import Foundation

/// Turns common error messages from game logs into advice people can act on.
public enum KnownIssues {
    private static let rules: [(pattern: String, hint: String)] = [
        (
            "no exported symbols needed by DXMT",
            "DXMT needs a Wine built from CrossOver's source code, and the current Wine isn't one. Switch Graphics to DXVK, or import a compatible Wine on the Runtimes page."
        ),
        (
            "Failed to create D3D11 device",
            "DirectX 11 couldn't start with this graphics backend. Try another one (DXVK, DXMT or WineD3D) in the game's settings."
        ),
        (
            "Failed to initialize graphics",
            "The game couldn't start its renderer. Try another graphics backend in the game's settings."
        ),
        (
            "Unexpected property",
            "This game uses an old NW.js feature Portwey doesn't translate yet. Save the log and report it so the compatibility layer can be updated."
        )
    ]

    /// Advice for a log line, if it matches a known problem.
    public static func hint(for line: String) -> String? {
        rules.first { line.localizedCaseInsensitiveContains($0.pattern) }?.hint
    }
}

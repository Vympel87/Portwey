import Foundation

public enum RosettaService {
    public static var isRequired: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Checks for Rosetta by trying to run a binary in x86_64 mode.
    public static func isInstalled() async -> Bool {
        guard isRequired else { return true }
        let result = try? await Shell.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"])
        return result?.succeeded ?? false
    }

    /// Installs Rosetta. macOS will show a prompt asking for an admin password.
    public static func install() async throws {
        let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
        let result = try await Shell.run("/usr/bin/osascript", ["-e", script])

        guard result.succeeded else {
            if result.output.contains("-128") {
                throw LauncherError.rosettaInstallCancelled
            }
            throw LauncherError.commandFailed(
                command: "softwareupdate --install-rosetta",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        guard await isInstalled() else {
            throw LauncherError.rosettaUnavailable
        }
    }
}

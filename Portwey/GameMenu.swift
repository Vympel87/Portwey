import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LauncherCore

struct GameMenuItems: View {
    let game: Game
    var onOpenDetails: (() -> Void)?

    @Environment(GameLibrary.self) private var library
    @Environment(GameRunner.self) private var runner
    @Environment(SetupManager.self) private var setup

    var body: some View {
        Button("Play") {
            playGame(game, runner: runner, setup: setup)
        }
        .disabled(runner.isBusy || !game.executableExists)

        if let onOpenDetails {
            Button("Open Details", action: onOpenDetails)
        }

        Divider()

        Button("Change Cover…") {
            chooseCoverImage(for: game, library: library)
        }
        if game.coverFileName != nil {
            Button("Remove Cover") {
                library.removeCover(for: game.id)
            }
        }

        Divider()

        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([game.executableURL])
        }
        if game.launchMethod == .wine {
            Button("Open C: Drive") {
                openDriveC(for: game)
            }
        }

        Divider()

        Button("Remove from Library", role: .destructive) {
            library.remove(game)
        }
        .disabled(runner.activeGameID == game.id)

        if library.isManagedByPortwey(game) {
            Button("Delete Game Files…", role: .destructive) {
                if confirmDeleteGameFiles(for: game) {
                    library.remove(game, deleteGameFiles: true)
                }
            }
            .disabled(runner.activeGameID == game.id)
        }
    }
}

@MainActor
func confirmDeleteGameFiles(for game: Game) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Delete \(game.title)?"
    alert.informativeText = "The game is removed from your library and its files are deleted from Portwey's games folder. This can't be undone."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    alert.buttons.first?.hasDestructiveAction = true
    return alert.runModal() == .alertFirstButtonReturn
}

@MainActor
func chooseCoverImage(for game: Game, library: GameLibrary) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message = "Choose a cover image for \(game.title)"
    panel.prompt = "Use as Cover"

    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        try library.setCover(from: url, for: game.id)
    } catch {
        NSAlert(error: error).runModal()
    }
}

@MainActor
func openDriveC(for game: Game) {
    let driveC = BottleManager.bottleURL(named: game.bottleName)
        .appendingPathComponent("drive_c", isDirectory: true)
    NSWorkspace.shared.open(driveC)
}

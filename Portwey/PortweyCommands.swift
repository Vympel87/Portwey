import SwiftUI
import LauncherCore

/// Menu bar commands and keyboard shortcuts for the main window.
struct PortweyCommands: Commands {
    let appState: AppState
    let runner: GameRunner

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                Task { await UpdateChecker.check(userInitiated: true) }
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Add Game…") {
                appState.requestAddGame()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandMenu("Game") {
            Button("Stop Game") {
                Task { await runner.stop() }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!runner.isBusy)
        }

        CommandGroup(before: .sidebar) {
            Button("Library") { appState.sidebarSelection = .library }
                .keyboardShortcut("1", modifiers: .command)
            Button("Steam") { appState.sidebarSelection = .steam }
                .keyboardShortcut("2", modifiers: .command)
            Button("Presets") { appState.sidebarSelection = .presets }
                .keyboardShortcut("3", modifiers: .command)
            Button("Bottles") { appState.sidebarSelection = .bottles }
                .keyboardShortcut("4", modifiers: .command)
            Button("Runtimes") { appState.sidebarSelection = .runtimes }
                .keyboardShortcut("5", modifiers: .command)
            Divider()
        }
    }
}

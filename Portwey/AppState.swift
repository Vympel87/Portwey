import SwiftUI
import Observation

/// App-wide UI state shared by the main window, menus and keyboard shortcuts.
@MainActor
@Observable
final class AppState {
    var sidebarSelection: SidebarItem? = .library
    var addGameRequested = false

    func requestAddGame() {
        sidebarSelection = .library
        addGameRequested = true
    }
}

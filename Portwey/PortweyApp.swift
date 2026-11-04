//
//  PortweyApp.swift
//  Portwey
//
//  Created by Yudhistira Rafazaky Bandono on 03/11/26.
//

import SwiftUI
import LauncherCore

@main
struct PortweyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var setup = SetupManager()
    @State private var library: GameLibrary
    @State private var runner: GameRunner
    @State private var steam: SteamManager
    @State private var appState = AppState()

    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    init() {
        let library = GameLibrary()
        _library = State(initialValue: library)
        _runner = State(initialValue: GameRunner(library: library))
        _steam = State(initialValue: SteamManager(library: library))
    }

    var body: some Scene {
        // A single main window; closing it keeps Portwey running in the menu bar.
        Window("Portwey", id: "main") {
            ContentView()
                .environment(setup)
                .environment(library)
                .environment(runner)
                .environment(steam)
                .environment(appState)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    appDelegate.connect(library: library, runner: runner, setup: setup)
                }
        }
        .commands {
            PortweyCommands(appState: appState, runner: runner)
        }

        Settings {
            SettingsView()
                .environment(setup)
                .environment(library)
        }

        MenuBarExtra("Portwey", systemImage: "gamecontroller.fill", isInserted: $showMenuBarExtra) {
            MenuBarContent()
                .environment(setup)
                .environment(library)
                .environment(runner)
        }
    }
}

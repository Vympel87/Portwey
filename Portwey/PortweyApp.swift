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
    @State private var setup = SetupManager()
    @State private var library: GameLibrary
    @State private var runner: GameRunner

    init() {
        let library = GameLibrary()
        _library = State(initialValue: library)
        _runner = State(initialValue: GameRunner(library: library))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(setup)
                .environment(library)
                .environment(runner)
                .frame(minWidth: 960, minHeight: 640)
        }
    }
}

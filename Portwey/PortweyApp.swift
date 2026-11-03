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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(setup)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

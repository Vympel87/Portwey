//
//  ContentView.swift
//  Portwey
//
//  Created by Yudhistira Rafazaky Bandono on 03/11/26.
//

import SwiftUI
import LauncherCore

struct ContentView: View {
    @Environment(SetupManager.self) private var setup
    @Environment(GameLibrary.self) private var library

    var body: some View {
        Group {
            if setup.isReady {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .task {
            // If Wine was installed before, re-run the checks automatically without a button click.
            if setup.runtime != nil, setup.phase == .idle {
                await setup.start()
            }
        }
        .task {
            await library.refreshPresets()
        }
    }
}

#Preview {
    let library = GameLibrary()
    return ContentView()
        .environment(SetupManager())
        .environment(library)
        .environment(GameRunner(library: library))
        .environment(SteamManager(library: library))
        .environment(AppState())
}

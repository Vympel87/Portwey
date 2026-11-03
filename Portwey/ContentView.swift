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

    var body: some View {
        Group {
            if setup.isReady {
                ReadyPlaceholderView()
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
    }
}

private struct ReadyPlaceholderView: View {
    @Environment(SetupManager.self) private var setup

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Portwey is ready")
                .font(.largeTitle.bold())
            if let runtime = setup.runtime {
                Text(runtime.version)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Text("Your game library will show up here (coming next).")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environment(SetupManager())
}

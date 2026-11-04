import SwiftUI
import AppKit
import LauncherCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 560)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(GameRunner.self) private var runner
    @Environment(SetupManager.self) private var setup

    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheckUpdates = true

    @State private var downloadsSize: Int64?
    @State private var message: String?

    private var downloadsText: String {
        guard let downloadsSize else { return "Calculating…" }
        return ByteCountFormatter.string(fromByteCount: downloadsSize, countStyle: .file)
    }

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show Portwey in the menu bar", isOn: $showMenuBarExtra)
                Text("Quick access to recent games and to the game that's running, even when the main window is closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                LabeledContent("Current version") {
                    HStack {
                        Text(UpdateChecker.currentVersion)
                            .foregroundStyle(.secondary)
                        Button("Check Now") {
                            Task { await UpdateChecker.check(userInitiated: true) }
                        }
                    }
                }
            }

            Section("Storage") {
                LabeledContent("Data folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(AppPaths.root)
                    }
                }
                Text(AppPaths.root.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                LabeledContent("Download cache") {
                    HStack {
                        Text(downloadsText)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Clear") {
                            clearDownloads()
                        }
                        .disabled((downloadsSize ?? 0) == 0)
                    }
                }
                Text("Leftover installer files. Clearing them doesn't affect installed games or runtimes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Uninstall") {
                LabeledContent("Remove Portwey completely") {
                    Button("Uninstall Portwey…", role: .destructive) {
                        Task { await Uninstaller.confirmAndUninstall(runner: runner, setup: setup) }
                    }
                }
                Text("Dragging Portwey to the Trash leaves its runtimes, bottles and imported games behind. This removes everything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            downloadsSize = await BottleManager.diskSize(of: AppPaths.downloads)
        }
    }

    private func clearDownloads() {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: AppPaths.downloads, includingPropertiesForKeys: nil)) ?? []
        for item in items {
            try? fm.removeItem(at: item)
        }
        downloadsSize = 0
        message = "Download cache cleared."
    }
}

// MARK: - About

private struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Portwey")
                            .font(.title.bold())
                        Text("Version \(version) (\(build))")
                            .foregroundStyle(.secondary)
                        Text("Play Windows games on Apple Silicon.")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text("Third-party components")
                    .font(.headline)
                Text("Portwey doesn't include these components. It downloads them from their official sources when they're needed, and each one keeps its own license.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(ThirdPartyComponent.all) { component in
                    VStack(alignment: .leading, spacing: 2) {
                        Link(component.name, destination: component.url)
                            .font(.body.weight(.semibold))
                        Text(component.purpose)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("License: \(component.license)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text("Portwey isn't affiliated with or endorsed by any of these projects, Valve or Apple.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ThirdPartyComponent: Identifiable {
    let name: String
    let purpose: String
    let license: String
    let url: URL

    var id: String { name }

    static let all: [ThirdPartyComponent] = [
        ThirdPartyComponent(
            name: "Wine",
            purpose: "Runs Windows programs on macOS",
            license: "LGPL 2.1 or later",
            url: URL(string: "https://www.winehq.org")!
        ),
        ThirdPartyComponent(
            name: "macOS Wine builds by Gcenx",
            purpose: "Ready-made Wine for macOS (includes MoltenVK)",
            license: "LGPL 2.1 or later",
            url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds")!
        ),
        ThirdPartyComponent(
            name: "MoltenVK",
            purpose: "Vulkan on top of Apple's Metal",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/KhronosGroup/MoltenVK")!
        ),
        ThirdPartyComponent(
            name: "DXVK-macOS",
            purpose: "DirectX 10/11 through Vulkan",
            license: "zlib",
            url: URL(string: "https://github.com/Gcenx/DXVK-macOS")!
        ),
        ThirdPartyComponent(
            name: "DXMT",
            purpose: "DirectX 11 straight to Metal (experimental)",
            license: "See project",
            url: URL(string: "https://github.com/3Shain/dxmt")!
        ),
        ThirdPartyComponent(
            name: "NW.js",
            purpose: "Runs RPG Maker MV/MZ games natively",
            license: "MIT",
            url: URL(string: "https://nwjs.io")!
        ),
        ThirdPartyComponent(
            name: "Godot Engine",
            purpose: "Runs Godot games natively",
            license: "MIT",
            url: URL(string: "https://godotengine.org")!
        ),
        ThirdPartyComponent(
            name: "Steam",
            purpose: "Valve's Windows Steam client (optional, beta)",
            license: "Steam Subscriber Agreement",
            url: URL(string: "https://store.steampowered.com")!
        )
    ]
}

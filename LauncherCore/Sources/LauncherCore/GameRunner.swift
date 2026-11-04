import Foundation
import Observation

@MainActor
@Observable
public final class GameRunner {
    public enum State: Equatable {
        case idle
        case preparing(gameID: UUID)
        case running(gameID: UUID)
    }

    public private(set) var state: State = .idle
    public private(set) var logs: [String] = []
    public private(set) var lastError: String?

    private let library: GameLibrary
    private var process: Process?
    private var startedAt: Date?
    private var runningGameID: UUID?
    private var runningBottle: URL?
    private var runningRuntime: RuntimeInfo?
    private let maxLogLines = 3000

    public init(library: GameLibrary) {
        self.library = library
    }

    public var isBusy: Bool { state != .idle }

    public func isPreparing(_ id: UUID) -> Bool { state == .preparing(gameID: id) }

    public func isRunning(_ id: UUID) -> Bool { state == .running(gameID: id) }

    // MARK: - Launch

    public func launch(_ game: Game, runtime: RuntimeInfo) async {
        guard state == .idle else { return }
        logs.removeAll()
        lastError = nil
        state = .preparing(gameID: game.id)

        do {
            guard game.executableExists else {
                throw LauncherError.executableNotFound(game.executablePath)
            }

            let process: Process
            switch game.launchMethod {
            case .wine:
                process = try await makeWineProcess(for: game, runtime: runtime)
            case .nwjs:
                process = try await makeNWJSProcess(for: game)
            case .godot:
                process = try await makeGodotProcess(for: game)
            }

            attachOutput(to: process)
            try process.run()

            self.process = process
            startedAt = Date()
            runningGameID = game.id
            state = .running(gameID: game.id)
        } catch {
            lastError = error.localizedDescription
            log("❌ \(error.localizedDescription)")
            runningBottle = nil
            runningRuntime = nil
            state = .idle
        }
    }

    public func stop() async {
        guard let process else { return }
        log("Stopping game…")
        process.terminate()
        if let bottle = runningBottle, let runtime = runningRuntime {
            await BottleManager.killAll(in: bottle, runtime: runtime)
        }
    }

    // MARK: - Wine

    private func makeWineProcess(for game: Game, runtime: RuntimeInfo) async throws -> Process {
        let bottle = try await BottleManager.ensureBottle(named: game.bottleName, runtime: runtime) { [weak self] line in
            Task { @MainActor in self?.log(line) }
        }

        // Graphics backend: DXVK games run on a DXVK copy of Wine, WineD3D games on the original.
        var launchRuntime = runtime
        var extraEnvironment: [String: String] = [:]
        switch game.graphicsBackend {
        case .dxvk:
            if let dxvk = DXVKService.installed() {
                launchRuntime = try await DXVKService.runtimeVariant(base: runtime, dxvk: dxvk) { [weak self] line in
                    Task { @MainActor in self?.log(line) }
                }
                extraEnvironment = DXVKService.environment(for: bottle)
                log("Graphics: DXVK \(dxvk.tag)")
            } else {
                log("⚠️ DXVK isn't installed, falling back to WineD3D")
            }
        case .wined3d:
            log("Graphics: WineD3D (OpenGL)")
        }

        // Per-game custom environment variables win over the defaults above.
        extraEnvironment.merge(game.environment) { _, custom in custom }
        logCustomSettings(for: game)

        let process = Process()
        process.executableURL = launchRuntime.wineBinaryURL
        process.arguments = [game.executablePath] + game.arguments
        process.currentDirectoryURL = game.workingDirectoryURL
        process.environment = BottleManager.environment(for: bottle, extra: extraEnvironment)

        log("Launching \(game.title) with Wine…")
        log("$ WINEPREFIX=\"\(bottle.path)\" \"\(launchRuntime.wineBinaryPath)\" \"\(game.executablePath)\"")

        runningBottle = bottle
        runningRuntime = launchRuntime
        return process
    }

    // MARK: - Native NW.js

    private func makeNWJSProcess(for game: Game) async throws -> Process {
        let nwjs = try await NWJSService.ensureInstalled { [weak self] line in
            Task { @MainActor in self?.log(line) }
        }

        let gameRoot = game.workingDirectoryURL
        try NWJSService.prepareGameFolder(gameRoot, fallbackName: game.title) { line in
            log(line)
        }
        logCustomSettings(for: game)

        // Browsers block audio until the user clicks; games expect music right away.
        let arguments = ["--autoplay-policy=no-user-gesture-required"] + game.arguments + [gameRoot.path]

        let process = Process()
        process.executableURL = nwjs.executableURL
        process.arguments = arguments
        process.currentDirectoryURL = gameRoot
        process.environment = ProcessInfo.processInfo.environment
            .merging(game.environment) { _, custom in custom }

        log("Runner: native NW.js \(nwjs.version) (no Wine, no Rosetta)")
        log("Launching \(game.title)…")
        log("$ \"\(nwjs.executableURL.path)\" \(arguments.map { "\"\($0)\"" }.joined(separator: " "))")

        runningBottle = nil
        runningRuntime = nil
        return process
    }

    // MARK: - Native Godot

    private func makeGodotProcess(for game: Game) async throws -> Process {
        let pack: GodotPackInfo
        switch GodotService.nativeSupport(for: game.executableURL) {
        case .supported(let info):
            pack = info
        case .unsupported(let reason):
            throw LauncherError.godotNotSupported(reason)
        }

        let location = pack.isEmbedded ? "data inside the .exe" : pack.packURL.lastPathComponent
        log("Godot \(pack.version) game detected (\(location))")

        let godot = try await GodotService.ensureInstalled(version: pack.version) { [weak self] line in
            Task { @MainActor in self?.log(line) }
        }
        logCustomSettings(for: game)

        // --main-pack runs the game's data with the matching Godot build, as a game (not the editor).
        let arguments = ["--main-pack", pack.packURL.path] + game.arguments

        let process = Process()
        process.executableURL = godot.executableURL
        process.arguments = arguments
        process.currentDirectoryURL = game.workingDirectoryURL
        process.environment = ProcessInfo.processInfo.environment
            .merging(game.environment) { _, custom in custom }

        log("Runner: native Godot \(godot.version) (no Wine, no Rosetta)")
        log("Launching \(game.title)…")
        log("$ \"\(godot.executableURL.path)\" \(arguments.map { "\"\($0)\"" }.joined(separator: " "))")

        runningBottle = nil
        runningRuntime = nil
        return process
    }

    // MARK: - Process output

    private func attachOutput(to process: Process) {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.appendOutput(text) }
        }

        process.terminationHandler = { [weak self] finished in
            let exitCode = finished.terminationStatus
            Task { @MainActor in self?.didTerminate(exitCode: exitCode) }
        }
    }

    private func didTerminate(exitCode: Int32) {
        if let id = runningGameID, let startedAt {
            library.recordSession(gameID: id, duration: Date().timeIntervalSince(startedAt))
        }
        log("Game exited with code \(exitCode)")

        process = nil
        startedAt = nil
        runningGameID = nil
        runningBottle = nil
        runningRuntime = nil
        state = .idle
    }

    // MARK: - Logging

    private func logCustomSettings(for game: Game) {
        if !game.environment.isEmpty {
            log("Custom environment: \(game.environment.keys.sorted().joined(separator: ", "))")
        }
        if !game.arguments.isEmpty {
            log("Arguments: \(game.arguments.joined(separator: " "))")
        }
    }

    private func appendOutput(_ text: String) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            logs.append(String(line))
        }
        trimLogs()
    }

    private func log(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let line = "[\(time)] \(message)"
        logs.append(line)
        trimLogs()
        print(line)
    }

    private func trimLogs() {
        if logs.count > maxLogLines {
            logs.removeFirst(logs.count - maxLogLines)
        }
    }
}

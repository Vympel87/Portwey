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

    public func launch(_ game: Game, runtime: RuntimeInfo) async {
        guard state == .idle else { return }
        logs.removeAll()
        lastError = nil
        state = .preparing(gameID: game.id)

        do {
            guard game.executableExists else {
                throw LauncherError.executableNotFound(game.executablePath)
            }

            let bottle = try await BottleManager.ensureBottle(named: game.bottleName, runtime: runtime) { [weak self] line in
                Task { @MainActor in self?.log(line) }
            }

            let process = Process()
            process.executableURL = runtime.wineBinaryURL
            process.arguments = [game.executablePath] + game.arguments
            process.currentDirectoryURL = game.workingDirectoryURL
            process.environment = BottleManager.environment(for: bottle)

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

            log("Launching \(game.title)…")
            log("$ WINEPREFIX=\"\(bottle.path)\" \"\(runtime.wineBinaryPath)\" \"\(game.executablePath)\"")
            try process.run()

            self.process = process
            startedAt = Date()
            runningGameID = game.id
            runningBottle = bottle
            runningRuntime = runtime
            state = .running(gameID: game.id)
        } catch {
            lastError = error.localizedDescription
            log("❌ \(error.localizedDescription)")
            state = .idle
        }
    }

    public func stop() async {
        guard let bottle = runningBottle, let runtime = runningRuntime else { return }
        log("Stopping game…")
        process?.terminate()
        await BottleManager.killAll(in: bottle, runtime: runtime)
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

//
//  ShellResult.swift
//  LauncherCore
//
//  Created by Yudhistira Rafazaky Bandono on 04/11/26.
//


import Foundation

public struct ShellResult: Sendable {
    public let exitCode: Int32
    public let output: String
    public var succeeded: Bool { exitCode == 0 }
}

public enum Shell {
    @discardableResult
    public static func run(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> ShellResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            if let environment {
                process.environment = ProcessInfo.processInfo.environment
                    .merging(environment) { _, new in new }
            }
            if let currentDirectory {
                process.currentDirectoryURL = currentDirectory
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ShellResult(exitCode: process.terminationStatus, output: output)
        }.value
    }

    @discardableResult
    public static func runChecked(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> ShellResult {
        let result = try await run(executable, arguments, environment: environment, currentDirectory: currentDirectory)
        guard result.succeeded else {
            throw LauncherError.commandFailed(
                command: ([executable] + arguments).joined(separator: " "),
                exitCode: result.exitCode,
                output: result.output
            )
        }
        return result
    }
}

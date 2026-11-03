//
//  FileDownloader 2.swift
//  LauncherCore
//
//  Created by Yudhistira Rafazaky Bandono on 04/11/26.
//


import Foundation

final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var lastReported: Double = -1

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 120       // max wait between data packets
            configuration.timeoutIntervalForResource = 60 * 60  // max total download time
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let pending: CheckedContinuation<URL, Error>? = lock.withLock {
            let current = continuation
            continuation = nil
            return current
        }
        pending?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let shouldReport: Bool = lock.withLock {
            if progress - lastReported >= 0.01 || progress >= 1 {
                lastReported = progress
                return true
            }
            return false
        }
        if shouldReport { onProgress(progress) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            finish(.failure(LauncherError.downloadFailed("HTTP \(http.statusCode)")))
            return
        }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(LauncherError.downloadFailed(error.localizedDescription)))
        }
        session.finishTasksAndInvalidate()
    }
}


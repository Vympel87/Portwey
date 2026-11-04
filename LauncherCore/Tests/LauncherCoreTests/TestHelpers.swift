import Foundation

/// A fresh, empty folder in the temporary directory for each test.
func makeTemporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PortweyTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Creates an empty file (and its parent folders).
@discardableResult
func touch(_ relativePath: String, in folder: URL, contents: Data = Data()) throws -> URL {
    let url = folder.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: url.path, contents: contents)
    return url
}

/// Creates an empty folder.
func makeFolder(_ relativePath: String, in folder: URL) throws {
    try FileManager.default.createDirectory(
        at: folder.appendingPathComponent(relativePath, isDirectory: true),
        withIntermediateDirectories: true
    )
}

extension Data {
    /// Appends an integer in little-endian byte order, the way Windows and Godot files store them.
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

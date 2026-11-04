import Foundation

/// Reads the header of a Godot data pack (.pck), either as its own file or embedded at the end of an .exe.
///
/// Layout:
/// - Standalone: "GDPC" magic, format version, engine major/minor/patch, then (format 2+) flags.
/// - Embedded:   [pack data][UInt64 pack size]["GDPC"] at the very end of the .exe.
public struct GodotPackInfo: Sendable, Equatable {
    public let packURL: URL
    public let isEmbedded: Bool
    public let formatVersion: UInt32
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let isEncrypted: Bool

    /// Matches Godot's release naming: "4.3" for 4.3.0, "4.2.2" otherwise.
    public var version: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    static let magic: UInt32 = 0x4350_4447 // "GDPC" in little-endian

    public static func read(from url: URL) -> GodotPackInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // 1. A standalone .pck starts with the header.
        if let info = header(in: handle, at: 0, url: url, embedded: false) {
            return info
        }

        // 2. A self-contained .exe ends with [pack size][magic].
        guard
            let end = try? handle.seekToEnd(),
            end >= 12,
            let trailer = bytes(in: handle, at: end - 12, count: 12),
            littleEndian32(trailer, at: 8) == magic
        else { return nil }

        let size = littleEndian64(trailer, at: 0)
        guard size > 0, size <= end - 12 else { return nil }
        return header(in: handle, at: end - 12 - size, url: url, embedded: true)
    }

    private static func header(in handle: FileHandle, at offset: UInt64, url: URL, embedded: Bool) -> GodotPackInfo? {
        guard
            let data = bytes(in: handle, at: offset, count: 24),
            littleEndian32(data, at: 0) == magic
        else { return nil }

        let format = littleEndian32(data, at: 4)
        let major = Int(littleEndian32(data, at: 8))
        let minor = Int(littleEndian32(data, at: 12))
        let patch = Int(littleEndian32(data, at: 16))
        guard (2...9).contains(major), minor < 100, patch < 100 else { return nil }

        // Pack format 2+ (Godot 4) has a flags field; bit 0 means the file list is encrypted.
        let flags = format >= 2 ? littleEndian32(data, at: 20) : 0

        return GodotPackInfo(
            packURL: url,
            isEmbedded: embedded,
            formatVersion: format,
            major: major,
            minor: minor,
            patch: patch,
            isEncrypted: (flags & 1) != 0
        )
    }

    private static func bytes(in handle: FileHandle, at offset: UInt64, count: Int) -> Data? {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func littleEndian32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(data[data.startIndex + offset + index]) << (8 * UInt32(index))
        }
        return value
    }

    private static func littleEndian64(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[data.startIndex + offset + index]) << (8 * UInt64(index))
        }
        return value
    }
}

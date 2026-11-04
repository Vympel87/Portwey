import Foundation
import Testing
@testable import LauncherCore

@Suite("Godot .pck reader")
struct GodotPackTests {
    /// Godot 3 header: magic, format 1, version, 16 reserved words, file count.
    private func godot3Pack(major: UInt32, minor: UInt32, patch: UInt32) -> Data {
        var data = Data("GDPC".utf8)
        data.appendLittleEndian(UInt32(1))
        data.appendLittleEndian(major)
        data.appendLittleEndian(minor)
        data.appendLittleEndian(patch)
        for _ in 0..<16 { data.appendLittleEndian(UInt32(0)) }
        data.appendLittleEndian(UInt32(0))
        return data
    }

    /// Godot 4 header: magic, format 2, version, flags, file base, 16 reserved words, file count.
    private func godot4Pack(major: UInt32, minor: UInt32, patch: UInt32, flags: UInt32) -> Data {
        var data = Data("GDPC".utf8)
        data.appendLittleEndian(UInt32(2))
        data.appendLittleEndian(major)
        data.appendLittleEndian(minor)
        data.appendLittleEndian(patch)
        data.appendLittleEndian(flags)
        data.appendLittleEndian(UInt64(0))
        for _ in 0..<16 { data.appendLittleEndian(UInt32(0)) }
        data.appendLittleEndian(UInt32(0))
        return data
    }

    @Test("Reads the engine version from a Godot 3 pack")
    func godot3() throws {
        let folder = try makeTemporaryFolder()
        let pack = try touch("game.pck", in: folder, contents: godot3Pack(major: 3, minor: 5, patch: 2))

        let info = try #require(GodotPackInfo.read(from: pack))
        #expect(info.major == 3)
        #expect(info.minor == 5)
        #expect(info.patch == 2)
        #expect(info.version == "3.5.2")
        #expect(info.isEmbedded == false)
        #expect(info.isEncrypted == false)
    }

    @Test("Reads a Godot 4 pack and notices encryption")
    func godot4Encrypted() throws {
        let folder = try makeTemporaryFolder()
        let plain = try touch("plain.pck", in: folder, contents: godot4Pack(major: 4, minor: 2, patch: 1, flags: 0))
        let encrypted = try touch("encrypted.pck", in: folder, contents: godot4Pack(major: 4, minor: 2, patch: 1, flags: 1))

        let plainInfo = try #require(GodotPackInfo.read(from: plain))
        #expect(plainInfo.major == 4)
        #expect(plainInfo.minor == 2)
        #expect(plainInfo.isEncrypted == false)

        let encryptedInfo = try #require(GodotPackInfo.read(from: encrypted))
        #expect(encryptedInfo.isEncrypted == true)
    }

    @Test("Ignores files that aren't Godot packs")
    func notAPack() throws {
        let folder = try makeTemporaryFolder()
        let junk = try touch("data.pck", in: folder, contents: Data("definitely not a pack".utf8))

        #expect(GodotPackInfo.read(from: junk) == nil)
        #expect(GodotPackInfo.read(from: folder.appendingPathComponent("missing.pck")) == nil)
    }
}

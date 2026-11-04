import Foundation
import Testing
@testable import LauncherCore

@Suite("Icons from .exe files")
struct ExeIconExtractorTests {
    @Test("Files that aren't Windows programs give no icon")
    func notAnExecutable() throws {
        let folder = try makeTemporaryFolder()
        let fake = try touch("fake.exe", in: folder, contents: Data("just some text".utf8))

        #expect(ExeIconExtractor.extractICO(from: fake) == nil)
        #expect(ExeIconExtractor.extractPNG(from: fake) == nil)
    }

    @Test("A cut-off file doesn't crash the parser")
    func truncatedHeader() throws {
        let folder = try makeTemporaryFolder()
        // Starts like a real program ("MZ") but ends right after.
        let truncated = try touch("broken.exe", in: folder, contents: Data([0x4D, 0x5A, 0x90, 0x00]))

        #expect(ExeIconExtractor.extractICO(from: truncated) == nil)
    }

    @Test("A missing file gives no icon")
    func missingFile() throws {
        let folder = try makeTemporaryFolder()
        #expect(ExeIconExtractor.extractPNG(from: folder.appendingPathComponent("missing.exe")) == nil)
    }
}

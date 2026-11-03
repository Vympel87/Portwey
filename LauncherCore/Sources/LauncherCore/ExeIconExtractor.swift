import Foundation
import AppKit

/// Reads the application icon embedded in a Windows .exe (PE file) without any external tools.
///
/// How it works:
/// 1. Parse the PE headers to find the resource section.
/// 2. Walk the resource tree to the first RT_GROUP_ICON (the app icon) and its RT_ICON images.
/// 3. Rebuild a standard .ico file from those pieces, which macOS can open directly.
public enum ExeIconExtractor {
    private static let rtIcon: UInt32 = 3
    private static let rtGroupIcon: UInt32 = 14

    /// The largest icon image as PNG data, or nil if the .exe has no icon.
    public static func extractPNG(from exe: URL) -> Data? {
        guard let ico = extractICO(from: exe), let image = NSImage(data: ico) else { return nil }
        guard let best = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }) else { return nil }

        if let bitmap = best as? NSBitmapImageRep {
            return bitmap.representation(using: .png, properties: [:])
        }
        var rect = NSRect(x: 0, y: 0, width: best.pixelsWide, height: best.pixelsHigh)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    /// The icon rebuilt as .ico data.
    public static func extractICO(from exe: URL) -> Data? {
        guard
            let data = try? Data(contentsOf: exe, options: .alwaysMapped),
            let image = PEImage(data: data)
        else { return nil }
        return image.buildICO(groupType: rtGroupIcon, iconType: rtIcon)
    }
}

// MARK: - Byte reading (PE files are little-endian)

private struct ByteReader {
    let data: Data

    func u8(_ offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }

    func u16(_ offset: Int) -> UInt16? {
        guard let low = u8(offset), let high = u8(offset + 1) else { return nil }
        return UInt16(low) | (UInt16(high) << 8)
    }

    func u32(_ offset: Int) -> UInt32? {
        guard let low = u16(offset), let high = u16(offset + 2) else { return nil }
        return UInt32(low) | (UInt32(high) << 16)
    }

    func bytes(_ offset: Int, _ count: Int) -> Data? {
        guard offset >= 0, count >= 0, offset + count <= data.count else { return nil }
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + count))
    }
}

// MARK: - PE parsing

private struct PESection {
    let virtualAddress: UInt32
    let virtualSize: UInt32
    let rawSize: UInt32
    let rawPointer: UInt32
}

private struct ResourceEntry {
    let id: UInt32?        // nil when the entry uses a string name
    let isDirectory: Bool
    let offset: Int        // relative to the start of the resource section
}

private struct PEImage {
    let reader: ByteReader
    let sections: [PESection]
    let resourceBase: Int

    init?(data: Data) {
        let reader = ByteReader(data: data)

        // "MZ" DOS header, then the offset to the "PE\0\0" header at 0x3C.
        guard reader.u16(0) == 0x5A4D, let peOffset = reader.u32(0x3C).map(Int.init) else { return nil }
        guard reader.u32(peOffset) == 0x0000_4550 else { return nil }

        guard
            let sectionCount = reader.u16(peOffset + 6),
            let optionalHeaderSize = reader.u16(peOffset + 20)
        else { return nil }

        // Optional header: PE32 (0x10B) or PE32+ (0x20B) have data directories at different offsets.
        let optionalHeader = peOffset + 24
        let dataDirectories: Int
        switch reader.u16(optionalHeader) {
        case 0x10B: dataDirectories = optionalHeader + 96
        case 0x20B: dataDirectories = optionalHeader + 112
        default: return nil
        }

        // Data directory #2 is the resource table.
        guard let resourceRVA = reader.u32(dataDirectories + 2 * 8), resourceRVA != 0 else { return nil }

        var sections: [PESection] = []
        let sectionTable = optionalHeader + Int(optionalHeaderSize)
        for index in 0..<Int(sectionCount) {
            let entry = sectionTable + index * 40
            guard
                let virtualSize = reader.u32(entry + 8),
                let virtualAddress = reader.u32(entry + 12),
                let rawSize = reader.u32(entry + 16),
                let rawPointer = reader.u32(entry + 20)
            else { return nil }
            sections.append(PESection(
                virtualAddress: virtualAddress,
                virtualSize: virtualSize,
                rawSize: rawSize,
                rawPointer: rawPointer
            ))
        }

        guard let resourceBase = Self.fileOffset(forRVA: resourceRVA, sections: sections) else { return nil }
        self.reader = reader
        self.sections = sections
        self.resourceBase = resourceBase
    }

    /// Converts a virtual address (as the program sees it in memory) into a position in the file.
    static func fileOffset(forRVA rva: UInt32, sections: [PESection]) -> Int? {
        for section in sections {
            let size = max(section.virtualSize, section.rawSize)
            if rva >= section.virtualAddress && rva < section.virtualAddress &+ size {
                return Int(rva - section.virtualAddress) + Int(section.rawPointer)
            }
        }
        return nil
    }

    func entries(inDirectoryAt relativeOffset: Int) -> [ResourceEntry] {
        let directory = resourceBase + relativeOffset
        guard
            let namedCount = reader.u16(directory + 12),
            let idCount = reader.u16(directory + 14)
        else { return [] }

        let total = Int(namedCount) + Int(idCount)
        guard total < 4096 else { return [] }

        var result: [ResourceEntry] = []
        for index in 0..<total {
            let entry = directory + 16 + index * 8
            guard let name = reader.u32(entry), let offset = reader.u32(entry + 4) else { break }
            result.append(ResourceEntry(
                id: (name & 0x8000_0000) == 0 ? name : nil,
                isDirectory: (offset & 0x8000_0000) != 0,
                offset: Int(offset & 0x7FFF_FFFF)
            ))
        }
        return result
    }

    /// Follows a resource entry down (name → language) to its raw bytes.
    func firstData(from entry: ResourceEntry, depth: Int = 0) -> Data? {
        guard depth < 4 else { return nil }
        if entry.isDirectory {
            guard let child = entries(inDirectoryAt: entry.offset).first else { return nil }
            return firstData(from: child, depth: depth + 1)
        }
        let dataEntry = resourceBase + entry.offset
        guard
            let rva = reader.u32(dataEntry),
            let size = reader.u32(dataEntry + 4),
            let offset = Self.fileOffset(forRVA: rva, sections: sections)
        else { return nil }
        return reader.bytes(offset, Int(size))
    }

    func buildICO(groupType: UInt32, iconType: UInt32) -> Data? {
        let root = entries(inDirectoryAt: 0)
        guard
            let groupDirectory = root.first(where: { $0.id == groupType && $0.isDirectory }),
            let iconDirectory = root.first(where: { $0.id == iconType && $0.isDirectory })
        else { return nil }

        let icons = entries(inDirectoryAt: iconDirectory.offset)

        // The first icon group is almost always the main application icon.
        guard
            let firstGroup = entries(inDirectoryAt: groupDirectory.offset).first,
            let groupData = firstData(from: firstGroup)
        else { return nil }

        let group = ByteReader(data: groupData)
        guard let count = group.u16(4), count > 0 else { return nil }

        // Each group entry is 14 bytes: the same first 8 bytes as an .ico entry, then size and the RT_ICON id.
        var images: [(header: Data, image: Data)] = []
        for index in 0..<Int(count) {
            let entry = 6 + index * 14
            guard
                let header = group.bytes(entry, 8),
                let iconID = group.u16(entry + 12),
                let iconEntry = icons.first(where: { $0.id == UInt32(iconID) }),
                let imageData = firstData(from: iconEntry)
            else { continue }
            images.append((header, imageData))
        }
        guard !images.isEmpty else { return nil }

        // .ico layout: 6-byte header, 16 bytes per entry, then the image data.
        var ico = Data()
        ico.append(littleEndian(UInt16(0)))
        ico.append(littleEndian(UInt16(1)))
        ico.append(littleEndian(UInt16(images.count)))

        var imageOffset = 6 + images.count * 16
        for item in images {
            ico.append(item.header)
            ico.append(littleEndian(UInt32(item.image.count)))
            ico.append(littleEndian(UInt32(imageOffset)))
            imageOffset += item.image.count
        }
        for item in images {
            ico.append(item.image)
        }
        return ico
    }

    private func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}

import Foundation
import Compression

// MARK: - Hatalar

enum ZipError: LocalizedError {
    case notAnArchive
    case corrupted(String)
    case unsupportedCompression(UInt16)
    case missingEntry(String)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "Dosya bir ZIP arşivi değil."
        case .corrupted(let detail):
            return "Arşiv okunamadı: \(detail)"
        case .unsupportedCompression(let method):
            return "Desteklenmeyen sıkıştırma yöntemi (\(method))."
        case .missingEntry(let name):
            return "Arşivde '\(name)' girdisi bulunamadı."
        }
    }
}

// MARK: - Girdi

struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
    let crc32: UInt32
}

// MARK: - Minimal ZIP okuyucu
//
// Foundation'da hazır bir ZIP arşiv okuyucusu bulunmadığı için (ZIPFoundation vb.
// harici bağımlılık gerektirir) burada bağımlılıksız bir okuyucu yazıldı.
// Merkezi dizin (Central Directory) okunur; ZIP64 uzantısı ve deflate
// sıkıştırması desteklenir.

final class ZipArchive {
    private let data: Data
    private(set) var entries: [String: ZipEntry] = [:]
    private(set) var entryOrder: [String] = []

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        try readCentralDirectory()
    }

    init(data: Data) throws {
        self.data = data
        try readCentralDirectory()
    }

    // MARK: Bayt okuma yardımcıları

    private func u16(_ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func u32(_ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func u64(_ offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << (8 * UInt64(index))
        }
        return value
    }

    // MARK: Merkezi dizin

    private func readCentralDirectory() throws {
        guard let eocd = locateEndOfCentralDirectory() else {
            throw ZipError.notAnArchive
        }

        var entryCount = Int(u16(eocd + 10) ?? 0)
        var directoryOffset = Int(u32(eocd + 16) ?? 0)

        // ZIP64 gerekliyse genişletilmiş kayıtları oku.
        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF || directoryOffset == -1 {
            if let (count, offset) = readZip64Locator(near: eocd) {
                entryCount = count
                directoryOffset = offset
            }
        }

        guard directoryOffset >= 0, directoryOffset < data.count else {
            throw ZipError.corrupted("Merkezi dizin ofseti geçersiz.")
        }

        var cursor = directoryOffset
        for _ in 0..<entryCount {
            guard let signature = u32(cursor), signature == 0x0201_4B50 else { break }
            guard
                let method = u16(cursor + 10),
                let crc = u32(cursor + 16),
                let compressed = u32(cursor + 20),
                let uncompressed = u32(cursor + 24),
                let nameLength = u16(cursor + 28),
                let extraLength = u16(cursor + 30),
                let commentLength = u16(cursor + 32),
                let localOffset = u32(cursor + 42)
            else { break }

            let nameStart = cursor + 46
            guard nameStart + Int(nameLength) <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<(nameStart + Int(nameLength)))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""

            let extraStart = nameStart + Int(nameLength)
            let extraEnd = min(extraStart + Int(extraLength), data.count)
            let extra = extraStart < extraEnd ? data.subdata(in: extraStart..<extraEnd) : Data()

            var finalCompressed = UInt64(compressed)
            var finalUncompressed = UInt64(uncompressed)
            var finalLocalOffset = UInt64(localOffset)

            // ZIP64 ek alanı
            if finalUncompressed == 0xFFFF_FFFF || finalCompressed == 0xFFFF_FFFF || finalLocalOffset == 0xFFFF_FFFF {
                var extraCursor = 0
                while extraCursor + 4 <= extra.count {
                    let headerID = UInt16(extra[extraCursor]) | (UInt16(extra[extraCursor + 1]) << 8)
                    let size = Int(UInt16(extra[extraCursor + 2]) | (UInt16(extra[extraCursor + 3]) << 8))
                    let payloadStart = extraCursor + 4
                    guard payloadStart + size <= extra.count else { break }
                    if headerID == 0x0001 {
                        var payloadCursor = payloadStart
                        if finalUncompressed == 0xFFFF_FFFF, let value = readUInt64(extra, at: &payloadCursor) {
                            finalUncompressed = value
                        }
                        if finalCompressed == 0xFFFF_FFFF, let value = readUInt64(extra, at: &payloadCursor) {
                            finalCompressed = value
                        }
                        if finalLocalOffset == 0xFFFF_FFFF, let value = readUInt64(extra, at: &payloadCursor) {
                            finalLocalOffset = value
                        }
                    }
                    extraCursor = payloadStart + size
                }
            }

            if !name.isEmpty {
                let entry = ZipEntry(
                    name: name,
                    method: method,
                    compressedSize: Int(finalCompressed),
                    uncompressedSize: Int(finalUncompressed),
                    localHeaderOffset: Int(finalLocalOffset),
                    crc32: crc
                )
                if entries[name] == nil { entryOrder.append(name) }
                entries[name] = entry
            }

            cursor = extraStart + Int(extraLength) + Int(commentLength)
        }

        if entries.isEmpty {
            throw ZipError.corrupted("Arşivde hiç girdi bulunamadı.")
        }
    }

    private func readUInt64(_ buffer: Data, at cursor: inout Int) -> UInt64? {
        guard cursor + 8 <= buffer.count else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(buffer[cursor + index]) << (8 * UInt64(index))
        }
        cursor += 8
        return value
    }

    private func locateEndOfCentralDirectory() -> Int? {
        let minimumSize = 22
        guard data.count >= minimumSize else { return nil }
        let lowerBound = max(0, data.count - (minimumSize + 65_535))
        var index = data.count - minimumSize
        while index >= lowerBound {
            if data[index] == 0x50, data[index + 1] == 0x4B, data[index + 2] == 0x05, data[index + 3] == 0x06 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private func readZip64Locator(near eocd: Int) -> (count: Int, offset: Int)? {
        let locatorOffset = eocd - 20
        guard locatorOffset >= 0, u32(locatorOffset) == 0x0706_4B50, let zip64Offset = u64(locatorOffset + 8) else {
            return nil
        }
        let base = Int(zip64Offset)
        guard base >= 0, base + 56 <= data.count, u32(base) == 0x0606_4B50 else { return nil }
        guard let count = u64(base + 32), let offset = u64(base + 48) else { return nil }
        return (Int(count), Int(offset))
    }

    // MARK: Girdi okuma

    func contains(_ name: String) -> Bool {
        entries[name] != nil
    }

    func data(for name: String) throws -> Data {
        guard let entry = entries[name] else { throw ZipError.missingEntry(name) }
        let header = entry.localHeaderOffset
        guard u32(header) == 0x0403_4B50, let nameLength = u16(header + 26), let extraLength = u16(header + 28) else {
            throw ZipError.corrupted("Yerel başlık okunamadı: \(name)")
        }
        let start = header + 30 + Int(nameLength) + Int(extraLength)
        let end = start + entry.compressedSize
        guard start >= 0, end <= data.count, start <= end else {
            throw ZipError.corrupted("Veri aralığı geçersiz: \(name)")
        }
        let payload = data.subdata(in: start..<end)

        switch entry.method {
        case 0:
            return payload
        case 8:
            guard let inflated = inflate(payload, expectedSize: entry.uncompressedSize) else {
                throw ZipError.corrupted("Sıkıştırılmış veri çözülemedi: \(name)")
            }
            return inflated
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    // MARK: Deflate çözme (Compression framework, COMPRESSION_ZLIB = ham DEFLATE)

    private func inflate(_ input: Data, expectedSize: Int) -> Data? {
        if input.isEmpty { return Data() }

        var bufferSize = expectedSize > 0 ? expectedSize : max(input.count * 4, 1 << 16)
        for _ in 0..<6 {
            var output = Data(count: bufferSize)
            let decoded = output.withUnsafeMutableBytes { destination -> Int in
                input.withUnsafeBytes { source -> Int in
                    guard
                        let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                        let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                    else { return 0 }
                    return compression_decode_buffer(
                        destinationBase, bufferSize,
                        sourceBase, input.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            if decoded > 0 {
                output.count = decoded
                return output
            }
            bufferSize *= 4
        }
        return nil
    }
}

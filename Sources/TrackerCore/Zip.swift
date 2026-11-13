import Compression
import Foundation

/// Just enough ZIP to write .xlsx files (stored entries) and read them (stored/deflate).
enum Zip {
    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    /// Store-only archive (no compression) — Excel and Numbers read these fine.
    static func write(_ files: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        // 2026-01-01 00:00 in DOS format
        let dosTime = 0, dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1
        for (name, data) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            var local: [UInt8] = le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0)
            local += le16(dosTime) + le16(dosDate) + le32(crc)
            local += le32(UInt32(data.count)) + le32(UInt32(data.count))
            local += le16(nameData.count) + le16(0)
            out.append(contentsOf: local); out.append(nameData); out.append(data)

            var cd: [UInt8] = le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(0)
            cd += le16(dosTime) + le16(dosDate) + le32(crc)
            cd += le32(UInt32(data.count)) + le32(UInt32(data.count))
            cd += le16(nameData.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset)
            central.append(contentsOf: cd); central.append(nameData)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        var end: [UInt8] = le32(0x0605_4B50) + le16(0) + le16(0)
        end += le16(files.count) + le16(files.count) + le32(UInt32(central.count)) + le32(cdOffset) + le16(0)
        out.append(contentsOf: end)
        return out
    }

    struct ReadError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// name → contents, for stored and deflated entries.
    static func read(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard bytes.count >= 22 else { throw ReadError(message: "Not a zip file") }
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 65_557) {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ReadError(message: "Not a zip/xlsx file") }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var out: [String: Data] = [:]
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else { break }
            let method = u16(p + 10)
            let csize = u32(p + 20), usize = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let local = u32(p + 42)
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + elen + clen
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= bytes.count else { continue }
            let comp = Data(bytes[start..<(start + csize)])
            switch method {
            case 0: out[name] = comp
            case 8: out[name] = try inflate(comp, size: usize)
            default: continue
            }
        }
        return out
    }

    static func inflate(_ data: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        var dst = [UInt8](repeating: 0, count: size)
        let n = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            compression_decode_buffer(&dst, size, src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                      nil, COMPRESSION_ZLIB)
        }
        guard n > 0 else { throw ReadError(message: "Couldn't decompress the file") }
        return Data(dst.prefix(n))
    }
}

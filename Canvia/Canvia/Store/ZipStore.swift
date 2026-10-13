// A ZIP archive in STORE mode — every file kept as it is, uncompressed —
// written and read by hand, as the app takes no dependencies: what a
// backup is. The Android twin writes the same with java.util.zip's STORED
// entries, so either phone reads the other's. Names are UTF-8 (flag bit
// 11); no ZIP64, so an archive stays under 4 GB and 65,535 files.

import Foundation

enum ZipStore {

    enum ZipError: LocalizedError {
        case notAZip
        case compressed(String)
        case tooBig
        var errorDescription: String? {
            switch self {
            case .notAZip: return "This file is not a Canvia backup."
            case .compressed: return "This backup was packed in a way Canvia cannot read."
            case .tooBig: return "There is too much to fit in one backup."
            }
        }
    }

    /// The CRC-32 a ZIP entry carries (the IEEE polynomial, reflected), by
    /// table.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xffff_ffff
    }

    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xedb8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// MS-DOS time and date, as a ZIP entry stamps them.
    static func dosStamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max((c.year ?? 1980) - 1980, 0)
        let time = ((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2)
        let day = (year << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1)
        return (UInt16(truncatingIfNeeded: time), UInt16(truncatingIfNeeded: day))
    }

    // MARK: writing

    /// Writes entries one at a time straight to a file, keeping only the
    /// directory in memory, then the directory at the end. Used from one
    /// task at a time.
    final class Writer: @unchecked Sendable {
        private let handle: FileHandle
        private var offset: UInt64 = 0
        private var directory = Data()
        private var count = 0
        private let stamp: (time: UInt16, date: UInt16)

        init(url: URL, date: Date = Date()) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            stamp = ZipStore.dosStamp(date)
        }

        /// One file, as `name` ("designs/doc_1.canvia.json").
        func add(_ name: String, _ data: Data) throws {
            let nameBytes = Data(name.utf8)
            guard offset + UInt64(data.count) + UInt64(nameBytes.count) + 30 < UInt64(UInt32.max),
                  data.count < Int(UInt32.max), count < 65_535 else { throw ZipError.tooBig }
            let crc = ZipStore.crc32(data)
            var local = Data()
            local.le32(0x0403_4b50)
            local.le16(20)                 // version needed
            local.le16(0x0800)             // UTF-8 names
            local.le16(0)                  // stored
            local.le16(stamp.time)
            local.le16(stamp.date)
            local.le32(crc)
            local.le32(UInt32(data.count))
            local.le32(UInt32(data.count))
            local.le16(UInt16(nameBytes.count))
            local.le16(0)                  // no extra field
            local.append(nameBytes)

            var central = Data()
            central.le32(0x0201_4b50)
            central.le16(20)               // made by
            central.le16(20)
            central.le16(0x0800)
            central.le16(0)
            central.le16(stamp.time)
            central.le16(stamp.date)
            central.le32(crc)
            central.le32(UInt32(data.count))
            central.le32(UInt32(data.count))
            central.le16(UInt16(nameBytes.count))
            central.le16(0)                // extra
            central.le16(0)                // comment
            central.le16(0)                // disk
            central.le16(0)                // internal attributes
            central.le32(0)                // external attributes
            central.le32(UInt32(offset))
            central.append(nameBytes)

            try handle.write(contentsOf: local)
            try handle.write(contentsOf: data)
            offset += UInt64(local.count + data.count)
            directory.append(central)
            count += 1
        }

        /// The directory and its end record, and the file closed.
        func finish() throws {
            var end = Data()
            end.le32(0x0605_4b50)
            end.le16(0)
            end.le16(0)
            end.le16(UInt16(count))
            end.le16(UInt16(count))
            end.le32(UInt32(directory.count))
            end.le32(UInt32(offset))
            end.le16(0)
            try handle.write(contentsOf: directory)
            try handle.write(contentsOf: end)
            try handle.close()
        }

        /// Closed without its directory, for a backup given up on.
        func abandon() {
            try? handle.close()
        }
    }

    // MARK: reading

    /// The files of an archive, by name, read from its directory. The
    /// archive is mapped rather than read in, and a file's bytes are taken
    /// only when asked for.
    struct Reader {
        let data: Data
        /// Each file's bytes, as a range of `data`.
        let entries: [String: Range<Int>]

        init(url: URL) throws {
            try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
        }

        init(data: Data) throws {
            self.data = data
            let n = data.count
            guard n >= 22 else { throw ZipError.notAZip }
            // The end record, within the last 64 KB and its own 22 bytes.
            var end = -1
            var i = n - 22
            while i >= max(0, n - 22 - 65_535) {
                if data.u32(i) == 0x0605_4b50 { end = i; break }
                i -= 1
            }
            guard end >= 0 else { throw ZipError.notAZip }
            let total = data.u16(end + 10)
            var at = Int(data.u32(end + 16))
            var found: [String: Range<Int>] = [:]
            for _ in 0..<total {
                guard at + 46 <= n, data.u32(at) == 0x0201_4b50 else { throw ZipError.notAZip }
                let method = data.u16(at + 10)
                let compressed = Int(data.u32(at + 20))
                let size = Int(data.u32(at + 24))
                let nameLength = data.u16(at + 28)
                let extraLength = data.u16(at + 30)
                let commentLength = data.u16(at + 32)
                let local = Int(data.u32(at + 42))
                guard at + 46 + nameLength <= n else { throw ZipError.notAZip }
                let name = String(decoding: data.subdata(in: (data.startIndex + at + 46)..<(data.startIndex + at + 46 + nameLength)),
                                  as: UTF8.self)
                at += 46 + nameLength + extraLength + commentLength
                // A folder's own entry holds nothing.
                if name.hasSuffix("/") { continue }
                guard method == 0, compressed == size else { throw ZipError.compressed(name) }
                guard local + 30 <= n, data.u32(local) == 0x0403_4b50 else { throw ZipError.notAZip }
                let start = local + 30 + data.u16(local + 26) + data.u16(local + 28)
                guard start + size <= n else { throw ZipError.notAZip }
                found[name] = start..<(start + size)
            }
            entries = found
        }

        /// A file's bytes, or nil when the archive has none of that name.
        func file(_ name: String) -> Data? {
            guard let range = entries[name] else { return nil }
            return data.subdata(in: (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound))
        }

        /// The names under a folder ("designs/"), sorted.
        func names(in folder: String) -> [String] {
            entries.keys.filter { $0.hasPrefix(folder) && $0.count > folder.count }.sorted()
        }
    }
}

// Little-endian numbers, as a ZIP holds them.
extension Data {
    fileprivate mutating func le16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8(value >> 8))
    }

    fileprivate mutating func le32(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xff)) }
    }

    /// The two bytes at `offset` from the start, as a number.
    fileprivate func u16(_ offset: Int) -> Int {
        let i = startIndex + offset
        return Int(self[i]) | Int(self[i + 1]) << 8
    }

    fileprivate func u32(_ offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}

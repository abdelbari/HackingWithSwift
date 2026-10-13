// A ZIP archive written an entry at a time, for the PowerPoint export (a
// .pptx is a ZIP of XML parts and pictures).
//
// Every entry is stored as it is — no compression — which every reader
// opens, and which needs nothing past Foundation: no third-party library,
// as on the Android twin. The pictures inside are PNG and JPEG, already
// compressed, so deflate would win little but the XML. Each entry carries
// the same fixed date (1 January 1980, the format's first day), so the same
// design makes the same bytes on every run.
//
// Bytes go to `sink` as they are made — a file, for an export — so only one
// entry is ever held at once; the central directory, a few dozen bytes an
// entry, is kept until `finish`.

import Foundation

final class ZipWriter {

    enum ZipError: LocalizedError {
        case tooLarge, finished

        var errorDescription: String? {
            switch self {
            case .tooLarge: return "the file is too large"
            case .finished: return "the file was already finished"
            }
        }
    }

    private let sink: (Data) throws -> Void
    private var offset: UInt64 = 0
    private var central = Data()
    private var count = 0
    private var done = false

    init(sink: @escaping (Data) throws -> Void) {
        self.sink = sink
    }

    /// One file of the archive, under `name` ("ppt/slides/slide1.xml").
    func add(_ name: String, _ data: Data) throws {
        guard !done else { throw ZipError.finished }
        let nameBytes = Data(name.utf8)
        // A plain archive counts in 32 bits; past that it would need ZIP64,
        // which no export of this app comes near.
        guard offset + UInt64(data.count) + 30 + UInt64(nameBytes.count) < UInt64(UInt32.max),
              count < Int(UInt16.max), nameBytes.count < Int(UInt16.max) else { throw ZipError.tooLarge }
        let crc = Self.crc32(data)
        let size = UInt32(data.count)

        var local = Data()
        Self.put32(0x0403_4b50, &local)
        Self.put16(20, &local)                     // version needed: 2.0
        Self.put16(Self.utf8Flag(name), &local)
        Self.put16(0, &local)                      // stored
        Self.put16(0, &local)                      // time 00:00
        Self.put16(Self.dosDate, &local)
        Self.put32(crc, &local)
        Self.put32(size, &local)                   // compressed: the same
        Self.put32(size, &local)
        Self.put16(UInt16(nameBytes.count), &local)
        Self.put16(0, &local)                      // no extra field
        local.append(nameBytes)

        Self.put32(0x0201_4b50, &central)
        Self.put16(20, &central)                   // made by: 2.0
        Self.put16(20, &central)
        Self.put16(Self.utf8Flag(name), &central)
        Self.put16(0, &central)
        Self.put16(0, &central)
        Self.put16(Self.dosDate, &central)
        Self.put32(crc, &central)
        Self.put32(size, &central)
        Self.put32(size, &central)
        Self.put16(UInt16(nameBytes.count), &central)
        Self.put16(0, &central)                    // extra
        Self.put16(0, &central)                    // comment
        Self.put16(0, &central)                    // disk
        Self.put16(0, &central)                    // internal attributes
        Self.put32(0, &central)                    // external attributes
        Self.put32(UInt32(offset), &central)
        central.append(nameBytes)

        try sink(local)
        try sink(data)
        offset += UInt64(local.count + data.count)
        count += 1
    }

    /// The central directory and its end record, after the last entry.
    func finish() throws {
        guard !done else { throw ZipError.finished }
        guard offset + UInt64(central.count) < UInt64(UInt32.max) else { throw ZipError.tooLarge }
        done = true
        var end = Data()
        Self.put32(0x0605_4b50, &end)
        Self.put16(0, &end)                        // this disk
        Self.put16(0, &end)                        // the directory's disk
        Self.put16(UInt16(count), &end)
        Self.put16(UInt16(count), &end)
        Self.put32(UInt32(central.count), &end)
        Self.put32(UInt32(offset), &end)
        Self.put16(0, &end)                        // no comment
        try sink(central)
        try sink(end)
    }

    // MARK: the format's pieces

    /// 1 January 1980 in MS-DOS form: (year − 1980) << 9 | month << 5 | day.
    static let dosDate: UInt16 = (0 << 9) | (1 << 5) | 1

    /// Bit 11 says the name is UTF-8; set only for a name that needs it.
    private static func utf8Flag(_ name: String) -> UInt16 {
        name.utf8.contains { $0 >= 0x80 } ? 0x0800 : 0
    }

    private static func put16(_ value: UInt16, _ data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8(value >> 8))
    }

    private static func put32(_ value: UInt32, _ data: inout Data) {
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> UInt32(shift)) & 0xff)) }
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// The CRC-32 ZIP checks each entry by (the IEEE polynomial, reflected).
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        let table = crcTable
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

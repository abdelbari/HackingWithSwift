// The print-ready PDF in CMYK, for a print shop: each sheet one picture in
// press ink — DeviceCMYK, eight bits a channel, FlateDecode — over its whole
// area at dpi, the crop marks drawn over it as lines of black ink alone
// (0/0/0/100, registration as a shop reads it), and the sheet's TrimBox and
// BleedBox set as the RGB PDF's are. The Android twin's CmykPdf, object for
// object and byte for byte up to the packed ink — Quartz's PDF context would
// write its own colour space — written a band of rows at a time, never
// holding a sheet's ink whole. The pixels become ink by Cmyk.

import Compression
import CoreGraphics
import Foundation

enum CmykPdf {

    /// The dots per inch a CMYK sheet is drawn at: flattened, as Flatten
    /// draws a page.
    static let dpi = 300.0

    /// Rows of a sheet read, inked and packed at once.
    static let band = 128

    /// A sheet's ink packs to about half (FlateDecode): what the size note
    /// counts.
    static let packedShare = 0.5

    /// One sheet's picture: `width` × `height` pixels, whose `rows` fill an
    /// array with `count` rows from `top`, 0xAARRGGBB, row after row.
    struct Sheet {
        var width: Int
        var height: Int
        var rows: (_ top: Int, _ count: Int, _ into: inout [UInt32]) -> Void
    }

    /// The pixels of a sheet `size` points across and down at dpi.
    static func pixels(_ size: CGSize) -> (width: Int, height: Int) {
        (max(1, Int((Double(size.width) * dpi / 72).rounded())), max(1, Int((Double(size.height) * dpi / 72).rounded())))
    }

    /// About how many bytes `sheets` sheets of `size` come to.
    static func estimatedBytes(sheets: Int, size: CGSize) -> Int {
        let px = pixels(size)
        return Int((Double(sheets) * Double(px.width) * Double(px.height) * 4 * packedShare).rounded())
    }

    /// What the colour profile says of a CMYK PDF of about `bytes`:
    /// "CMYK · flattened · about 24 MB", in whole megabytes, at least one.
    static func note(_ bytes: Int) -> String {
        tr("CMYK · flattened · about %d MB", max(1, Int((Double(bytes) / 1_000_000).rounded())))
    }

    /// `sheets` written as one PDF, each `size` points — what the tests read
    /// whole; the app writes a sheet at a time through SheetWriter.
    static func write(_ sheets: [Sheet], size: CGSize, trim: [CGRect?], bleed: [CGRect?],
                      marks: [[(CGPoint, CGPoint)]], band: Int = CmykPdf.band) throws -> Data {
        var out = Data()
        let writer = try SheetWriter(sheets: sheets.count, size: size) { out.append($0) }
        for (i, sheet) in sheets.enumerated() {
            try writer.add(sheet, trim: trim.indices.contains(i) ? trim[i] : nil,
                           bleed: bleed.indices.contains(i) ? bleed[i] : nil,
                           marks: marks.indices.contains(i) ? marks[i] : [], band: band)
        }
        try writer.finish()
        return out
    }

    enum WriteError: Error { case deflate }

    /// The PDF written as it goes: the catalogue and the page tree for
    /// `sheets` sheets first, then each sheet as it is added — its page, its
    /// contents, its picture and the picture's length — then the
    /// cross-reference table.
    final class SheetWriter {
        private let size: CGSize
        private let sheets: Int
        private let emit: (Data) throws -> Void
        private var count = 0
        private var offsets: [Int: Int] = [:]
        private var added = 0

        init(sheets: Int, size: CGSize, emit: @escaping (Data) throws -> Void) throws {
            self.sheets = sheets
            self.size = size
            self.emit = emit
            // A binary comment after the header, so nothing takes it for text.
            try text("%PDF-1.4\n")
            try bytes(Data([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]))
            try begin(1)
            try text("<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
            try begin(2)
            let kids = (0..<sheets).map { "\(SheetWriter.first($0)) 0 R" }.joined(separator: " ")
            try text("<< /Type /Pages /Kids [\(kids)] /Count \(sheets) >>\nendobj\n")
        }

        /// 1 the catalogue, 2 the page tree, then four a sheet.
        private static func first(_ i: Int) -> Int { 3 + 4 * i }

        /// The next sheet: its picture over the whole of it, `marks` (in
        /// sheet points from the top left, as PrintLayout gives them) over
        /// that, and `trim` and `bleed` (PDF points up from the bottom) its
        /// TrimBox and BleedBox when there are any.
        func add(_ sheet: Sheet, trim: CGRect?, bleed: CGRect?, marks: [(CGPoint, CGPoint)],
                 band: Int = CmykPdf.band) throws {
            let page = SheetWriter.first(added)
            added += 1
            var boxes = ""
            if let trim { boxes += " /TrimBox " + SheetWriter.box(trim) }
            if let bleed { boxes += " /BleedBox " + SheetWriter.box(bleed) }
            let w = SheetWriter.num(Double(size.width)), h = SheetWriter.num(Double(size.height))
            try begin(page)
            try text("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(w) \(h)]\(boxes) "
                     + "/Resources << /XObject << /Im0 \(page + 2) 0 R >> >> /Contents \(page + 1) 0 R >>\nendobj\n")
            let contents = Data(SheetWriter.contents(size, marks: marks).utf8)
            try begin(page + 1)
            try text("<< /Length \(contents.count) >>\nstream\n")
            try bytes(contents)
            try text("\nendstream\nendobj\n")
            try begin(page + 2)
            try text("<< /Type /XObject /Subtype /Image /Width \(sheet.width) /Height \(sheet.height) "
                     + "/ColorSpace /DeviceCMYK /BitsPerComponent 8 /Filter /FlateDecode /Length \(page + 3) 0 R >>\nstream\n")
            let start = count
            try ink(sheet, band: band)
            let length = count - start
            try text("\nendstream\nendobj\n")
            try begin(page + 3)
            try text("\(length)\nendobj\n")
        }

        /// The cross-reference table and the trailer.
        func finish() throws {
            let objects = 3 + 4 * sheets
            let xref = count
            var table = "xref\n0 \(objects)\n0000000000 65535 f \n"
            for n in 1..<objects {
                let at = String(offsets[n] ?? 0)
                table += String(repeating: "0", count: max(0, 10 - at.count)) + at + " 00000 n \n"
            }
            try text(table)
            try text("trailer\n<< /Size \(objects) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n")
        }

        private func begin(_ number: Int) throws {
            offsets[number] = count
            try text("\(number) 0 obj\n")
        }

        private func text(_ string: String) throws { try bytes(Data(string.utf8)) }

        private func bytes(_ data: Data) throws {
            try emit(data)
            count += data.count
        }

        /// A sheet's drawing: the picture over the whole sheet, then each
        /// mark a half-point line of black ink alone.
        private static func contents(_ size: CGSize, marks: [(CGPoint, CGPoint)]) -> String {
            let h = Double(size.height)
            var out = "q \(num(Double(size.width))) 0 0 \(num(h)) 0 0 cm /Im0 Do Q\n"
            guard !marks.isEmpty else { return out }
            out += "0 0 0 1 K 0.5 w\n"
            for (a, b) in marks {
                // PDF measures up from the bottom.
                out += "\(num(Double(a.x))) \(num(h - Double(a.y))) m \(num(Double(b.x))) \(num(h - Double(b.y))) l S\n"
            }
            return out
        }

        /// The sheet's pixels as ink, packed, a band at a time.
        private func ink(_ sheet: Sheet, band rows: Int) throws {
            let flate = try Flate { [unowned self] in try self.bytes($0) }
            let band = min(max(rows, 1), max(sheet.height, 1))
            var argb = [UInt32](repeating: 0, count: sheet.width * band)
            var cmyk = [UInt8](repeating: 0, count: sheet.width * band * 4)
            var top = 0
            while top < sheet.height {
                let n = min(band, sheet.height - top)
                sheet.rows(top, n, &argb)
                Cmyk.convert(argb, from: 0, count: sheet.width * n, into: &cmyk, at: 0)
                try flate.write(cmyk, count: sheet.width * n * 4)
                top += n
            }
            try flate.finish()
        }

        private static func box(_ b: CGRect) -> String {
            "[\(num(Double(b.minX))) \(num(Double(b.minY))) \(num(Double(b.maxX))) \(num(Double(b.maxY)))]"
        }

        static func num(_ v: Double) -> String {
            String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), v)
        }
    }

    /// Bytes packed as FlateDecode reads them: a zlib stream — its two-byte
    /// header, raw DEFLATE (Compression's ZLIB) and the Adler-32 of what went
    /// in — handed on as it is made.
    final class Flate {
        private let stream: UnsafeMutablePointer<compression_stream>
        private let buffer: UnsafeMutablePointer<UInt8>
        private let capacity = 64 * 1024
        private let emit: (Data) throws -> Void
        private var adlerA: UInt32 = 1
        private var adlerB: UInt32 = 0
        private var open = true

        init(emit: @escaping (Data) throws -> Void) throws {
            self.emit = emit
            stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            guard compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                open = false
                throw WriteError.deflate
            }
            // Deflate, a 32K window, the default level.
            try emit(Data([0x78, 0x9C]))
        }

        deinit {
            if open { compression_stream_destroy(stream) }
            stream.deallocate()
            buffer.deallocate()
        }

        /// The first `count` of `bytes`, packed.
        func write(_ bytes: [UInt8], count: Int) throws {
            guard count > 0 else { return }
            adler(bytes, count: count)
            try bytes.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                stream.pointee.src_ptr = base
                stream.pointee.src_size = count
                try pump(finalize: false)
            }
        }

        /// The end of the stream, and its Adler-32.
        func finish() throws {
            stream.pointee.src_ptr = UnsafePointer(buffer)
            stream.pointee.src_size = 0
            try pump(finalize: true)
            let sum = adlerB << 16 | adlerA
            try emit(Data([UInt8(sum >> 24 & 0xff), UInt8(sum >> 16 & 0xff), UInt8(sum >> 8 & 0xff), UInt8(sum & 0xff)]))
        }

        private func pump(finalize: Bool) throws {
            let flags = finalize ? Int32(bitPattern: COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = capacity
                let status = compression_stream_process(stream, flags)
                let made = capacity - stream.pointee.dst_size
                if made > 0 { try emit(Data(bytes: buffer, count: made)) }
                if status == COMPRESSION_STATUS_END { return }
                guard status == COMPRESSION_STATUS_OK else { throw WriteError.deflate }
                // All taken in, and room to spare: nothing more for now.
                if !finalize && stream.pointee.src_size == 0 && stream.pointee.dst_size > 0 { return }
            }
        }

        /// Adler-32 over the bytes as they go in, summed in runs short
        /// enough never to overflow.
        private func adler(_ bytes: [UInt8], count: Int) {
            var a = adlerA, b = adlerB
            var i = 0
            while i < count {
                let end = min(i + 5552, count)
                while i < end {
                    a &+= UInt32(bytes[i])
                    b &+= a
                    i += 1
                }
                a %= 65521
                b %= 65521
            }
            adlerA = a
            adlerB = b
        }
    }
}

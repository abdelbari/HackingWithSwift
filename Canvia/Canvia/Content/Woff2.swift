// A WOFF2 web font unpacked into the TrueType or OpenType font it holds
// (W3C WOFF 2.0), in pure code — the Android twin's Woff2, rule for rule, so
// a font of your own added from a .woff2 is the same bytes, and the same
// hash, on either phone (CustomFonts.sfnt):
//
//  - the table directory read (a known tag's index or a tag of its own, the
//    original length and, for a transformed table, its transformed length,
//    as UIntBase128), and the tables' stream inflated whole (Brotli);
//  - a transformed glyf (version 0) rebuilt glyph by glyph, with its loca:
//    a simple glyph's points from their triplets, its flags written as the
//    reference decoder writes them (a flag repeated with its count, a
//    coordinate in one byte when it fits, none when unchanged), its
//    bounding box as given or worked out from its points; a composite's
//    components as they are; each glyph padded to four bytes; loca long or
//    short as the transform says;
//  - a transformed hmtx (version 1) given back the side bearings it left
//    out, from each glyph's least x;
//  - every other table as it came;
//  - the font written with its tables sorted by tag, each checksum worked
//    out (head's with its checksum adjustment as zero), each table padded
//    to four bytes, and head's checksum adjustment set last (0xB1B0AFBA
//    less the whole font's sum).
//
// A collection, a table transformed another way, and anything that does
// not read are not unpacked.

import Foundation

enum Woff2 {

    static let signature = 0x774F_4632 // "wOF2"

    /// The tags a directory entry names by index, 0 to 62.
    private static let known: [Int] = [
        "cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post", "cvt ", "fpgm", "glyf", "loca", "prep", "CFF ", "VORG", "EBDT",
        "EBLC", "gasp", "hdmx", "kern", "LTSH", "PCLT", "VDMX", "vhea", "vmtx", "BASE", "GDEF", "GPOS", "GSUB", "EBSC", "JSTF", "MATH",
        "CBDT", "CBLC", "COLR", "CPAL", "SVG ", "sbix", "acnt", "avar", "bdat", "bloc", "bsln", "cvar", "fdsc", "feat", "fmtx", "fvar",
        "gvar", "hsty", "just", "lcar", "mort", "morx", "opbd", "prop", "trak", "Zapf", "Silf", "Glat", "Gloc", "Feat", "Sill",
    ].map(tagOf)

    private static func tagOf(_ name: String) -> Int {
        name.unicodeScalars.reduce(0) { ($0 << 8) | Int($1.value) }
    }

    private static let glyfTag = tagOf("glyf")
    private static let locaTag = tagOf("loca")
    private static let hmtxTag = tagOf("hmtx")
    private static let headTag = tagOf("head")
    private static let hheaTag = tagOf("hhea")
    private static let ttcfTag = 0x7474_6366

    struct Unreadable: Error {}

    private final class Table {
        let tag: Int
        let transformed: Bool
        let length: Int
        var data: [UInt8] = []

        init(tag: Int, transformed: Bool, length: Int) {
            self.tag = tag
            self.transformed = transformed
            self.length = length
        }
    }

    /// `data`'s font, at most `limit` bytes; nil when it is not a WOFF2
    /// this reads.
    static func unpack(_ data: Data, limit: Int) -> Data? {
        guard let font = try? unpacked([UInt8](data), limit: limit) else { return nil }
        return Data(font)
    }

    private static func unpacked(_ bytes: [UInt8], limit: Int) throws -> [UInt8]? {
        let r = Cursor(bytes)
        guard try r.u32() == signature else { return nil }
        let flavor = try r.u32()
        if flavor == ttcfTag { return nil }
        _ = try r.u32() // length
        let count = try r.u16()
        _ = try r.u16() // reserved
        let total = try r.u32()
        if total > limit { return nil }
        let compressed = try r.u32()
        r.at = 48
        var tables: [Table] = []
        for _ in 0..<count {
            let flags = try r.u8()
            let tag = try flags & 63 == 63 ? r.u32() : known[flags & 63]
            let version = (flags >> 6) & 3
            let orig = try r.base128()
            let transformed = tag == glyfTag || tag == locaTag ? version == 0 : version != 0
            if transformed && tag != glyfTag && tag != locaTag && !(tag == hmtxTag && version == 1) { return nil }
            let length = try transformed ? r.base128() : orig
            tables.append(Table(tag: tag, transformed: transformed, length: length))
        }
        let streamSize = tables.reduce(0) { $0 + $1.length }
        if streamSize > limit || r.at + compressed > bytes.count { return nil }
        let stream = try Brotli.decompress(Array(bytes[r.at..<(r.at + compressed)]), limit: streamSize)
        if stream.count != streamSize { return nil }
        var at = 0
        for t in tables {
            t.data = Array(stream[at..<(at + t.length)])
            at += t.length
        }
        let glyf = tables.first { $0.tag == glyfTag }
        let loca = tables.first { $0.tag == locaTag }
        var xMins: [Int]?
        if let glyf, glyf.transformed {
            guard let loca, loca.transformed, let rebuilt = try rebuiltGlyf(glyf.data) else { return nil }
            glyf.data = rebuilt.glyf
            loca.data = rebuilt.loca
            xMins = rebuilt.xMins
        } else if let loca, loca.transformed {
            return nil
        }
        if let hmtx = tables.first(where: { $0.tag == hmtxTag }), hmtx.transformed {
            guard let hhea = tables.first(where: { $0.tag == hheaTag }), let xMins else { return nil }
            let metrics = Cursor(hhea.data)
            metrics.at = 34
            guard let rebuilt = try rebuiltHmtx(hmtx.data, xMins: xMins, metrics: try metrics.u16()) else { return nil }
            hmtx.data = rebuilt
        }
        return written(flavor: flavor, tables.sorted { $0.tag < $1.tag }, limit: limit)
    }

    // MARK: glyf and loca

    private static let onCurve = 0x01
    private static let xShort = 0x02
    private static let yShort = 0x04
    private static let repeatFlag = 0x08
    private static let xSame = 0x10
    private static let ySame = 0x20
    private static let overlapSimple = 0x40

    /// The transformed glyf's glyphs rebuilt: the glyf and loca tables, and
    /// each glyph's least x (0 for an empty one).
    private static func rebuiltGlyf(_ data: [UInt8]) throws -> (glyf: [UInt8], loca: [UInt8], xMins: [Int])? {
        let head = Cursor(data)
        _ = try head.u16() // reserved
        let options = try head.u16()
        let glyphs = try head.u16()
        let indexFormat = try head.u16()
        var sizes: [Int] = []
        for _ in 0..<7 { sizes.append(try head.u32()) }
        var offset = head.at
        func stream(_ size: Int) throws -> Cursor {
            if size < 0 || offset + size > data.count { throw Unreadable() }
            let s = Cursor(data, at: offset, end: offset + size)
            offset += size
            return s
        }
        let contours = try stream(sizes[0])
        let points = try stream(sizes[1])
        let flags = try stream(sizes[2])
        let glyph = try stream(sizes[3])
        let composite = try stream(sizes[4])
        let bboxBitmapSize = 4 * ((glyphs + 31) / 32)
        let bboxAll = try stream(sizes[5])
        if bboxBitmapSize > sizes[5] { throw Unreadable() }
        let bboxBitmap = bboxAll.at
        let bbox = Cursor(data, at: bboxAll.at + bboxBitmapSize, end: bboxAll.end)
        let instructions = try stream(sizes[6])
        let overlap = try options & 1 != 0 ? stream((glyphs + 7) >> 3).at : -1
        func hasBox(_ i: Int) -> Bool { Int(data[bboxBitmap + (i >> 3)]) & (0x80 >> (i & 7)) != 0 }
        func overlaps(_ i: Int) -> Bool { overlap >= 0 && Int(data[overlap + (i >> 3)]) & (0x80 >> (i & 7)) != 0 }

        var out: [UInt8] = []
        var offsets = [Int](repeating: 0, count: glyphs + 1)
        var xMins = [Int](repeating: 0, count: glyphs)
        for i in 0..<glyphs {
            offsets[i] = out.count
            let n = try contours.s16()
            let g = ByteWriter()
            if n == 0 {
                if hasBox(i) { return nil }
            } else if n < 0 {
                if !hasBox(i) { return nil }
                g.s16(-1)
                var box: [Int] = []
                for _ in 0..<4 { box.append(try bbox.s16()) }
                box.forEach(g.s16)
                xMins[i] = box[0]
                var more: Bool
                var instructed = false
                repeat {
                    let f = try composite.u16()
                    var size = 2 + (f & 0x0001 != 0 ? 4 : 2)
                    if f & 0x0008 != 0 {
                        size += 2
                    } else if f & 0x0040 != 0 {
                        size += 4
                    } else if f & 0x0080 != 0 {
                        size += 8
                    }
                    g.u16(f)
                    g.bytes(try composite.bytes(size))
                    if f & 0x0100 != 0 { instructed = true }
                    more = f & 0x0020 != 0
                } while more
                if instructed {
                    let length = try glyph.u255()
                    g.u16(length)
                    g.bytes(try instructions.bytes(length))
                }
            } else {
                var ends = [Int](repeating: 0, count: n)
                var total = 0
                for c in 0..<n {
                    total += try points.u255()
                    ends[c] = total - 1
                }
                var xs = [Int](repeating: 0, count: total)
                var ys = [Int](repeating: 0, count: total)
                var on = [Bool](repeating: false, count: total)
                var x = 0
                var y = 0
                for p in 0..<total {
                    let raw = try flags.u8()
                    on[p] = raw >> 7 == 0
                    let f = raw & 0x7F
                    let (dx, dy) = try triplet(f, glyph)
                    x += dx
                    y += dy
                    xs[p] = x
                    ys[p] = y
                }
                var box = [0, 0, 0, 0]
                if hasBox(i) {
                    for k in 0..<4 { box[k] = try bbox.s16() }
                } else if total > 0 {
                    box = [xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0]
                }
                xMins[i] = box[0]
                let length = try glyph.u255()
                g.s16(n)
                box.forEach(g.s16)
                ends.forEach(g.u16)
                g.u16(length)
                g.bytes(try instructions.bytes(length))
                writePoints(g, xs, ys, on, overlaps(i))
            }
            let bytes = g.out
            out.append(contentsOf: bytes)
            let padded = (bytes.count + 3) & ~3
            if padded > bytes.count { out.append(contentsOf: [UInt8](repeating: 0, count: padded - bytes.count)) }
        }
        offsets[glyphs] = out.count
        let loca = ByteWriter()
        for o in offsets {
            if indexFormat == 0 { loca.u16(o >> 1) } else { loca.u32(o) }
        }
        return (out, loca.out, xMins)
    }

    /// One point's move from its triplet: its flag's low seven bits, the
    /// bytes it takes from the glyph stream.
    private static func triplet(_ f: Int, _ glyph: Cursor) throws -> (Int, Int) {
        if f < 10 {
            let b = try glyph.u8()
            return (0, sign(f, ((f & 14) << 7) + b))
        }
        if f < 20 {
            let b = try glyph.u8()
            return (sign(f, (((f - 10) & 14) << 7) + b), 0)
        }
        if f < 84 {
            let b0 = f - 20
            let b1 = try glyph.u8()
            return (sign(f, 1 + (b0 & 0x30) + (b1 >> 4)), sign(f >> 1, 1 + ((b0 & 0x0C) << 2) + (b1 & 0x0F)))
        }
        if f < 120 {
            let b0 = f - 84
            let b1 = try glyph.u8()
            let b2 = try glyph.u8()
            return (sign(f, 1 + ((b0 / 12) << 8) + b1), sign(f >> 1, 1 + (((b0 % 12) >> 2) << 8) + b2))
        }
        if f < 124 {
            let b1 = try glyph.u8()
            let b2 = try glyph.u8()
            let b3 = try glyph.u8()
            return (sign(f, (b1 << 4) + (b2 >> 4)), sign(f >> 1, ((b2 & 0x0F) << 8) + b3))
        }
        let x1 = try glyph.u8()
        let x2 = try glyph.u8()
        let y1 = try glyph.u8()
        let y2 = try glyph.u8()
        return (sign(f, (x1 << 8) + x2), sign(f >> 1, (y1 << 8) + y2))
    }

    private static func sign(_ flag: Int, _ value: Int) -> Int { flag & 1 != 0 ? value : -value }

    /// A simple glyph's flags and coordinates, as the reference writes
    /// them.
    private static func writePoints(_ g: ByteWriter, _ xs: [Int], _ ys: [Int], _ on: [Bool], _ overlap: Bool) {
        let xBytes = ByteWriter()
        let yBytes = ByteWriter()
        var lastX = 0
        var lastY = 0
        var lastFlag = -1
        var repeats = 0
        var flagBytes: [Int] = []
        for p in xs.indices {
            var flag = on[p] ? onCurve : 0
            if overlap && p == 0 { flag |= overlapSimple }
            let dx = xs[p] - lastX
            let dy = ys[p] - lastY
            if dx == 0 {
                flag |= xSame
            } else if dx > -256 && dx < 256 {
                flag |= xShort | (dx > 0 ? xSame : 0)
                xBytes.u8(abs(dx))
            } else {
                xBytes.s16(dx)
            }
            if dy == 0 {
                flag |= ySame
            } else if dy > -256 && dy < 256 {
                flag |= yShort | (dy > 0 ? ySame : 0)
                yBytes.u8(abs(dy))
            } else {
                yBytes.s16(dy)
            }
            if flag == lastFlag && repeats != 255 {
                flagBytes[flagBytes.count - 1] |= repeatFlag
                repeats += 1
            } else {
                if repeats != 0 { flagBytes.append(repeats) }
                flagBytes.append(flag)
                repeats = 0
            }
            lastX = xs[p]
            lastY = ys[p]
            lastFlag = flag
        }
        if repeats != 0 { flagBytes.append(repeats) }
        flagBytes.forEach(g.u8)
        g.bytes(xBytes.out)
        g.bytes(yBytes.out)
    }

    // MARK: hmtx

    private static func rebuiltHmtx(_ data: [UInt8], xMins: [Int], metrics: Int) throws -> [UInt8]? {
        let r = Cursor(data)
        let flags = try r.u8()
        if flags & 0xFC != 0 { return nil }
        let glyphs = xMins.count
        if metrics < 1 || metrics > glyphs { return nil }
        var advances: [Int] = []
        for _ in 0..<metrics { advances.append(try r.u16()) }
        var lsbs: [Int] = []
        for i in 0..<glyphs {
            if i < metrics && flags & 1 == 0 {
                lsbs.append(try r.s16())
            } else if i >= metrics && flags & 2 == 0 {
                lsbs.append(try r.s16())
            } else {
                lsbs.append(xMins[i])
            }
        }
        // The proportional bearings come before the monospaced ones.
        let out = ByteWriter()
        for i in 0..<glyphs {
            if i < metrics { out.u16(advances[i]) }
            out.s16(lsbs[i])
        }
        return out.out
    }

    // MARK: writing the font

    /// Tables from elsewhere — CoreText's, for a WOFF2 the decoder cannot
    /// read (CustomFonts.woff2Font) — written by the same rule (written).
    static func font(flavor: Int, tables: [(tag: Int, data: [UInt8])], limit: Int) -> [UInt8]? {
        let made = tables.map { entry -> Table in
            let table = Table(tag: entry.tag, transformed: false, length: entry.data.count)
            table.data = entry.data
            return table
        }
        return written(flavor: flavor, made.sorted { $0.tag < $1.tag }, limit: limit)
    }

    private static func written(flavor: Int, _ tables: [Table], limit: Int) -> [UInt8]? {
        let head = tables.first { $0.tag == headTag }
        if let head, head.data.count >= 12 {
            for k in 8..<12 { head.data[k] = 0 }
        }
        let count = tables.count
        var searchRange = 1
        var entrySelector = 0
        while searchRange * 2 <= count {
            searchRange *= 2
            entrySelector += 1
        }
        searchRange *= 16
        let out = ByteWriter()
        out.u32(flavor)
        out.u16(count)
        out.u16(searchRange)
        out.u16(entrySelector)
        out.u16(count * 16 - searchRange)
        var offset = 12 + 16 * count
        var headAt = -1
        for t in tables {
            out.u32(t.tag)
            out.u32(Int(checksum(t.data)))
            out.u32(offset)
            out.u32(t.data.count)
            if let head, t === head { headAt = offset }
            offset += (t.data.count + 3) & ~3
        }
        if offset > limit { return nil }
        for t in tables {
            out.bytes(t.data)
            let padded = (t.data.count + 3) & ~3
            for _ in t.data.count..<padded { out.u8(0) }
        }
        var font = out.out
        if headAt >= 0 {
            let adjustment = UInt32(0xB1B0_AFBA) &- checksum(font)
            for k in 0..<4 { font[headAt + 8 + k] = UInt8(truncatingIfNeeded: adjustment >> (24 - 8 * UInt32(k))) }
        }
        return font
    }

    /// The sum of `data`'s big-endian 32-bit words, the last padded with
    /// zeros.
    private static func checksum(_ data: [UInt8]) -> UInt32 {
        var sum: UInt32 = 0
        var i = 0
        while i < data.count {
            var word: UInt32 = 0
            for k in 0..<4 { word = word << 8 | UInt32(i + k < data.count ? data[i + k] : 0) }
            sum = sum &+ word
            i += 4
        }
        return sum
    }

    // MARK: bytes

    private final class Cursor {
        let data: [UInt8]
        var at: Int
        let end: Int

        init(_ data: [UInt8], at: Int = 0, end: Int? = nil) {
            self.data = data
            self.at = at
            self.end = min(end ?? data.count, data.count)
        }

        func u8() throws -> Int {
            if at < 0 || at >= end { throw Unreadable() }
            defer { at += 1 }
            return Int(data[at])
        }

        func u16() throws -> Int { try u8() << 8 | u8() }

        func s16() throws -> Int { Int(Int16(truncatingIfNeeded: try u16())) }

        func u32() throws -> Int { try u16() << 16 | u16() }

        func bytes(_ n: Int) throws -> [UInt8] {
            if n < 0 || at < 0 || at + n > end { throw Unreadable() }
            defer { at += n }
            return Array(data[at..<(at + n)])
        }

        /// UIntBase128: up to five bytes, seven bits each, high first.
        func base128() throws -> Int {
            var value = 0
            for i in 0..<5 {
                let b = try u8()
                if i == 0 && b == 0x80 { throw Unreadable() }
                value = (value << 7) | (b & 0x7F)
                if value > 0x7FFF_FFFF { throw Unreadable() }
                if b & 0x80 == 0 { return value }
            }
            throw Unreadable()
        }

        /// 255UInt16.
        func u255() throws -> Int {
            let code = try u8()
            switch code {
            case 253: return try u16()
            case 255: return try u8() + 253
            case 254: return try u8() + 506
            default: return code
            }
        }
    }

    private final class ByteWriter {
        private(set) var out: [UInt8] = []

        func u8(_ v: Int) { out.append(UInt8(truncatingIfNeeded: v)) }

        func u16(_ v: Int) {
            out.append(UInt8(truncatingIfNeeded: v >> 8))
            out.append(UInt8(truncatingIfNeeded: v))
        }

        func s16(_ v: Int) { u16(v & 0xFFFF) }

        func u32(_ v: Int) {
            u16(v >> 16)
            u16(v & 0xFFFF)
        }

        func bytes(_ b: [UInt8]) { out.append(contentsOf: b) }
    }
}

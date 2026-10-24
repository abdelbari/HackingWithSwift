// Compress file for PNG: the picture cut to at most 256 colours and written
// as an indexed PNG — colour type 3, its palette, a tRNS of the palette's
// alphas when any is not opaque — which is much smaller for flat graphics.
// The colours are chosen as the Android twin's GifWriter chooses a frame's,
// step for step, with alpha beside red, green and blue:
//
//   • every pixel goes in a bucket by the top five bits of red, green and
//     blue and the top three of alpha; a pixel with no alpha at all is put
//     in the black one, its colour unseen
//   • 256 buckets or fewer used: each is a colour, its pixels' mean (whole
//     numbers, rounded down), in bucket order
//   • more: median cut — the box of buckets whose channel spread is widest
//     (red, green, blue, then alpha, its three bits counted four apart, the
//     first on a tie) is cut at its pixels' median along that channel,
//     until there are 256 boxes or none can be cut; each box is its pixels'
//     mean, and each bucket takes the nearest of them (3·dr² + 4·dg² +
//     2·db² + 3·da²), the first on a tie
//   • no dithering: a design is flat colour and type, which a dither
//     speckles
//
// Rows are written with filter 0 under a zlib stream (the system's
// Compression deflate, in zlib's header and Adler-32), and pHYs carries the
// dpi as the normal PNG does. ExportPlan.keepsCompressed says whether it is
// worth keeping.

import Compression
import CoreGraphics
import Foundation

enum PngWriter {

    /// A picture's colours and each pixel's place among them.
    struct Indexed: Equatable {
        /// RGBA, 0…255 each.
        var palette: [[UInt8]]
        var indices: [UInt8]
    }

    private static let buckets = 8 * 32 * 32 * 32

    private static func bucket(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Int {
        guard a > 0 else { return 0 }
        return (a >> 5) << 15 | (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
    }

    /// One channel of bucket `k` on a 0…31 scale: red, green, blue, alpha.
    private static func channel(_ k: Int, _ c: Int) -> Int {
        switch c {
        case 0: return (k >> 10) & 31
        case 1: return (k >> 5) & 31
        case 2: return k & 31
        default: return (k >> 15) * 4
        }
    }

    /// `rgba` — straight, not premultiplied, four bytes a pixel — cut to at
    /// most 256 colours.
    static func quantize(_ rgba: [UInt8]) -> Indexed {
        let n = rgba.count / 4
        var count = [Int](repeating: 0, count: buckets)
        var sumR = [Int](repeating: 0, count: buckets), sumG = [Int](repeating: 0, count: buckets)
        var sumB = [Int](repeating: 0, count: buckets), sumA = [Int](repeating: 0, count: buckets)
        var keys = [Int](repeating: 0, count: n)
        for i in 0..<n {
            let a = Int(rgba[i * 4 + 3])
            let r = a > 0 ? Int(rgba[i * 4]) : 0
            let g = a > 0 ? Int(rgba[i * 4 + 1]) : 0
            let b = a > 0 ? Int(rgba[i * 4 + 2]) : 0
            let k = bucket(r, g, b, a)
            keys[i] = k
            count[k] += 1
            sumR[k] += r
            sumG[k] += g
            sumB[k] += b
            sumA[k] += a
        }
        var used = (0..<buckets).filter { count[$0] > 0 }
        func mean(_ k: Int) -> [Int] {
            [sumR[k] / count[k], sumG[k] / count[k], sumB[k] / count[k], sumA[k] / count[k]]
        }
        var palette: [[Int]]
        var lut = [Int](repeating: 0, count: buckets)
        if used.count <= 256 {
            palette = used.map(mean)
            for (i, k) in used.enumerated() { lut[k] = i }
        } else {
            let boxes = medianCut(&used, count: count)
            palette = boxes.map { box -> [Int] in
                var total = 0, r = 0, g = 0, b = 0, a = 0
                for j in box.lowerBound..<box.upperBound {
                    let k = used[j]
                    total += count[k]; r += sumR[k]; g += sumG[k]; b += sumB[k]; a += sumA[k]
                }
                return [r / total, g / total, b / total, a / total]
            }
            for k in used { lut[k] = nearest(palette, mean(k)) }
        }
        let indices = keys.map { UInt8(lut[$0]) }
        return Indexed(palette: palette.map { $0.map { UInt8($0) } }, indices: indices)
    }

    /// The used buckets (reordered in place) split into at most 256 boxes,
    /// each a range of `used`.
    private static func medianCut(_ used: inout [Int], count: [Int]) -> [Range<Int>] {
        var boxes: [Range<Int>] = [0..<used.count]
        func spread(_ box: Range<Int>) -> (channel: Int, width: Int) {
            var best = 0, widest = -1
            for c in 0..<4 {
                var lo = Int.max, hi = Int.min
                for j in box {
                    let v = channel(used[j], c)
                    lo = min(lo, v)
                    hi = max(hi, v)
                }
                if hi - lo > widest {
                    widest = hi - lo
                    best = c
                }
            }
            return (best, widest)
        }
        while boxes.count < 256 {
            var pick = -1, pickChannel = 0, pickSpread = 0
            for (i, box) in boxes.enumerated() where box.count >= 2 {
                let s = spread(box)
                if s.width > pickSpread {
                    pick = i
                    pickChannel = s.channel
                    pickSpread = s.width
                }
            }
            guard pick >= 0 else { break }
            let box = boxes[pick]
            // A stable sort: buckets level on the channel keep their order.
            let sorted = used[box].enumerated()
                .sorted { a, b in
                    let va = channel(a.element, pickChannel), vb = channel(b.element, pickChannel)
                    return va != vb ? va < vb : a.offset < b.offset
                }
                .map(\.element)
            for (j, k) in sorted.enumerated() { used[box.lowerBound + j] = k }
            let total = box.reduce(0) { $0 + count[used[$1]] }
            var running = 0
            var cut = box.lowerBound + 1
            for j in box.lowerBound..<(box.upperBound - 1) {
                running += count[used[j]]
                cut = j + 1
                if running * 2 >= total { break }
            }
            boxes[pick] = box.lowerBound..<cut
            boxes.append(cut..<box.upperBound)
        }
        return boxes
    }

    private static func nearest(_ palette: [[Int]], _ c: [Int]) -> Int {
        var best = 0, bestD = Int.max
        for (i, p) in palette.enumerated() {
            let dr = p[0] - c[0], dg = p[1] - c[1], db = p[2] - c[2], da = p[3] - c[3]
            let d = 3 * dr * dr + 4 * dg * dg + 2 * db * db + 3 * da * da
            if d < bestD {
                bestD = d
                best = i
            }
        }
        return best
    }

    // MARK: the file

    /// `rgba`, `width` × `height`, as an indexed PNG; with `dpi`, its pHYs.
    /// Nil when it will not compress.
    static func png(rgba: [UInt8], width: Int, height: Int, dpi: Double? = nil) -> Data? {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }
        let indexed = quantize(rgba)
        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.appendBig(UInt32(width))
        header.appendBig(UInt32(height))
        header.append(contentsOf: [8, 3, 0, 0, 0])
        chunk("IHDR", header, into: &out)
        if let dpi, dpi > 0 {
            var phys = Data()
            let perMetre = UInt32((dpi / 0.0254).rounded())
            phys.appendBig(perMetre)
            phys.appendBig(perMetre)
            phys.append(1)
            chunk("pHYs", phys, into: &out)
        }
        chunk("PLTE", Data(indexed.palette.flatMap { $0.prefix(3) }), into: &out)
        var alphas = indexed.palette.map { $0[3] }
        while alphas.last == 255 { alphas.removeLast() }
        if !alphas.isEmpty { chunk("tRNS", Data(alphas), into: &out) }
        var rows = Data(capacity: (width + 1) * height)
        for y in 0..<height {
            rows.append(0)
            rows.append(contentsOf: indexed.indices[(y * width)..<((y + 1) * width)])
        }
        guard let compressed = zlib(rows) else { return nil }
        chunk("IDAT", compressed, into: &out)
        chunk("IEND", Data(), into: &out)
        return out
    }

    private static func chunk(_ type: String, _ body: Data, into out: inout Data) {
        let typed = Data(type.utf8) + body
        out.appendBig(UInt32(body.count))
        out.append(typed)
        out.appendBig(ZipWriter.crc32(typed))
    }

    /// `data` as a zlib stream: its header, the system's deflate, and its
    /// Adler-32.
    static func zlib(_ data: Data) -> Data? {
        var out = Data([0x78, 0xDA])
        guard !data.isEmpty else { return nil }
        let capacity = data.count + data.count / 10 + 1024
        var deflated = Data(count: capacity)
        let written = deflated.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let to = dst.bindMemory(to: UInt8.self).baseAddress,
                      let from = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(to, capacity, from, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        out.append(deflated.prefix(written))
        out.appendBig(adler32(data))
        return out
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    // MARK: from a picture

    /// `image`'s pixels as straight RGBA, four bytes a pixel, row by row.
    static func rgba(of image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Back from premultiplied, to the nearest.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Int(pixels[i + 3])
            guard a > 0, a < 255 else { continue }
            for c in 0..<3 { pixels[i + c] = UInt8(min(255, (Int(pixels[i + c]) * 255 + a / 2) / a)) }
        }
        return pixels
    }
}

private extension Data {
    mutating func appendBig(_ value: UInt32) {
        append(UInt8(value >> 24))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }
}

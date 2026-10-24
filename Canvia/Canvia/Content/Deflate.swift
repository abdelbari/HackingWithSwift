// A zlib stream written the same, byte for byte, on both phones — the
// compressed PNG's IDAT (PngWriter) — where each system's own deflate may
// choose other matches. The Android twin's Deflate, line for line:
//
//   • the header 78 DA; one final block of the fixed Huffman codes (RFC
//     1951, 3.2.6)
//   • the bytes matched greedily from the first, each against the last
//     32 KB: three bytes hashed ((b0 << 10) ^ (b1 << 5) ^ b2, 15 bits) to
//     the newest place they were seen, and from there back through each
//     earlier place with the same hash, `chain` of them at most, the
//     longest match of at least `minMatch` and at most `maxMatch` bytes
//     taken — the nearest on a tie, and at once when one is as long as it
//     can be — else the byte itself; every place passed over, matched or
//     not, hashed for the matches after it
//   • then the end of the block, and the Adler-32 of the bytes, high byte
//     first
//
// Flat colour — a design's — is long runs, which this packs about as small
// as zlib's own.

import Foundation

enum Deflate {

    static let window = 32768
    static let minMatch = 3
    static let maxMatch = 258

    /// How many earlier places with the same hash are tried, at most.
    static let chain = 64

    private static let hashBits = 15
    private static let hashMask = (1 << 15) - 1

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
                                     131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
                                       1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
                                        12, 12, 13, 13]

    /// `bytes` as a zlib stream.
    static func zlib(_ bytes: [UInt8]) -> Data {
        var out = BitWriter()
        out.byte(0x78)
        out.byte(0xDA)
        out.bits(1, 1) // the last block
        out.bits(1, 2) // of the fixed codes
        let n = bytes.count
        var head = [Int](repeating: -1, count: 1 << hashBits)
        var prev = [Int](repeating: 0, count: window)
        func hash(_ at: Int) -> Int {
            ((Int(bytes[at]) << 10) ^ (Int(bytes[at + 1]) << 5) ^ Int(bytes[at + 2])) & hashMask
        }
        func insert(_ at: Int) {
            guard at + minMatch <= n else { return }
            let h = hash(at)
            prev[at & (window - 1)] = head[h]
            head[h] = at
        }
        var i = 0
        while i < n {
            var bestLength = 0
            var bestDistance = 0
            if i + minMatch <= n {
                let most = min(maxMatch, n - i)
                var candidate = head[hash(i)]
                var tries = chain
                while candidate >= 0 && i - candidate <= window && tries > 0 {
                    var length = 0
                    while length < most && bytes[candidate + length] == bytes[i + length] { length += 1 }
                    if length > bestLength {
                        bestLength = length
                        bestDistance = i - candidate
                        if length == most { break }
                    }
                    candidate = prev[candidate & (window - 1)]
                    tries -= 1
                }
            }
            if bestLength >= minMatch {
                out.length(bestLength)
                out.distance(bestDistance)
                for k in i..<(i + bestLength) { insert(k) }
                i += bestLength
            } else {
                out.symbol(Int(bytes[i]))
                insert(i)
                i += 1
            }
        }
        out.symbol(256)
        out.flush()
        let sum = adler32(bytes)
        out.byte(Int((sum >> 24) & 0xFF))
        out.byte(Int((sum >> 16) & 0xFF))
        out.byte(Int((sum >> 8) & 0xFF))
        out.byte(Int(sum & 0xFF))
        return Data(out.out)
    }

    /// The Adler-32 of `bytes`.
    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for v in bytes {
            a = (a + UInt32(v)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    /// Bits packed from the lowest of each byte up, as DEFLATE packs them.
    private struct BitWriter {
        var out: [UInt8] = []
        private var buffer: UInt64 = 0
        private var count = 0

        mutating func byte(_ v: Int) { out.append(UInt8(v & 0xFF)) }

        /// The lowest `n` bits of `value`, lowest first.
        mutating func bits(_ value: Int, _ n: Int) {
            buffer |= (UInt64(value) & ((1 << UInt64(n)) - 1)) << UInt64(count)
            count += n
            while count >= 8 {
                out.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                count -= 8
            }
        }

        /// A Huffman code of `n` bits, its highest bit first.
        private mutating func code(_ value: Int, _ n: Int) {
            var reversed = 0
            for k in 0..<n { reversed |= ((value >> k) & 1) << (n - 1 - k) }
            bits(reversed, n)
        }

        /// Literal or length symbol `s` in the fixed code.
        mutating func symbol(_ s: Int) {
            if s < 144 {
                code(0x30 + s, 8)
            } else if s < 256 {
                code(0x190 + s - 144, 9)
            } else if s < 280 {
                code(s - 256, 7)
            } else {
                code(0xC0 + s - 280, 8)
            }
        }

        mutating func length(_ length: Int) {
            var k = Deflate.lengthBase.count - 1
            while Deflate.lengthBase[k] > length { k -= 1 }
            symbol(257 + k)
            bits(length - Deflate.lengthBase[k], Deflate.lengthExtra[k])
        }

        mutating func distance(_ distance: Int) {
            var k = Deflate.distanceBase.count - 1
            while Deflate.distanceBase[k] > distance { k -= 1 }
            code(k, 5)
            bits(distance - Deflate.distanceBase[k], Deflate.distanceExtra[k])
        }

        mutating func flush() {
            if count > 0 { out.append(UInt8(buffer & 0xFF)) }
            buffer = 0
            count = 0
        }
    }
}

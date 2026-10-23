// Brotli decompression (RFC 7932), in pure code, for the WOFF2 fonts a
// person adds (Woff2, CustomFonts.sfnt) — the Android twin's Brotli, rule
// for rule, so a WOFF2 unpacks to the same bytes, and the same hash, on
// either phone. It reads a whole stream at once into memory, as a font is:
// the window is the output itself, so a distance reaches as far back as
// the stream allows. The dictionary and transforms of the RFC's appendices
// are brotli-dictionary.bin and brotli-transforms.bin, which the Android
// twin's tools/generate_brotli_data.py writes and copies here.

import Foundation

enum Brotli {

    struct Malformed: Error {
        var reason: String
        init(_ reason: String) { self.reason = reason }
    }

    /// `input` decompressed; at most `limit` bytes, past which it is
    /// refused. Throws Malformed for a stream that does not read.
    static func decompress(_ input: [UInt8], limit: Int) throws -> [UInt8] {
        try Decoder(input, limit: limit).run()
    }

    // MARK: the RFC's tables

    private static let dictionaryBytes: [UInt8] = resource("brotli-dictionary")

    /// The 121 transforms: prefix, type, suffix.
    private static let transforms: [(prefix: [UInt8], kind: Int, suffix: [UInt8])] = {
        let raw = resource("brotli-transforms")
        var out: [(prefix: [UInt8], kind: Int, suffix: [UInt8])] = []
        var at = 0
        while at < raw.count {
            let prefixLength = Int(raw[at])
            guard at + 1 + prefixLength + 2 <= raw.count else { break }
            let prefix = Array(raw[(at + 1)..<(at + 1 + prefixLength)])
            at += 1 + prefixLength
            let kind = Int(raw[at])
            let suffixLength = Int(raw[at + 1])
            guard at + 2 + suffixLength <= raw.count else { break }
            let suffix = Array(raw[(at + 2)..<(at + 2 + suffixLength)])
            at += 2 + suffixLength
            out.append((prefix, kind, suffix))
        }
        return out
    }()

    private static func resource(_ name: String) -> [UInt8] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin"),
              let data = try? Data(contentsOf: url) else { return [] }
        return [UInt8](data)
    }

    /// How many bits a dictionary word of each length is indexed by.
    private static let ndbits = [0, 0, 0, 0, 10, 10, 11, 11, 10, 10, 10, 10, 10, 9, 9, 8, 7, 7, 8, 7, 7, 6, 6, 5, 5]

    /// Where the words of each length start in the dictionary.
    private static let dictionaryOffsets: [Int] = {
        var offsets = [Int](repeating: 0, count: 25)
        for length in 5...24 { offsets[length] = offsets[length - 1] + (length - 1) * (1 << ndbits[length - 1]) }
        return offsets
    }()

    private static let blockLengthBase = [
        1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, 305, 369, 497, 753, 1265, 2289, 4337, 8433, 16625,
    ]
    private static let blockLengthExtra = [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13, 24]

    private static let insertBase = [0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98, 130, 194, 322, 578, 1090, 2114, 6210, 22594]
    private static let insertExtra = [0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24]
    private static let copyBase = [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54, 70, 102, 134, 198, 326, 582, 1094, 2118]
    private static let copyExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24]

    /// Each cell of 64 insert-and-copy codes: its insert and copy codes'
    /// first, the first two cells using the last distance.
    private static let cellInsert = [0, 0, 0, 0, 8, 8, 0, 16, 8, 16, 16]
    private static let cellCopy = [0, 8, 0, 8, 0, 8, 16, 0, 16, 8, 16]

    /// The order code length code lengths are given in.
    private static let codeLengthOrder = [1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15]

    /// The fixed code a code length code length is read with: by the next
    /// four bits, how many it takes and what it is.
    private static let clLength = [2, 2, 2, 3, 2, 2, 2, 4, 2, 2, 2, 3, 2, 2, 2, 4]
    private static let clValue = [0, 4, 3, 2, 0, 4, 3, 1, 0, 4, 3, 2, 0, 4, 3, 5]

    /// The context lookup tables (RFC 7932 section 7.1).
    private static let lut0: [Int] = {
        let head = [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 0, 0, 4, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            8, 12, 16, 12, 12, 20, 12, 16, 24, 28, 12, 12, 32, 12, 36, 12,
            44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 32, 32, 24, 40, 28, 12,
            12, 48, 52, 52, 52, 48, 52, 52, 52, 48, 52, 52, 52, 52, 52, 48,
            52, 52, 52, 52, 52, 48, 52, 52, 52, 52, 52, 24, 12, 28, 12, 12,
            12, 56, 60, 60, 60, 56, 60, 60, 60, 56, 60, 60, 60, 60, 60, 56,
            60, 60, 60, 60, 60, 56, 60, 60, 60, 60, 60, 24, 12, 28, 12, 0,
        ]
        return head + (0..<64).map { $0 & 1 } + (0..<64).map { 2 + ($0 & 1) }
    }()

    private static let lut1: [Int] = {
        let head = [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1,
            1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
            2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1,
            1, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
            3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 1, 1, 0,
        ]
        return head + [Int](repeating: 0, count: 96) + [Int](repeating: 2, count: 32)
    }()

    private static let lut2: [Int] = (0..<256).map { b in
        if b == 0 { return 0 }
        if b < 16 { return 1 }
        if b < 64 { return 2 }
        if b < 128 { return 3 }
        if b < 192 { return 4 }
        if b < 240 { return 5 }
        if b < 255 { return 6 }
        return 7
    }

    // MARK: reading bits

    /// The stream's bits, least significant first.
    private final class Bits {
        private let data: [UInt8]
        private var next = 0
        private var buffer: UInt64 = 0
        private var count = 0

        init(_ data: [UInt8]) { self.data = data }

        private func fill() {
            while count <= 56 && next < data.count {
                buffer |= UInt64(data[next]) << UInt64(count)
                next += 1
                count += 8
            }
        }

        func read(_ n: Int) throws -> Int {
            if n == 0 { return 0 }
            if count < n { fill() }
            if count < n { throw Malformed("the stream ends early") }
            let v = Int(buffer & ((UInt64(1) << UInt64(n)) - 1))
            buffer >>= UInt64(n)
            count -= n
            return v
        }

        /// The next `n` bits without taking them, zeros past the end.
        func peek(_ n: Int) -> Int {
            if count < n { fill() }
            return Int(buffer & ((UInt64(1) << UInt64(n)) - 1))
        }

        func skip(_ n: Int) throws {
            if count < n { fill() }
            if count < n { throw Malformed("the stream ends early") }
            buffer >>= UInt64(n)
            count -= n
        }

        /// To the next byte's start; the bits passed must be zeros.
        func align() throws {
            if try read(count % 8) != 0 { throw Malformed("padding is not zero") }
        }

        /// `n` whole bytes, aligned, into `into` from `at`.
        func bytes(_ n: Int, into: inout [UInt8], at: Int) throws {
            var i = 0
            while i < n && count >= 8 {
                into[at + i] = UInt8(truncatingIfNeeded: buffer)
                i += 1
                buffer >>= 8
                count -= 8
            }
            let rest = n - i
            if rest > data.count - next || at + n > into.count { throw Malformed("the stream ends early") }
            if rest > 0 {
                into.replaceSubrange((at + i)..<(at + n), with: data[next..<(next + rest)])
                next += rest
            }
        }
    }

    // MARK: prefix codes

    /// A canonical prefix code: symbols by code length, read a bit at a
    /// time, most significant first. One symbol alone takes no bits.
    private final class Code {
        private var counts = [Int](repeating: 0, count: 16)
        private let symbols: [Int]
        private let single: Int

        init(_ lengths: [Int]) throws {
            for l in lengths where l > 0 { counts[l] += 1 }
            var offsets = [Int](repeating: 0, count: 16)
            for l in 1..<15 { offsets[l + 1] = offsets[l] + counts[l] }
            let used = lengths.filter { $0 > 0 }.count
            if used == 0 { throw Malformed("a prefix code with no symbols") }
            var symbols = [Int](repeating: 0, count: used)
            for (s, l) in lengths.enumerated() where l > 0 {
                symbols[offsets[l]] = s
                offsets[l] += 1
            }
            self.symbols = symbols
            single = used == 1 ? symbols[0] : -1
        }

        func read(_ bits: Bits) throws -> Int {
            if single >= 0 { return single }
            var code = 0
            var first = 0
            var index = 0
            for l in 1...15 {
                code |= try bits.read(1)
                let n = counts[l]
                if code - first < n { return symbols[index + code - first] }
                index += n
                first = (first + n) << 1
                code <<= 1
            }
            throw Malformed("not a prefix code")
        }
    }

    /// A prefix code over `alphabet` symbols, as the stream gives it:
    /// simple (up to four symbols listed) or complex (code lengths).
    private static func readCode(_ bits: Bits, _ alphabet: Int) throws -> Code {
        var lengths = [Int](repeating: 0, count: alphabet)
        let hskip = try bits.read(2)
        if hskip == 1 {
            var width = 0
            var v = alphabet - 1
            while v > 0 {
                width += 1
                v >>= 1
            }
            let n = try bits.read(2) + 1
            var symbols: [Int] = []
            for _ in 0..<n {
                let s = try bits.read(width)
                if s >= alphabet { throw Malformed("symbol past the alphabet") }
                symbols.append(s)
            }
            if Set(symbols).count != n { throw Malformed("a symbol listed twice") }
            switch n {
            case 1:
                lengths[symbols[0]] = 1
            case 2:
                for s in symbols { lengths[s] = 1 }
            case 3:
                lengths[symbols[0]] = 1
                lengths[symbols[1]] = 2
                lengths[symbols[2]] = 2
            default:
                if try bits.read(1) == 0 {
                    for s in symbols { lengths[s] = 2 }
                } else {
                    lengths[symbols[0]] = 1
                    lengths[symbols[1]] = 2
                    lengths[symbols[2]] = 3
                    lengths[symbols[3]] = 3
                }
            }
            return try Code(lengths)
        }
        // Complex: the code length code's lengths first.
        var clLengths = [Int](repeating: 0, count: 18)
        var space = 32
        var nonZero = 0
        for i in hskip..<18 {
            let peeked = bits.peek(4)
            try bits.skip(clLength[peeked])
            let v = clValue[peeked]
            clLengths[codeLengthOrder[i]] = v
            if v != 0 {
                space -= 32 >> v
                nonZero += 1
                if space <= 0 { break }
            }
        }
        if nonZero != 1 && space != 0 { throw Malformed("a code length code that does not add up") }
        let clCode = try Code(clLengths)
        var symbol = 0
        var previous = 8
        var repeatCount = 0
        var repeatLength = 0
        var left = 32768
        while symbol < alphabet && left > 0 {
            let cl = try clCode.read(bits)
            if cl < 16 {
                repeatCount = 0
                lengths[symbol] = cl
                symbol += 1
                if cl != 0 {
                    previous = cl
                    left -= 32768 >> cl
                }
            } else {
                let extra = cl == 16 ? 2 : 3
                let length = cl == 16 ? previous : 0
                if repeatLength != length {
                    repeatCount = 0
                    repeatLength = length
                }
                let old = repeatCount
                if repeatCount > 0 { repeatCount = (repeatCount - 2) << extra }
                repeatCount += try bits.read(extra) + 3
                let delta = repeatCount - old
                if symbol + delta > alphabet { throw Malformed("code lengths past the alphabet") }
                for _ in 0..<delta {
                    lengths[symbol] = repeatLength
                    symbol += 1
                }
                if repeatLength != 0 { left -= delta << (15 - repeatLength) }
            }
        }
        if left != 0 { throw Malformed("code lengths that do not add up") }
        return try Code(lengths)
    }

    private static func varLen(_ bits: Bits) throws -> Int {
        if try bits.read(1) == 0 { return 1 }
        let n = try bits.read(3)
        return try n == 0 ? 2 : (1 << n) + bits.read(n) + 1
    }

    /// One category's block types and the codes switching between them.
    private final class Blocks {
        let bits: Bits
        let types: Int
        let typeCode: Code?
        let countCode: Code?
        var count: Int
        var type = 0
        private var previous = 1

        init(_ bits: Bits) throws {
            self.bits = bits
            types = try Brotli.varLen(bits)
            typeCode = try types >= 2 ? Brotli.readCode(bits, types + 2) : nil
            let countCode = try types >= 2 ? Brotli.readCode(bits, 26) : nil
            self.countCode = countCode
            if let countCode {
                let s = try countCode.read(bits)
                count = try Brotli.blockLengthBase[s] + bits.read(Brotli.blockLengthExtra[s])
            } else {
                count = 1 << 28
            }
        }

        private func blockLength(_ code: Code) throws -> Int {
            let s = try code.read(bits)
            return try Brotli.blockLengthBase[s] + bits.read(Brotli.blockLengthExtra[s])
        }

        /// Counts one down, switching type when the block ends.
        func step() throws {
            if count == 0, let typeCode, let countCode {
                let code = try typeCode.read(bits)
                var next: Int
                switch code {
                case 0: next = previous
                case 1: next = type + 1
                default: next = code - 2
                }
                if next >= types { next -= types }
                previous = type
                type = next
                count = try blockLength(countCode)
            }
            count -= 1
        }
    }

    // MARK: decoding

    private final class Decoder {
        private let bits: Bits
        private let limit: Int
        private var out: [UInt8]
        private var size = 0
        private var distances = [16, 15, 11, 4] // fourth … last
        private var maxBackward = 0

        init(_ input: [UInt8], limit: Int) {
            bits = Bits(input)
            self.limit = limit
            out = [UInt8](repeating: 0, count: max(0, min(limit, max(1024, input.count * 4))))
        }

        private func put(_ b: UInt8) throws {
            if size == out.count { try grow(size + 1) }
            out[size] = b
            size += 1
        }

        private func grow(_ need: Int) throws {
            if need > limit { throw Malformed("past the size it may be") }
            let next = min(limit, max(need, out.count * 2))
            out.append(contentsOf: [UInt8](repeating: 0, count: next - out.count))
        }

        func run() throws -> [UInt8] {
            let wbits = try windowBits()
            maxBackward = (1 << wbits) - 16
            while true {
                let last = try bits.read(1) == 1
                if last, try bits.read(1) == 1 { break }
                let n = try bits.read(2)
                let nibbles = n == 3 ? 0 : n + 4
                if nibbles == 0 {
                    if try bits.read(1) != 0 { throw Malformed("reserved bit set") }
                    let skipBytes = try bits.read(2)
                    var skip = 0
                    for i in 0..<skipBytes { skip |= try bits.read(8) << (8 * i) }
                    if skipBytes > 0 { skip += 1 }
                    try bits.align()
                    if skip > 0 {
                        var scratch = [UInt8](repeating: 0, count: skip)
                        try bits.bytes(skip, into: &scratch, at: 0)
                    }
                    if last { break }
                    continue
                }
                var length = 0
                for i in 0..<nibbles {
                    let nibble = try bits.read(4)
                    if i == nibbles - 1 && nibbles > 4 && nibble == 0 { throw Malformed("a length with a zero nibble on top") }
                    length |= nibble << (4 * i)
                }
                length += 1
                if !last, try bits.read(1) == 1 {
                    try bits.align()
                    if size + length > out.count { try grow(size + length) }
                    try bits.bytes(length, into: &out, at: size)
                    size += length
                    continue
                }
                try compressed(length)
                if last { break }
            }
            return Array(out[0..<size])
        }

        private func windowBits() throws -> Int {
            if try bits.read(1) == 0 { return 16 }
            let n = try bits.read(3)
            if n != 0 { return 17 + n }
            let m = try bits.read(3)
            if m == 1 { throw Malformed("a large window") }
            return m != 0 ? 8 + m : 17
        }

        private func contextMap(_ trees: Int, _ size: Int) throws -> [Int] {
            var map = [Int](repeating: 0, count: size)
            if trees < 2 { return map }
            let rleMax = try bits.read(1) == 1 ? bits.read(4) + 1 : 0
            let code = try Brotli.readCode(bits, trees + rleMax)
            var i = 0
            while i < size {
                let s = try code.read(bits)
                if s == 0 {
                    map[i] = 0
                    i += 1
                } else if s <= rleMax {
                    let run = try (1 << s) + bits.read(s)
                    if i + run > size { throw Malformed("a context map run past its end") }
                    i += run
                } else {
                    map[i] = s - rleMax
                    i += 1
                }
            }
            if try bits.read(1) == 1 {
                // Inverse move to front.
                var mtf = Array(0..<256)
                for k in map.indices {
                    let index = map[k]
                    let value = mtf[index]
                    map[k] = value
                    mtf.remove(at: index)
                    mtf.insert(value, at: 0)
                }
            }
            // A tree the map names must be one there is.
            if map.contains(where: { $0 >= trees }) { throw Malformed("a context map naming no tree") }
            return map
        }

        private func compressed(_ length: Int) throws {
            let end = size + length
            let literalBlocks = try Blocks(bits)
            let commandBlocks = try Blocks(bits)
            let distanceBlocks = try Blocks(bits)
            let postfix = try bits.read(2)
            let direct = try bits.read(4) << postfix
            var modes: [Int] = []
            for _ in 0..<literalBlocks.types { modes.append(try bits.read(2)) }
            let literalTrees = try Brotli.varLen(bits)
            let literalMap = try contextMap(literalTrees, literalBlocks.types * 64)
            let distanceTrees = try Brotli.varLen(bits)
            let distanceMap = try contextMap(distanceTrees, distanceBlocks.types * 4)
            var literalCodes: [Code] = []
            for _ in 0..<literalTrees { literalCodes.append(try Brotli.readCode(bits, 256)) }
            var commandCodes: [Code] = []
            for _ in 0..<commandBlocks.types { commandCodes.append(try Brotli.readCode(bits, 704)) }
            let distanceAlphabet = 16 + direct + (48 << postfix)
            var distanceCodes: [Code] = []
            for _ in 0..<distanceTrees { distanceCodes.append(try Brotli.readCode(bits, distanceAlphabet)) }
            let postfixMask = (1 << postfix) - 1
            while size < end {
                try commandBlocks.step()
                let command = try commandCodes[commandBlocks.type].read(bits)
                let cell = command >> 6
                let insertCode = Brotli.cellInsert[cell] + ((command >> 3) & 7)
                let copyCode = Brotli.cellCopy[cell] + (command & 7)
                let insert = try Brotli.insertBase[insertCode] + bits.read(Brotli.insertExtra[insertCode])
                let copy = try Brotli.copyBase[copyCode] + bits.read(Brotli.copyExtra[copyCode])
                for _ in 0..<insert {
                    try literalBlocks.step()
                    let p1 = size > 0 ? Int(out[size - 1]) : 0
                    let p2 = size > 1 ? Int(out[size - 2]) : 0
                    let context: Int
                    switch modes[literalBlocks.type] {
                    case 0: context = p1 & 0x3F
                    case 1: context = p1 >> 2
                    case 2: context = Brotli.lut0[p1] | Brotli.lut1[p2]
                    default: context = (Brotli.lut2[p1] << 3) | Brotli.lut2[p2]
                    }
                    let literal = try literalCodes[literalMap[literalBlocks.type * 64 + context]].read(bits)
                    try put(UInt8(truncatingIfNeeded: literal))
                    if size > end { throw Malformed("past the meta-block's length") }
                }
                if size >= end { break }
                var distance: Int
                var pushed = true
                if cell < 2 {
                    distance = distances[3]
                    pushed = false
                } else {
                    try distanceBlocks.step()
                    let context = copy > 4 ? 3 : copy - 2
                    let code = try distanceCodes[distanceMap[distanceBlocks.type * 4 + context]].read(bits)
                    if code < 16 {
                        if code == 0 { pushed = false }
                        distance = special(code)
                    } else if code < 16 + direct {
                        distance = code - 15
                    } else {
                        let d = code - direct - 16
                        let extraBits = 1 + (d >> (postfix + 1))
                        let high = d >> postfix
                        let low = d & postfixMask
                        let offset = ((2 + (high & 1)) << extraBits) - 4
                        distance = try ((offset + bits.read(extraBits)) << postfix) + low + direct + 1
                    }
                    if distance <= 0 { throw Malformed("a distance before the start") }
                }
                let reach = min(maxBackward, size)
                if distance > reach {
                    try word(copy, distance - reach - 1)
                } else {
                    if pushed { push(distance) }
                    if size + copy > out.count { try grow(size + copy) }
                    for _ in 0..<copy {
                        out[size] = out[size - distance]
                        size += 1
                    }
                }
                if size > end { throw Malformed("past the meta-block's length") }
            }
        }

        private func special(_ code: Int) -> Int {
            let last = distances[3]
            let second = distances[2]
            switch code {
            case 0: return last
            case 1: return second
            case 2: return distances[1]
            case 3: return distances[0]
            case 4: return last - 1
            case 5: return last + 1
            case 6: return last - 2
            case 7: return last + 2
            case 8: return last - 3
            case 9: return last + 3
            case 10: return second - 1
            case 11: return second + 1
            case 12: return second - 2
            case 13: return second + 2
            case 14: return second - 3
            default: return second + 3
            }
        }

        private func push(_ distance: Int) {
            distances[0] = distances[1]
            distances[1] = distances[2]
            distances[2] = distances[3]
            distances[3] = distance
        }

        /// A word of the dictionary, `length` long, transformed.
        private func word(_ length: Int, _ id: Int) throws {
            if length < 4 || length > 24 { throw Malformed("a dictionary word of no length it has") }
            let bitsFor = Brotli.ndbits[length]
            let index = id & ((1 << bitsFor) - 1)
            let transform = id >> bitsFor
            if transform >= Brotli.transforms.count { throw Malformed("no such transform") }
            let start = Brotli.dictionaryOffsets[length] + index * length
            let (prefix, kind, suffix) = Brotli.transforms[transform]
            var from = start
            var count = length
            if (1...9).contains(kind) {
                count -= kind
            } else if (12...20).contains(kind) {
                let skip = min(kind - 11, count)
                from += skip
                count -= skip
            }
            count = max(0, count)
            if from + count > Brotli.dictionaryBytes.count { throw Malformed("a word past the dictionary") }
            var word = Array(Brotli.dictionaryBytes[from..<(from + count)])
            if kind == 10 {
                _ = ferment(&word, 0)
            } else if kind == 11 {
                var at = 0
                while at < word.count { at += ferment(&word, at) }
            }
            for b in prefix { try put(b) }
            for b in word { try put(b) }
            for b in suffix { try put(b) }
        }

        /// The RFC's uppercasing of the letter at `at`, by its UTF-8 lead
        /// byte; how many bytes it took.
        private func ferment(_ word: inout [UInt8], _ at: Int) -> Int {
            let b = word[at]
            if b < 192 {
                if (97...122).contains(b) { word[at] = b ^ 32 }
                return 1
            }
            if b < 224 {
                if at + 1 < word.count { word[at + 1] ^= 32 }
                return 2
            }
            if at + 2 < word.count { word[at + 2] ^= 5 }
            return 3
        }
    }
}

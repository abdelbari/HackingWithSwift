// Barcodes — Code 128, EAN-13, UPC-A and Code 39 — made on the phone, as the
// Android twin makes them, number for number: encode turns a kind and its
// words into the widths of its bars and spaces, and a barcode is a photo
// element whose src is "barcode:<kind>:<payload>" (source), drawn as
// rectangles wherever it goes — the canvas, SVG, PDF and PowerPoint — as a
// QR code's vector is. It shares a QR code's colour, background and margin
// keys (CodeGenerator.Look; its margin is in modules, its bars' width), and
// `barcodeText` says whether its words are written under the bars.

import CoreGraphics
import Foundation
import UIKit

enum Barcodes {

    /// The kinds, by the key the src keeps and the name the sheet shows, in
    /// the sheet's order.
    enum Symbology: String, CaseIterable, Identifiable {
        case code128, ean13, upca, code39
        var id: String { rawValue }
        var name: String {
            switch self {
            case .code128: return "Code 128"
            case .ean13: return "EAN-13"
            case .upca: return "UPC-A"
            case .code39: return "Code 39"
            }
        }
    }

    /// What encode makes of a kind's words: its bars, or why not.
    enum Encoding: Equatable {
        /// Module widths, a bar first and then a space, a bar… — and the
        /// words written under them (an EAN-13's or a UPC-A's digits with
        /// the check digit, a Code 39's without its stars).
        case bars(widths: [Int], readable: String)
        /// The words cannot be this kind of code; the reason says why.
        case invalid(String)

        var widths: [Int]? {
            if case .bars(let widths, _) = self { return widths }
            return nil
        }

        var readable: String? {
            if case .bars(_, let readable) = self { return readable }
            return nil
        }

        var reason: String? {
            if case .invalid(let reason) = self { return reason }
            return nil
        }
    }

    static let prefix = "barcode:"

    /// The most characters a Code 128 or Code 39 holds here.
    static let maxLength = 80

    /// A barcode's src: its kind's key and its payload, percent-encoded as
    /// UTF-8, every byte but A–Z, a–z, 0–9 and - . _ ~ as %XX (upper case
    /// hex) — so a colon or a space in it is no problem.
    static func source(_ kind: Symbology, _ payload: String) -> String {
        prefix + kind.rawValue + ":" + percentEncoded(payload)
    }

    /// The kind and payload of a barcode's src; nil for anything else.
    static func parse(_ src: String?) -> (kind: Symbology, payload: String)? {
        guard let src, src.hasPrefix(prefix) else { return nil }
        let rest = src.dropFirst(prefix.count)
        guard let colon = rest.firstIndex(of: ":"), let kind = Symbology(rawValue: String(rest[..<colon])),
              let payload = percentDecoded(String(rest[rest.index(after: colon)...])) else { return nil }
        return (kind, payload)
    }

    static func isBarcode(_ src: String?) -> Bool { parse(src) != nil }

    /// Whether `el` writes its words under its bars.
    static func showsText(_ el: Element) -> Bool { el.barcodeText != false }

    /// Words for `kind` made into bars, or the reason they cannot be.
    static func encode(_ kind: Symbology, _ text: String) -> Encoding {
        switch kind {
        case .ean13: return ean13(text)
        case .upca: return upca(text)
        case .code39: return code39(text)
        case .code128: return code128(text)
        }
    }

    // MARK: EAN-13 and UPC-A

    private static let lCodes = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let gCodes = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
    private static let rCodes = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]

    /// Which of the left six digits use the G codes, by the first digit.
    private static let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    /// The check digit of `digits`, 12 of them (an EAN-13's first twelve),
    /// weighted 1, 3, 1, 3… from the left.
    static func eanCheckDigit(_ digits: [Int]) -> Int {
        let sum = digits.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 1 : 3) }
        return (10 - sum % 10) % 10
    }

    /// The digits of `text`, spaces and hyphens typed between them ignored;
    /// nil when anything else is in it.
    private static func digits(_ text: String) -> [Int]? {
        let kept = text.filter { $0 != " " && $0 != "-" }
        let out = kept.compactMap { c -> Int? in c.isASCII ? c.wholeNumberValue : nil }
        return out.count == kept.count ? out : nil
    }

    /// EAN-13: 12 digits and the check digit worked out, or 13 whose last
    /// is the check digit — any other, said ("The check digit should be 7").
    private static func ean13(_ text: String) -> Encoding {
        guard let digits = digits(text), (12...13).contains(digits.count) else {
            return .invalid(tr("EAN-13 needs 12 or 13 digits"))
        }
        let check = eanCheckDigit(Array(digits.prefix(12)))
        if digits.count == 13 && digits[12] != check {
            return .invalid(tr("The check digit should be %@", "\(check)"))
        }
        let all = Array(digits.prefix(12)) + [check]
        let pattern = Array(parity[all[0]])
        var bits = "101"
        for i in 1...6 { bits += pattern[i - 1] == "L" ? lCodes[all[i]] : gCodes[all[i]] }
        bits += "01010"
        for i in 7...12 { bits += rCodes[all[i]] }
        bits += "101"
        return .bars(widths: runs(bits), readable: all.map(String.init).joined())
    }

    /// UPC-A: 11 digits and the check digit, or 12 — an EAN-13 led by 0,
    /// with the same bars; its words are its own 12 digits.
    private static func upca(_ text: String) -> Encoding {
        guard let digits = digits(text), (11...12).contains(digits.count) else {
            return .invalid(tr("UPC-A needs 11 or 12 digits"))
        }
        let ean = ean13("0" + digits.map(String.init).joined())
        guard case .bars(let widths, let readable) = ean else { return ean }
        return .bars(widths: widths, readable: String(readable.dropFirst()))
    }

    /// Bits, "1" dark, as run lengths from the first, which is dark.
    private static func runs(_ bits: String) -> [Int] {
        var out: [Int] = []
        var last: Character?
        for c in bits {
            if c == last, let n = out.popLast() {
                out.append(n + 1)
            } else {
                out.append(1)
            }
            last = c
        }
        return out
    }

    // MARK: Code 39

    private static let code39Alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%")

    /// Each character's nine bars and spaces, 1 wide and 0 narrow.
    private static let code39Patterns = [
        "000110100", "100100001", "001100001", "101100000", "000110001", "100110000", "001110000", "000100101",
        "100100100", "001100100", "100001001", "001001001", "101001000", "000011001", "100011000", "001011000",
        "000001101", "100001100", "001001100", "000011100", "100000011", "001000011", "101000010", "000010011",
        "100010010", "001010010", "000000111", "100000110", "001000110", "000010110", "110000001", "011000001",
        "111000000", "010010001", "110010000", "011010000", "010000101", "110000100", "011000100", "010101000",
        "010100010", "010001010", "000101010",
    ]
    private static let code39Star = "010010100"

    /// A wide bar or space is this many modules, a narrow one one.
    static let code39Wide = 3

    /// Code 39: A–Z (lower case read as upper), 0–9, space and - . $ / + %,
    /// between start and stop stars, a narrow space between characters; no
    /// check character. At most maxLength characters.
    private static func code39(_ text: String) -> Encoding {
        let upper = text.uppercased(with: Locale(identifier: "en_US_POSIX"))
        if upper.isEmpty { return .invalid(tr("Type something to encode")) }
        if upper.count > maxLength { return .invalid(tr("That is too long for a barcode")) }
        let indices = upper.map { code39Alphabet.firstIndex(of: $0) }
        guard !indices.contains(where: { $0 == nil }) else {
            return .invalid(tr("Code 39 takes A–Z, 0–9, spaces and - . $ / + %"))
        }
        let patterns = [code39Star] + indices.compactMap { $0.map { code39Patterns[$0] } } + [code39Star]
        var out: [Int] = []
        for (i, pattern) in patterns.enumerated() {
            if i > 0 { out.append(1) }
            for c in pattern { out.append(c == "1" ? code39Wide : 1) }
        }
        return .bars(widths: out, readable: upper)
    }

    // MARK: Code 128

    /// Each symbol's six bars and spaces (the stop's seven), by value.
    private static let code128Patterns = [
        "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213", "221312", "231212",
        "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132", "221231", "213212", "223112", "312131",
        "311222", "321122", "321221", "312212", "322112", "322211", "212123", "212321", "232121", "111323", "131123", "131321",
        "112313", "132113", "132311", "211313", "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121",
        "313121", "211331", "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
        "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214", "112412", "122114",
        "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111", "111242", "121142", "121241", "114212",
        "124112", "124211", "411212", "421112", "421211", "212141", "214121", "412121", "111143", "111341", "131141", "114113",
        "114311", "411113", "411311", "113141", "114131", "311141", "411131", "211412", "211214", "211232", "2331112",
    ]
    private static let codeC = 99
    private static let codeB = 100
    private static let startB = 104
    private static let startC = 105
    private static let stop = 106

    /// The symbol values Code 128 writes for `text` — start, data and switch
    /// symbols and the check symbol, before the stop — choosing subset B or
    /// C by one rule both phones keep: a run of digits goes in C, two to a
    /// symbol, when it is 4 digits or more, or the whole text and 2 or more;
    /// the rest goes in B. A run of an odd length in C gives its first digit
    /// to B. It starts in the subset of what comes first, switches with
    /// Code C (99) and Code B (100), and checks with the start's value and
    /// each symbol's times its place, mod 103. Nil for a character outside
    /// printable ASCII (space to ~). The Android twin's code128Values.
    static func code128Values(_ text: String) -> [Int]? {
        let chars = Array(text.unicodeScalars)
        guard chars.allSatisfy({ (32...126).contains($0.value) }) else { return nil }
        func isDigit(_ k: Int) -> Bool { (48...57).contains(chars[k].value) }
        func piece(_ from: Int, _ to: Int) -> String {
            String(String.UnicodeScalarView(chars[from..<to]))
        }
        // Each stretch of the text, in C (true) or in B.
        var parts: [(words: String, inC: Bool)] = []
        var i = 0
        while i < chars.count {
            var j = i
            while j < chars.count && isDigit(j) { j += 1 }
            let run = j - i
            let whole = i == 0 && j == chars.count
            if run >= 4 || (whole && run >= 2) {
                if run % 2 == 1 {
                    parts.append((piece(i, i + 1), false))
                    parts.append((piece(i + 1, j), true))
                } else {
                    parts.append((piece(i, j), true))
                }
                i = j
            } else {
                // Up to the next run of digits that goes in C.
                var k = run > 0 ? j : i + 1
                while k < chars.count {
                    if isDigit(k) {
                        var m = k
                        while m < chars.count && isDigit(m) { m += 1 }
                        if m - k >= 4 { break }
                        k = m
                    } else {
                        k += 1
                    }
                }
                parts.append((piece(i, k), false))
                i = k
            }
        }
        // Neighbouring stretches in B are one.
        var merged: [(words: String, inC: Bool)] = []
        for p in parts {
            if let last = merged.last, !last.inC, !p.inC {
                merged[merged.count - 1] = (last.words + p.words, false)
            } else {
                merged.append(p)
            }
        }
        var values: [Int] = []
        var inC: Bool?
        for (words, c) in merged {
            if inC == nil {
                values.append(c ? startC : startB)
            } else if inC != c {
                values.append(c ? codeC : codeB)
            }
            inC = c
            if c {
                let digits = Array(words)
                for k in stride(from: 0, to: digits.count, by: 2) { values.append(Int(String(digits[k...k + 1])) ?? 0) }
            } else {
                values.append(contentsOf: words.unicodeScalars.map { Int($0.value) - 32 })
            }
        }
        let check = values.enumerated().reduce(0) { $0 + $1.element * max($1.offset, 1) } % 103
        return values + [check]
    }

    private static func code128(_ text: String) -> Encoding {
        if text.isEmpty { return .invalid(tr("Type something to encode")) }
        if text.count > maxLength { return .invalid(tr("That is too long for a barcode")) }
        guard let values = code128Values(text) else {
            return .invalid(tr("Code 128 takes only the letters, digits and signs on a keyboard"))
        }
        let widths = (values + [stop]).flatMap { v in code128Patterns[v].compactMap(\.wholeNumberValue) }
        return .bars(widths: widths, readable: text)
    }

    // MARK: drawn

    /// A barcode as rectangles in its element's own space (its frame's top
    /// left at 0, 0), for the canvas and every export alike, the Android
    /// twin's layout:
    /// - across, its modules and `margin` of them either side fill the
    ///   frame's width, each bar at its module's place;
    /// - its bars stand from a pad at the top to a pad at the foot — the
    ///   margin's width, but at most a tenth of the height — and, with its
    ///   words shown, the lowest fifth of the frame is theirs (`caption` in
    ///   `captionBox`, type three quarters of its height, centred);
    /// - an invalid payload has no bars, and its reason is the caption, in
    ///   type an eighth of the height (at most a twentieth of the width).
    /// `background` is the whole frame, or nil for none.
    struct Drawing: Equatable {
        var style: CodeGenerator.Look
        var background: CGRect?
        var bars: [CGRect]
        var caption: String?
        var captionBox: CGRect?
        var fontSize: Double
    }

    static func vector(_ el: Element) -> Drawing? {
        guard el.type == .image, el.w > 0, el.h > 0, let code = parse(el.src) else { return nil }
        let style = CodeGenerator.style(of: el)
        let background: CGRect? = style.background == nil ? nil : CGRect(x: 0, y: 0, width: el.w, height: el.h)
        switch encode(code.kind, code.payload) {
        case .invalid(let reason):
            let size: Double = min(el.h / 8, el.w / 20)
            return Drawing(style: style, background: background, bars: [], caption: reason,
                          captionBox: CGRect(x: 0, y: (el.h - size * 1.4) / 2, width: el.w, height: size * 1.4), fontSize: size)
        case .bars(let widths, let readable):
            let units = Double(widths.reduce(0, +) + 2 * style.margin)
            let unit: Double = el.w / units
            let textH: Double = showsText(el) ? el.h * 0.2 : 0
            let pad: Double = min(Double(style.margin) * unit, el.h * 0.1)
            let top = pad
            let bottom = max(top + 1, el.h - pad - textH)
            var bars: [CGRect] = []
            var x = Double(style.margin)
            for (i, w) in widths.enumerated() {
                if i % 2 == 0 { bars.append(CGRect(x: x * unit, y: top, width: Double(w) * unit, height: bottom - top)) }
                x += Double(w)
            }
            let caption = textH > 0 ? readable : nil
            let box = caption == nil ? nil : CGRect(x: 0, y: el.h - pad - textH, width: el.w, height: textH)
            return Drawing(style: style, background: background, bars: bars, caption: caption, captionBox: box,
                          fontSize: textH * 0.75)
        }
    }

    /// vector's caption as a text element — its words, centred, in the
    /// code's colour, its type the vector's fontSize — in `el`'s own space
    /// (its frame's top left at 0, 0), or on the page, turned with `el`,
    /// with `onPage`: what the SVG and PowerPoint write under the bars. Nil
    /// with no caption.
    static func captionElement(_ el: Element, _ vector: Drawing, onPage: Bool = false) -> Element? {
        guard let words = vector.caption, let box = vector.captionBox else { return nil }
        var t = Element.text(words, fontSize: max(1, vector.fontSize), w: box.width)
        t.id = el.id + "-caption"
        t.align = "center"
        t.color = vector.style.color
        t.fontFamily = "sans"
        t.x = box.minX
        t.y = box.minY
        t.h = box.height
        t.opacity = el.opacity
        guard onPage else { return t }
        t.x += el.x
        t.y += el.y
        guard el.rotation != 0 else { return t }
        return Geometry.rotate([t], around: el.center, by: el.rotation).first ?? t
    }

    /// What a new barcode's frame is on a page `shorter` on its shorter
    /// side: half of it wide and half that tall.
    static func newSize(_ shorter: Double) -> CGSize {
        let w = (shorter * 0.5).rounded()
        return CGSize(width: w, height: (w / 2).rounded())
    }

    /// A barcode's picture, for anything that shows a code as pixels — a
    /// thumbnail, a filtered code: its vector drawn `scale` pixels a page
    /// unit, its words in the system face.
    static func picture(of el: Element, scale: Double = 2) -> UIImage? {
        guard let v = vector(el) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: el.w, height: el.h), format: format).image { ctx in
            if let paper = v.style.background, let box = v.background {
                UIColor(hex: paper).setFill()
                ctx.fill(box)
            }
            UIColor(hex: v.style.color).setFill()
            for bar in v.bars { ctx.fill(bar) }
            guard let words = v.caption, let box = v.captionBox else { return }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(1, v.fontSize)),
                .foregroundColor: UIColor(hex: v.style.color),
                .paragraphStyle: style,
            ]
            (words as NSString).draw(in: box, withAttributes: attributes)
        }
    }

    // MARK: percent-encoding

    private static func percentEncoded(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF")
        var out = ""
        for b in Array(text.utf8) {
            let c = Character(UnicodeScalar(b))
            if b < 128 && (c.isLetter || c.isNumber || c == "-" || c == "." || c == "_" || c == "~") {
                out.append(c)
            } else {
                out.append("%")
                out.append(hex[Int(b >> 4)])
                out.append(hex[Int(b & 15)])
            }
        }
        return out
    }

    private static func percentDecoded(_ text: String) -> String? {
        var bytes: [UInt8] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "%" {
                guard let end = text.index(i, offsetBy: 3, limitedBy: text.endIndex),
                      let b = UInt8(text[text.index(after: i)..<end], radix: 16) else { return nil }
                bytes.append(b)
                i = end
            } else {
                bytes.append(contentsOf: Array(String(c).utf8))
                i = text.index(after: i)
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}

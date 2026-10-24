// Styled words pasted from another app — a web page, Mail, Notes, Pages,
// Google Docs — as a clip the typing field pastes as it pastes words copied
// here (RichClipboard.Clip): bold, italic, underline and strike as markers,
// links, colours and sizes as spans, and bulleted and numbered lines as
// lists. HTML is read by a small tolerant tag walker (fromHtml), with no web
// view; RTF is read by the system into an attributed string, whose
// attributes go through the same builder (fromAttributed), so both read
// alike. The Android twin reads the same HTML into the same JSON, row for
// row of the shared fixtures.
//
// The rules, both phones:
//  - <b>, <strong>, <h1>…<h6> and a font-weight of bold, bolder or 600 and
//    up are bold (a weight under 600, or normal, is not, whatever the tag
//    said); <i>, <em>, <cite>, <var>, <dfn> and font-style italic or
//    oblique are italic; <u>, <ins> and text-decoration underline are
//    underlined; <s>, <del>, <strike> and line-through are struck;
//    text-decoration none takes both away.
//  - <a href> links its words; color (#rgb, #rrggbb, #rrggbbaa, rgb(),
//    rgba() — alpha last — and the basic names) and <font color> colour
//    them; font-size in px — pt as 4/3 px — is a size in design units, a
//    share of the box's type size (boxSize) to two places, none when it is
//    the box's own; a font-family or <font face> is kept only when it names
//    one of the library's families (by name or key).
//  - <br> is a line break; <p>, <div>, the headings, <li>, <ul>, <ol>, <tr>
//    and the other blocks (blocks) start a line of their own unless the
//    line is empty; <li> makes its line an item of the list round it —
//    "bullet" in <ul>, "number" in <ol> — at the level of how deep the
//    lists are, from 0; outside a list it is a plain line.
//  - Runs of spaces, tabs, line ends and no-break spaces are one space, and
//    none starts or ends a line; empty lines at the end are dropped.
//  - Entities are decoded (&amp; &lt; &gt; &quot; &apos; &#39; &nbsp; and
//    the typographic ones the Android twin knows, and &#NNN; &#xHH;);
//    <script>, <style>, <head>, <title>, <noscript> and <template> are
//    dropped whole, and comments too.
//  - RTF (read by the system) keeps bold, italic, underline, strike, links
//    and colours, but not sizes, fonts or black — RTF's own ink, which the
//    box's colour stands for — as the Android twin's RTF reader does.

import Foundation
import UIKit

enum ForeignText {

    /// The setting: whether a paste from another app keeps its formatting
    /// (on unless turned off).
    static let keepsFormattingKey = "canvia.pasteKeepsFormatting"

    static var keepsFormatting: Bool {
        UserDefaults.standard.object(forKey: keepsFormattingKey) as? Bool ?? true
    }

    /// The pasteboard types read, in the order they are tried after
    /// Canvia's own.
    static let htmlType = "public.html"
    static let rtfType = "public.rtf"

    /// The type size of a box a clip is read for when none is given.
    static let defaultBoxSize = 42.0

    /// The look of a stretch of words.
    struct TextLook: Equatable {
        var style = RichText.Style()
        var link: String?
        var color: String?
        var scale: Double?
        var font: String?
    }

    /// Another app's styled words on `board` as a clip for a box of type
    /// `boxSize` — its HTML first, then its RTF — while pastes keep their
    /// formatting (keepsFormatting); nil for none, or words with nothing in
    /// them.
    static func clip(on board: UIPasteboard, boxSize: Double) -> RichClipboard.Clip? {
        guard keepsFormatting else { return nil }
        if let data = board.data(forPasteboardType: htmlType), let html = String(data: data, encoding: .utf8) {
            let clip = fromHtml(html, boxSize: boxSize)
            if !clip.plain.isEmpty { return clip }
        }
        if let data = board.data(forPasteboardType: rtfType), let clip = fromRtf(data), !clip.plain.isEmpty {
            return clip
        }
        return nil
    }

    /// A text box of `clip`'s words in their styles, at `fontSize`, as wide
    /// as its widest line needs — its longest word at least, `maxWidth` at
    /// most — and as tall as its lines: what a styled paste onto the page
    /// makes.
    static func element(_ clip: RichClipboard.Clip, fontSize: Double, maxWidth: Double) -> Element {
        var el = Element.text(clip.text, fontSize: fontSize, w: maxWidth)
        el.setSpans(clip.spans)
        if clip.paragraphs.contains(where: \.isListed) { el.setLines(clip.paragraphs) }
        let natural = FontLibrary.naturalWidth(for: el)
        el.w = min(max(FontLibrary.lineWidth(for: el), natural) + 1, max(maxWidth, natural)).rounded(.up)
        el.h = FontLibrary.layoutHeight(for: el)
        return el
    }

    // MARK: building a clip

    /// Words gathered a stretch at a time, a line at a time, then made a
    /// clip.
    struct Builder {
        private var chars: [Character] = []
        private var looks: [TextLook] = []
        private(set) var lines: [TextParagraph] = [TextParagraph()]

        /// Whether the line being written has any words yet.
        var lineHasText: Bool { !(chars.last.map { $0 == "\n" } ?? true) }

        /// `text` in `look`. Collapsed (HTML), each run of white space is
        /// one space, and none starts a line or follows a space.
        mutating func add(_ text: String, _ look: TextLook, collapse: Bool) {
            for c in text {
                if c == "\n" && !collapse {
                    newLine()
                    continue
                }
                if collapse && (c.isWhitespace || c == "\u{a0}") {
                    guard lineHasText, chars.last != " " else { continue }
                    chars.append(" ")
                    looks.append(look)
                    continue
                }
                chars.append(c)
                looks.append(look)
            }
        }

        /// A line break, the new line in `paragraph`.
        mutating func newLine(_ paragraph: TextParagraph = TextParagraph()) {
            trimLineEnd()
            chars.append("\n")
            looks.append(TextLook())
            lines.append(paragraph)
        }

        /// A line of its own from here: a break, unless the line is empty.
        mutating func breakLine() {
            if lineHasText { newLine() }
        }

        /// The line being written in `paragraph`.
        mutating func setParagraph(_ paragraph: TextParagraph) {
            lines[lines.count - 1] = paragraph
        }

        /// No space at the end of the line being written.
        private mutating func trimLineEnd() {
            while chars.last == " " {
                chars.removeLast()
                looks.removeLast()
            }
        }

        /// The words as a clip: written with their markers
        /// (RichText.written), links, colours, sizes and fonts as spans,
        /// and a paragraph for each line — none at all when no line is a
        /// list item.
        func clip() -> RichClipboard.Clip {
            var b = self
            b.trimLineEnd()
            while b.chars.last == "\n" {
                b.chars.removeLast()
                b.looks.removeLast()
                b.lines.removeLast()
                b.trimLineEnd()
            }
            let plain = String(b.chars)
            let text = RichText.written(plain, styles: b.looks.map(\.style))
            var spans: [TextSpan] = []
            var offset = 0
            for (c, look) in zip(b.chars, b.looks) {
                let length = c.utf16.count
                if look.link != nil || look.color != nil || look.scale != nil || look.font != nil {
                    spans.append(TextSpan(start: offset, end: offset + length, color: look.color, scale: look.scale,
                                          font: look.font, link: look.link))
                }
                offset += length
            }
            let listed = b.lines.contains { $0.isListed }
            return RichClipboard.Clip(plain: RichText.strip(text), text: text, spans: Spans.normalised(spans),
                                      paragraphs: listed ? b.lines : [])
        }
    }

    // MARK: HTML

    /// `html` as a clip for a box of type `boxSize`, by the rules above.
    static func fromHtml(_ html: String, boxSize: Double = defaultBoxSize) -> RichClipboard.Clip {
        var walker = HtmlWalker(boxSize: boxSize)
        walker.walk(Array(html.replacingOccurrences(of: "\r\n", with: "\n")))
        return walker.builder.clip()
    }

    private struct Frame {
        var name: String
        var look: TextLook
    }

    private struct HtmlWalker {
        let boxSize: Double
        var builder = Builder()
        var stack: [Frame] = []
        /// The lists round the words, innermost last: "bullet" or "number".
        var lists: [String] = []

        static let blocks: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "tr",
                                          "table", "section", "article", "header", "footer", "dl", "dt", "dd", "figure",
                                          "figcaption", "address", "hr", "main", "nav", "aside"]
        static let voids: Set<String> = ["br", "img", "hr", "meta", "link", "input", "wbr", "col", "area", "base",
                                         "source", "param", "embed"]
        static let dropped: Set<String> = ["script", "style", "head", "title", "noscript", "template"]

        var look: TextLook { stack.last?.look ?? TextLook() }

        mutating func walk(_ chars: [Character]) {
            var i = 0
            var text = ""
            while i < chars.count {
                guard chars[i] == "<" else {
                    text.append(chars[i])
                    i += 1
                    continue
                }
                flush(&text)
                // A comment, to its end.
                if starts(chars, i, "<!--") {
                    i = find(chars, from: i + 4, "-->").map { $0 + 3 } ?? chars.count
                    continue
                }
                var j = i + 1
                var quote: Character?
                while j < chars.count {
                    let c = chars[j]
                    if let q = quote {
                        if c == q { quote = nil }
                    } else if c == "\"" || c == "'" {
                        quote = c
                    } else if c == ">" {
                        break
                    }
                    j += 1
                }
                let inside = String(chars[(i + 1)..<min(j, chars.count)])
                i = j + 1
                let name = tag(inside)
                // Dropped whole: everything to its closing tag.
                if !inside.hasPrefix("/"), Self.dropped.contains(name) {
                    i = find(chars, from: i, "</\(name)", ignoringCase: true)
                        .flatMap { find(chars, from: $0, ">") }.map { $0 + 1 } ?? chars.count
                    continue
                }
                if inside.hasPrefix("/") {
                    close(name)
                } else if !inside.hasPrefix("!") && !inside.hasPrefix("?") {
                    open(name, attributes: Self.attributes(inside), selfClosing: inside.hasSuffix("/"))
                }
            }
            flush(&text)
        }

        mutating func flush(_ text: inout String) {
            guard !text.isEmpty else { return }
            let current = look
            builder.add(ForeignText.decodeEntities(text), current, collapse: true)
            text = ""
        }

        mutating func open(_ name: String, attributes: [String: String], selfClosing: Bool) {
            switch name {
            case "br":
                builder.newLine()
            case "ul", "ol":
                builder.breakLine()
                lists.append(name == "ol" ? "number" : "bullet")
            case "li":
                builder.breakLine()
                // An item outside a list is a plain line.
                if let list = lists.last {
                    let level = min(max(lists.count - 1, 0), TextLists.maxLevel)
                    builder.setParagraph(TextParagraph(list: list, level: level))
                }
            default:
                if Self.blocks.contains(name) { builder.breakLine() }
            }
            guard !Self.voids.contains(name), !selfClosing else { return }
            var next = look
            switch name {
            case "b", "strong", "h1", "h2", "h3", "h4", "h5", "h6": next.style.bold = true
            case "i", "em", "cite", "var", "dfn": next.style.italic = true
            case "u", "ins": next.style.underline = true
            case "s", "del", "strike": next.style.strike = true
            case "a":
                if let href = attributes["href"] { next.link = href.trimmingCharacters(in: .whitespacesAndNewlines) }
            case "font":
                if let color = attributes["color"].flatMap(ForeignText.cssColour) { next.color = color }
                if let face = attributes["face"].flatMap(ForeignText.fontKey) { next.font = face }
            default: break
            }
            if let css = attributes["style"] { ForeignText.applyCss(css, to: &next, boxSize: boxSize) }
            stack.append(Frame(name: name, look: next))
        }

        mutating func close(_ name: String) {
            if let k = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(k...) }
            switch name {
            case "ul", "ol":
                if !lists.isEmpty { lists.removeLast() }
                builder.breakLine()
            case "li":
                builder.breakLine()
            default:
                if Self.blocks.contains(name) { builder.breakLine() }
            }
        }

        /// A tag's name, lower case, without its slash.
        func tag(_ inside: String) -> String {
            let body = inside.hasPrefix("/") ? inside.dropFirst() : Substring(inside)
            let name = body.prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" }
            return name.lowercased()
        }

        /// A tag's attributes by lower-case name, values unquoted and their
        /// entities decoded.
        static func attributes(_ inside: String) -> [String: String] {
            var out: [String: String] = [:]
            let chars = Array(inside)
            var i = chars.firstIndex(where: { $0.isWhitespace }) ?? chars.count
            while i < chars.count {
                while i < chars.count, chars[i].isWhitespace || chars[i] == "/" { i += 1 }
                let start = i
                while i < chars.count, !chars[i].isWhitespace, chars[i] != "=", chars[i] != "/" { i += 1 }
                let name = String(chars[start..<i]).lowercased()
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                guard i < chars.count, chars[i] == "=" else {
                    if !name.isEmpty { out[name] = "" }
                    continue
                }
                i += 1
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                var value = ""
                if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                    let q = chars[i]
                    i += 1
                    while i < chars.count, chars[i] != q { value.append(chars[i]); i += 1 }
                    i += 1
                } else {
                    while i < chars.count, !chars[i].isWhitespace { value.append(chars[i]); i += 1 }
                }
                if !name.isEmpty { out[name] = ForeignText.decodeEntities(value) }
            }
            return out
        }

        func starts(_ chars: [Character], _ at: Int, _ word: String) -> Bool {
            let w = Array(word)
            guard at + w.count <= chars.count else { return false }
            return Array(chars[at..<(at + w.count)]) == w
        }

        func find(_ chars: [Character], from: Int, _ word: String, ignoringCase: Bool = false) -> Int? {
            let w = Array(ignoringCase ? word.lowercased() : word)
            guard !w.isEmpty, from <= chars.count - w.count else { return nil }
            for k in from...(chars.count - w.count) {
                let part = chars[k..<(k + w.count)]
                if ignoringCase ? Array(String(part).lowercased()) == w : Array(part) == w { return k }
            }
            return nil
        }
    }

    /// Entities in `text` as the characters they stand for; one this does
    /// not know is left as it is.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{a0}", "mdash": "\u{2014}",
            "ndash": "\u{2013}", "hellip": "\u{2026}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}",
            "rdquo": "\u{201D}", "bull": "\u{2022}", "copy": "\u{A9}", "reg": "\u{AE}", "trade": "\u{2122}",
            "euro": "\u{20AC}", "pound": "\u{A3}", "yen": "\u{A5}", "middot": "\u{B7}", "deg": "\u{B0}", "times": "\u{D7}",
        ]
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(12).firstIndex(of: ";") {
                let name = String(after[..<semi])
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
                } else {
                    decoded = named[name]
                }
                if let decoded {
                    out += decoded
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }

    /// An inline style's declarations on `look`, its sizes shares of
    /// `boxSize`.
    static func applyCss(_ css: String, to look: inout TextLook, boxSize: Double) {
        for declaration in css.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
                .replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
            switch key {
            case "font-weight":
                if value == "bold" || value == "bolder" {
                    look.style.bold = true
                } else if let n = Double(value) {
                    look.style.bold = n >= 600
                } else if value == "normal" || value == "lighter" {
                    look.style.bold = false
                }
            case "font-style":
                look.style.italic = value == "italic" || value.hasPrefix("oblique")
            case "text-decoration", "text-decoration-line":
                if value.contains("none") {
                    look.style.underline = false
                    look.style.strike = false
                }
                if value.contains("underline") { look.style.underline = true }
                if value.contains("line-through") { look.style.strike = true }
            case "color":
                if let colour = cssColour(value) { look.color = colour }
            case "font-size":
                if let px = cssPixels(value) { look.scale = sizeScale(px, boxSize: boxSize) }
            case "font-family":
                let first = parts[1].split(separator: ",").first.map(String.init) ?? ""
                if let key = fontKey(first) { look.font = key }
            default:
                break
            }
        }
    }

    /// A source size of `px` — design units — as a share of `boxSize`, the
    /// type size of the box it goes into, to two places; nil for none or
    /// the box's own size. The Android twin's rule.
    static func sizeScale(_ px: Double, boxSize: Double) -> Double? {
        guard px > 0, px.isFinite, boxSize > 0 else { return nil }
        let scale = (px / boxSize * 100).rounded() / 100
        return scale == 1 ? nil : scale
    }

    /// "12px", "9pt" as pixels; nil for any other unit.
    static func cssPixels(_ value: String) -> Double? {
        if value.hasSuffix("px") { return Double(value.dropLast(2).trimmingCharacters(in: .whitespaces)) }
        if value.hasSuffix("pt") {
            return Double(value.dropLast(2).trimmingCharacters(in: .whitespaces)).map { $0 * 4 / 3 }
        }
        return nil
    }

    /// The basic colour names a style may give.
    static let namedColours: [String: String] = [
        "black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000", "blue": "#0000ff",
        "yellow": "#ffff00", "orange": "#ffa500", "purple": "#800080", "gray": "#808080", "grey": "#808080",
        "navy": "#000080", "teal": "#008080", "maroon": "#800000", "olive": "#808000", "silver": "#c0c0c0",
        "lime": "#00ff00", "aqua": "#00ffff", "fuchsia": "#ff00ff", "pink": "#ffc0cb", "brown": "#a52a2a",
    ]

    /// A CSS colour — a basic name, "#abc", "#aabbcc", "#aabbccdd", or
    /// rgb()/rgba() with numbers or percentages — as "#rrggbb", alpha last
    /// ("#rrggbbaa") when it is not whole; nil for anything else. The
    /// Android twin's ForeignText.colour.
    static func cssColour(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        if let named = namedColours[v] { return named }
        if v.hasPrefix("#") {
            let digits = String(v.dropFirst())
            guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit) else { return nil }
            switch digits.count {
            case 3: return "#" + digits.map { "\($0)\($0)" }.joined()
            case 6: return "#" + digits
            case 8: return digits.hasSuffix("ff") ? "#" + String(digits.prefix(6)) : "#" + digits
            default: return nil
            }
        }
        guard v.hasPrefix("rgb"), let open = v.firstIndex(of: "("), let shut = v.firstIndex(of: ")"),
              open < shut else { return nil }
        let parts = v[v.index(after: open)..<shut].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .map(String.init)
        guard parts.count >= 3 else { return nil }
        func channel(_ p: String) -> Int? {
            let n = p.hasSuffix("%") ? Double(p.dropLast()).map { $0 * 2.55 } : Double(p)
            guard let n, n.isFinite else { return nil }
            return Int(min(max((n + 0.5).rounded(.down), 0), 255))
        }
        var rgb: [Int] = []
        for part in parts.prefix(3) {
            guard let c = channel(part) else { return nil }
            rgb.append(c)
        }
        var alpha = 1.0
        if parts.count > 3 {
            let a = parts[3]
            if let n = a.hasSuffix("%") ? Double(a.dropLast()).map({ $0 / 100 }) : Double(a), n.isFinite {
                alpha = min(max(n, 0), 1)
            }
        }
        let hex = String(format: "#%02x%02x%02x", rgb[0], rgb[1], rgb[2])
        return alpha >= 1 ? hex : hex + String(format: "%02x", Int((alpha * 255 + 0.5).rounded(.down)))
    }

    /// The library family a source's font names — by its name or its key,
    /// letter case aside, quotes and spaces round it left out; nil for one
    /// the library has not.
    static func fontKey(_ family: String) -> String? {
        let name = family.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespaces)).lowercased()
        guard !name.isEmpty else { return nil }
        return FontLibrary.all.first { $0.name.lowercased() == name || $0.id.lowercased() == name }?.id
    }

    // MARK: RTF and attributed strings

    /// `rtf` as a clip, read by the system; nil when it cannot be read.
    static func fromRtf(_ rtf: Data) -> RichClipboard.Clip? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.rtf]
        guard let read = try? NSAttributedString(data: rtf, options: options, documentAttributes: nil) else { return nil }
        return fromAttributed(read)
    }

    static func fromRtf(text rtf: String) -> RichClipboard.Clip? {
        rtf.data(using: .utf8).flatMap { fromRtf($0) }
    }

    /// An attributed string's words as a clip, by the same rules as the
    /// Android twin's RTF reader: its fonts' bold and italic traits,
    /// underline, strikethrough, links, colours other than black (RTF's own
    /// ink, the \cf0 the box's colour stands for), a line separator (RTF's
    /// \line) a line break, and each paragraph's text list — a numbered
    /// marker format a "number" list, any other a "bullet" one, at its
    /// depth — its marker ("\t•\t") left out of the words. Sizes and fonts
    /// are not taken.
    static func fromAttributed(_ attributed: NSAttributedString) -> RichClipboard.Clip {
        var builder = Builder()
        let ns = attributed.string as NSString
        var location = 0
        while location < ns.length {
            let line = ns.paragraphRange(for: NSRange(location: location, length: 0))
            var start = line.location
            if let style = attributed.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle,
               let list = style.textLists.last {
                let numbered = ["decimal", "upper", "lower"].contains { list.markerFormat.rawValue.contains($0) }
                let level = min(style.textLists.count - 1, TextLists.maxLevel)
                builder.setParagraph(TextParagraph(list: numbered ? "number" : "bullet", level: level))
                // The marker the system writes before the words.
                let head = ns.substring(with: line) as NSString
                if head.hasPrefix("\t") {
                    let second = head.range(of: "\t", range: NSRange(location: 1, length: head.length - 1))
                    if second.location != NSNotFound { start = line.location + second.location + 1 }
                }
            }
            let body = NSRange(location: start, length: NSMaxRange(line) - start)
            attributed.enumerateAttributes(in: body) { attrs, part, _ in
                let words = ns.substring(with: part).replacingOccurrences(of: "\u{2028}", with: "\n")
                builder.add(words, look(of: attrs), collapse: false)
            }
            location = NSMaxRange(line)
        }
        return builder.clip()
    }

    /// The look attributes give words.
    static func look(of attrs: [NSAttributedString.Key: Any]) -> TextLook {
        var look = TextLook()
        if let font = attrs[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            look.style.bold = traits.contains(.traitBold)
            look.style.italic = traits.contains(.traitItalic)
        }
        if let underline = attrs[.underlineStyle] as? Int, underline != 0 { look.style.underline = true }
        if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 { look.style.strike = true }
        if let url = attrs[.link] as? URL {
            look.link = url.absoluteString
        } else if let link = attrs[.link] as? String {
            look.link = link
        }
        if let colour = attrs[.foregroundColor] as? UIColor, colour.hexString != "#000000" {
            look.color = colour.hexString
        }
        return look
    }
}

// Colours, sizes, fonts and links on chosen words inside one text element.
//
// Written as the element's `spans`: stretches of the words as they read —
// RichText.strip(text), before any capitals — in UTF-16 offsets, as
// RichText.Run counts them, each with a colour, a size (a scale on the
// box's type size, so fitting and corner-resizing keep working), a font (a
// key as `fontFamily` stores it, a font of your own's "custom:" too), a
// weight and a slant of their own (the family's cut, as the box's
// fontWeight and italic choose one), a link (a web address, email or phone
// number, as Links reads one) or several.
// Beside them `spansText` holds the very words the offsets were made for:
// should the words have been changed by a build that does not carry spans
// along, the two no longer agree and the spans are ignored — never a colour
// on the wrong letters — and dropped when the design is next saved.
//
// Every change to the words moves the spans with them (remap): text typed
// strictly inside a coloured word, or over letters all in it, takes its
// colour, text typed at either end does not, and a word deleted takes its
// colour with it. The Android twin runs the same rules over the same table
// of test vectors, row for row.

import Foundation
import UIKit

/// One stretch of words in a colour, a size, a font, a weight, a slant, a
/// link, or several.
struct TextSpan: Codable, Equatable, Hashable {
    /// UTF-16 offsets into the words as they read, end exclusive.
    var start: Int
    var end: Int
    /// "#rrggbb"; nil leaves the element's own colour.
    var color: String?
    /// The box's type size times this, 0.3 to 4; nil is the box's own.
    var scale: Double?
    /// A font key, as `fontFamily` holds one; nil is the box's own face.
    var font: String?
    /// "https://…", "http://…", "mailto:…" or "tel:…"; nil is no link.
    var link: String?
    /// A weight of the words' own, 100 to 900 as the box's fontWeight
    /// counts; nil is the box's.
    var weight: Int?
    /// Whether the words are slanted; nil is as the box is.
    var italic: Bool?
    /// A marker colour behind the words, "#rrggbb" or "#rrggbbaa"; nil is
    /// none.
    var highlight: String?

    init(start: Int, end: Int, color: String? = nil, scale: Double? = nil,
         font: String? = nil, link: String? = nil, weight: Int? = nil, italic: Bool? = nil,
         highlight: String? = nil) {
        self.start = start
        self.end = end
        self.color = color
        self.scale = scale
        self.font = font
        self.link = link
        self.weight = weight
        self.italic = italic
        self.highlight = highlight
    }

    private enum CodingKeys: String, CodingKey { case start, end, color, scale, font, link, weight, italic, highlight }

    // Each key on its own: a stretch missing its ends reads as empty and is
    // dropped when the spans are tidied, never the design.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = (try? c.decode(Int.self, forKey: .start)) ?? 0
        end = (try? c.decode(Int.self, forKey: .end)) ?? 0
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        scale = try? c.decodeIfPresent(Double.self, forKey: .scale)
        font = try? c.decodeIfPresent(String.self, forKey: .font)
        link = try? c.decodeIfPresent(String.self, forKey: .link)
        // A weight written as words, or a slant as a number, is none, as on
        // the Android twin.
        weight = try? c.decodeIfPresent(Int.self, forKey: .weight)
        italic = try? c.decodeIfPresent(Bool.self, forKey: .italic)
        highlight = try? c.decodeIfPresent(String.self, forKey: .highlight)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(scale, forKey: .scale)
        try c.encodeIfPresent(font, forKey: .font)
        try c.encodeIfPresent(link, forKey: .link)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(italic, forKey: .italic)
        try c.encodeIfPresent(highlight, forKey: .highlight)
    }

    var range: NSRange { NSRange(location: start, length: max(0, end - start)) }

    /// Whether it says anything: a colour, a size, a font, a weight, a
    /// slant, a link or a highlight.
    var says: Bool {
        color != nil || scale != nil || font != nil || link != nil || weight != nil || italic != nil || highlight != nil
    }

    /// Whether its letters are set in a face of their own: a font, a weight
    /// or a slant.
    var setsFace: Bool { font != nil || weight != nil || italic != nil }

    /// The same look over `from..<to`.
    func over(_ from: Int, _ to: Int) -> TextSpan {
        var out = self
        out.start = from
        out.end = to
        return out
    }

    /// Whether `other` has the same colour, size, font, weight, slant and
    /// link: where two differ in any of them, a run of words splits.
    func looksLike(_ other: TextSpan) -> Bool {
        color == other.color && scale == other.scale && font == other.font && link == other.link
            && weight == other.weight && italic == other.italic && highlight == other.highlight
    }
}

enum Spans {

    /// The most an element keeps; any past these are dropped.
    static let maxCount = 100
    /// How far a word's size reaches from the box's.
    static let scaleRange = 0.3...4.0
    /// What A- and A+ on the typing bar multiply a word's size by.
    static let smaller = 0.8
    static let larger = 1.25
    /// A size this close to the box's own is the box's own.
    static let scaleTolerance = 1e-9
    /// The weights a word may have of its own: the box's own range, a
    /// weight past it held to its end (950 is 900, 50 is 100) on both phones.
    static let weightRange = 100...900

    /// The attribute the drawn words carry their span's colour in, as hex,
    /// so outlines can be gathered by the colour each word is set in.
    static let colourKey = NSAttributedString.Key("CanviaSpanColour")

    /// The attribute linked words carry their link in, so the lines they are
    /// set on can be found (WordLinks).
    static let linkKey = NSAttributedString.Key("CanviaSpanLink")

    /// Linked words are drawn underlined in this — unless they have a
    /// colour of their own — as on the Android twin.
    static let linkColour = "#2563eb"

    /// The spans when they were made for `plain`, the words as they read
    /// now, tidied and cut to its length as on the Android twin; none when
    /// they were made for other words.
    static func live(_ spans: [TextSpan]?, madeFor spansText: String?, plain: String) -> [TextSpan] {
        guard let spans, !spans.isEmpty, spansText == plain else { return [] }
        return clipped(normalised(spans), to: plain.utf16.count)
    }

    /// The spans tidied: sorted, none overlapping — where two overlap, the
    /// later in the list wins — each with a colour, a size, a font, a
    /// weight, a slant or a link other than the box's own (a blank colour
    /// or font, a size of 1, or a link Links.normalized does not read as
    /// one, is none), sizes kept within `scaleRange`, weights within
    /// `weightRange`, links as Links.normalized writes them, neighbours
    /// alike in all six joined into one, and no more than `maxCount`.
    static func normalised(_ spans: [TextSpan]) -> [TextSpan] {
        let tidy = spans.compactMap { span -> TextSpan? in
            var out = span
            out.start = max(0, span.start)
            if let color = span.color {
                let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
                out.color = trimmed.isEmpty ? nil : trimmed
            }
            if let scale = span.scale {
                let kept = scale.isFinite ? min(max(scale, scaleRange.lowerBound), scaleRange.upperBound) : 1
                out.scale = abs(kept - 1) <= scaleTolerance ? nil : kept
            }
            if let font = span.font {
                let trimmed = font.trimmingCharacters(in: .whitespacesAndNewlines)
                out.font = trimmed.isEmpty ? nil : trimmed
            }
            if let link = span.link {
                out.link = Links.normalized(link)
            }
            if let weight = span.weight {
                out.weight = min(max(weight, weightRange.lowerBound), weightRange.upperBound)
            }
            if let highlight = span.highlight {
                let trimmed = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
                out.highlight = trimmed.isEmpty ? nil : trimmed
            }
            guard out.end > out.start, out.says else { return nil }
            return out
        }
        guard !tidy.isEmpty else { return [] }
        // Cut at every edge; each piece takes the last span over it.
        let edges = Set(tidy.flatMap { [$0.start, $0.end] }).sorted()
        var out: [TextSpan] = []
        for (from, to) in zip(edges, edges.dropFirst()) {
            guard let top = tidy.last(where: { $0.start <= from && $0.end >= to }) else { continue }
            if let last = out.last, last.end == from, last.looksLike(top) {
                out[out.count - 1].end = to
            } else {
                out.append(top.over(from, to))
            }
        }
        return Array(out.prefix(maxCount))
    }

    /// The spans moved from `oldPlain` onto `newPlain`, the same words
    /// edited once. What the two share at the start and then at the end is
    /// kept — never between the halves of a character kept in two — and the
    /// rest is the edit. A span before it stays and one after it moves by
    /// the change in length. Text put in strictly inside a span — not at
    /// either of its ends — takes that span's colour and size, and so does
    /// text put in over letters that were all in one span, its ends
    /// included, as a misspelling corrected or a word typed over: Canva
    /// keeps the colour of a word typed over, the same as typing inside it.
    /// A span the edit overlaps otherwise loses what was taken out, and one
    /// taken out whole goes. The Android twin's `remap`, rule for rule.
    static func remap(_ oldPlain: String, _ newPlain: String, _ spans: [TextSpan]) -> [TextSpan] {
        let old = Array(oldPlain.utf16), new = Array(newPlain.utf16)
        guard old != new else { return clipped(normalised(spans), to: new.count) }
        let shorter = min(old.count, new.count)
        var prefix = 0
        while prefix < shorter, old[prefix] == new[prefix] { prefix += 1 }
        if prefix > 0, UTF16.isLeadSurrogate(old[prefix - 1]) { prefix -= 1 }
        var suffix = 0
        while suffix < shorter - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        if suffix > 0, UTF16.isTrailSurrogate(old[old.count - suffix]) { suffix -= 1 }
        // The edit: old[from..<to] became new[from..<to + delta].
        let from = prefix, to = old.count - suffix
        let delta = new.count - old.count
        let moved = spans.flatMap { span -> [TextSpan] in
            // Typed in: only strictly inside. Typed over: every letter
            // replaced was in this span.
            let takes = from == to ? span.start < from && span.end > to : span.start <= from && span.end >= to
            var out = span
            if takes {
                out.end = span.end + delta
                return [out]
            }
            if span.end <= from { return [span] }
            if span.start >= to {
                out.start = span.start + delta
                out.end = span.end + delta
                return [out]
            }
            var pieces: [TextSpan] = []
            if span.start < from {
                out.end = from
                pieces.append(out)
            }
            if span.end > to {
                var after = span
                after.start = to + delta
                after.end = span.end + delta
                pieces.append(after)
            }
            return pieces
        }
        return clipped(normalised(moved), to: new.count)
    }

    /// The spans once the words in `range` are replaced by `length` units
    /// that stand for them — a page token by the page's number: a span over
    /// all of them takes in all of the new ones, and the rest move as an
    /// edit moves them.
    static func standingIn(_ spans: [TextSpan], range: NSRange, length: Int) -> [TextSpan] {
        let lo = range.location, hi = NSMaxRange(range), delta = length - range.length
        let moved = spans.compactMap { span -> TextSpan? in
            var out = span
            if span.start <= lo && span.end >= hi {
                out.end = span.end + delta
            } else {
                out.start = span.start < lo ? span.start : span.start >= hi ? span.start + delta : lo + length
                out.end = span.end <= lo ? span.end : span.end >= hi ? span.end + delta : lo
            }
            return out.end > out.start ? out : nil
        }
        return normalised(moved)
    }

    /// Spans cut to words `length` long.
    private static func clipped(_ spans: [TextSpan], to length: Int) -> [TextSpan] {
        spans.compactMap { span in
            guard span.start < length else { return nil }
            var out = span
            out.end = min(span.end, length)
            return out
        }
    }

    /// The words in `range` in `color` — or back in the box's colour, with
    /// nil — keeping any size they have.
    static func colouring(_ spans: [TextSpan], range: NSRange, color: String?) -> [TextSpan] {
        restyled(spans, range) { $0.color = color }
    }

    /// The words in `range` in the face `font` — or back in the box's own,
    /// with nil — keeping their colour, size and link.
    static func fonting(_ spans: [TextSpan], range: NSRange, font: String?) -> [TextSpan] {
        restyled(spans, range) { $0.font = font }
    }

    /// The words in `range` linked to `link` — or unlinked, with nil.
    static func linking(_ spans: [TextSpan], range: NSRange, link: String?) -> [TextSpan] {
        restyled(spans, range) { $0.link = link }
    }

    /// The words in `range` at `weight` — or back at the box's own, with
    /// nil — keeping their colour, size, font, slant and link: the font
    /// sheet's Weight row opened for the selected words.
    static func weighting(_ spans: [TextSpan], range: NSRange, weight: Int?) -> [TextSpan] {
        restyled(spans, range) { $0.weight = weight }
    }

    /// The words in `range` marked in `highlight` behind them — or with no
    /// marker, with nil — keeping everything else they have.
    static func highlighting(_ spans: [TextSpan], range: NSRange, highlight: String?) -> [TextSpan] {
        restyled(spans, range) { $0.highlight = highlight }
    }

    /// The words in `range` slanted or upright — or back as the box is,
    /// with nil: the font sheet's Italic toggle for the selected words.
    static func italicising(_ spans: [TextSpan], range: NSRange, italic: Bool?) -> [TextSpan] {
        restyled(spans, range) { $0.italic = italic }
    }

    /// The spans with no colours: what gradient letters, which colours on
    /// words would not show through, are drawn with.
    static func withoutColours(_ spans: [TextSpan]) -> [TextSpan] {
        normalised(spans.map { span -> TextSpan in
            var out = span
            out.color = nil
            return out
        })
    }

    /// The spans with no fonts: what a new face for the whole box leaves.
    static func withoutFonts(_ spans: [TextSpan]) -> [TextSpan] {
        normalised(spans.map { span -> TextSpan in
            var out = span
            out.font = nil
            return out
        })
    }

    /// Only the links: what Clear word colours and sizes leaves, a link not
    /// being a look — a highlight goes with the colours.
    static func linksOnly(_ spans: [TextSpan]) -> [TextSpan] {
        normalised(spans.map { TextSpan(start: $0.start, end: $0.end, link: $0.link) })
    }

    /// Whether some words have a colour, a size, a font, a weight, a slant
    /// or a highlight of their own — what Clear word colours and sizes
    /// takes off.
    static func hasStyles(_ spans: [TextSpan]) -> Bool {
        spans.contains { $0.color != nil || $0.scale != nil || $0.setsFace || $0.highlight != nil }
    }

    /// The words in `range` a step smaller or larger: each one's size times
    /// `factor`, to four places as on the Android twin, so going back down
    /// the steps it went up returns it to the box's own size, and no size is
    /// kept then.
    static func scaling(_ spans: [TextSpan], range: NSRange, by factor: Double) -> [TextSpan] {
        restyled(spans, range) { span in
            span.scale = (((span.scale ?? 1) * factor) * 10_000).rounded() / 10_000
        }
    }

    /// `spans` with every letter in `range` changed by `change` — those
    /// under no span too, starting from the box's own colour and size.
    private static func restyled(_ spans: [TextSpan], _ range: NSRange,
                                 _ change: (inout TextSpan) -> Void) -> [TextSpan] {
        let lo = max(0, range.location), hi = NSMaxRange(range)
        let tidy = normalised(spans)
        guard hi > lo else { return tidy }
        var out: [TextSpan] = []
        // The range in pieces, the gaps between spans included, as it is.
        var inside: [TextSpan] = []
        var cursor = lo
        for span in tidy {
            if span.start < lo {
                out.append(span.over(span.start, min(span.end, lo)))
            }
            if span.end > hi {
                out.append(span.over(max(span.start, hi), span.end))
            }
            let from = max(span.start, lo), to = min(span.end, hi)
            guard to > from else { continue }
            if from > cursor { inside.append(TextSpan(start: cursor, end: from)) }
            inside.append(span.over(from, to))
            cursor = to
        }
        if hi > cursor { inside.append(TextSpan(start: cursor, end: hi)) }
        for var piece in inside {
            change(&piece)
            out.append(piece)
        }
        return normalised(out.sorted { $0.start < $1.start })
    }

    /// The colour every letter in `range` is set in, when they share one —
    /// nil for the box's own — and whether they do share one. `spans` tidy.
    static func colour(of spans: [TextSpan], in range: NSRange) -> (color: String?, shared: Bool) {
        let shared = sharing(spans, range, \.color)
        return (shared.value, shared.shared)
    }

    /// The same for the font: nil for the box's own face.
    static func font(of spans: [TextSpan], in range: NSRange) -> (font: String?, shared: Bool) {
        let shared = sharing(spans, range, \.font)
        return (shared.value, shared.shared)
    }

    /// The same for the link: nil for none.
    static func link(of spans: [TextSpan], in range: NSRange) -> (link: String?, shared: Bool) {
        let shared = sharing(spans, range, \.link)
        return (shared.value, shared.shared)
    }

    /// The same for the weight: nil for the box's own.
    static func weight(of spans: [TextSpan], in range: NSRange) -> (weight: Int?, shared: Bool) {
        let shared = sharing(spans, range, \.weight)
        return (shared.value, shared.shared)
    }

    /// The same for the slant: nil for the box's own.
    static func italic(of spans: [TextSpan], in range: NSRange) -> (italic: Bool?, shared: Bool) {
        let shared = sharing(spans, range, \.italic)
        return (shared.value, shared.shared)
    }

    /// The same for the highlight: nil for none.
    static func highlight(of spans: [TextSpan], in range: NSRange) -> (highlight: String?, shared: Bool) {
        let shared = sharing(spans, range, \.highlight)
        return (shared.value, shared.shared)
    }

    // MARK: highlight marks

    /// The marker colours the typing bar offers after None, the brand's and
    /// the recent colours, on both phones.
    static let highlightPresets = ["#FFF176", "#A5D6A7", "#90CAF9", "#F48FB1", "#FFCC80"]
    /// How far a mark reaches past its words at each side, and how round its
    /// corners are, in ems of the box's type size.
    static let highlightPadEm = 0.08
    static let highlightRadiusEm = 0.15

    /// The attribute highlighted words carry their marker colour in, as
    /// hex, so the marks can be found on the drawn lines.
    static let highlightKey = NSAttributedString.Key("CanviaSpanHighlight")

    /// One mark behind words: a rounded rectangle in the box's space.
    struct HighlightRect: Equatable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var radius: Double
        var color: String
    }

    /// The marks behind one drawn line holding letters `start..<end` (the
    /// line's own, a break after it left out), from `top` to `bottom`, where
    /// `offset` gives the x of the edge before a letter: for each span with
    /// a highlight over some of the line's letters, one rectangle from the
    /// first of them to the end of the last, reaching `highlightPadEm` ems
    /// further at the left and the right — the line's full height, with no
    /// pad above or below, so marks on lines one under the other meet and
    /// never overlap — its corners `highlightRadiusEm` ems round. `em` is
    /// the box's type size as drawn. The same rule on both phones.
    static func highlightRects(_ spans: [TextSpan], start: Int, end: Int, top: Double, bottom: Double,
                               em: Double, offset: (Int) -> Double) -> [HighlightRect] {
        let pad = em * highlightPadEm, radius = em * highlightRadiusEm
        return spans.compactMap { span -> HighlightRect? in
            guard let color = span.highlight else { return nil }
            let from = max(span.start, start), to = min(span.end, end)
            guard to > from else { return nil }
            let left = offset(from), right = offset(to)
            return HighlightRect(x: left - pad, y: top, w: right - left + 2 * pad, h: bottom - top,
                                 radius: radius, color: color)
        }
    }

    /// What every letter in `range` has of `key`, nil where no span is, and
    /// whether they all have the same.
    private static func sharing<T: Equatable>(_ spans: [TextSpan], _ range: NSRange,
                                              _ key: KeyPath<TextSpan, T?>) -> (value: T?, shared: Bool) {
        let lo = range.location, hi = NSMaxRange(range)
        var values: [T?] = []
        var cursor = lo
        for span in spans where span.end > lo && span.start < hi {
            if span.start > cursor { values.append(nil) }
            values.append(span[keyPath: key])
            cursor = min(span.end, hi)
        }
        if cursor < hi { values.append(nil) }
        guard let first = values.first else { return (nil, true) }
        return values.allSatisfy({ $0 == first }) ? (first, true) : (nil, false)
    }
}

extension Element {

    /// The colours, sizes, fonts and links on its words that still fit
    /// them: none when the words were changed by something that did not
    /// carry them along.
    var liveSpans: [TextSpan] {
        guard let spans, !spans.isEmpty else { return [] }
        return Spans.live(spans, madeFor: spansText, plain: RichText.strip(text ?? ""))
    }

    /// The words changed to `new`, the colours and sizes on them moved
    /// along (Spans.remap) and written down against the new words, and the
    /// lists and levels on its lines with them (TextLists.remap). Every way
    /// the words are changed comes through here.
    mutating func setText(_ new: String) {
        let oldPlain = RichText.strip(text ?? "")
        let kept = liveSpans
        let lines = TextLists.paragraphsOf(self)
        text = new
        moveLines(from: oldPlain, lines)
        guard spans != nil || spansText != nil else { return }
        setSpans(Spans.remap(oldPlain, RichText.strip(new), kept))
    }

    /// "{page}" and "{pages}" filled in with the page's number and the
    /// number of pages, where the page is known; a colour or size on a token
    /// stays on the number that stands for it, and each line keeps its list.
    mutating func fillPageTokens(number: Int, count: Int) {
        guard let raw = text, raw.contains("{page") else { return }
        let oldPlain = RichText.strip(raw)
        let lines = TextLists.paragraphsOf(self)
        var moved = liveSpans
        var words = raw
        for (token, value) in [("{pages}", String(count)), ("{page}", String(number))] {
            // From the last back, so the ones before stay where they were.
            var before = (words as NSString).length
            while true {
                let ns = words as NSString
                let hit = ns.range(of: token, options: .backwards, range: NSRange(location: 0, length: before))
                guard hit.location != NSNotFound else { break }
                if !moved.isEmpty, let plain = RichText.plainRange(of: hit, in: words) {
                    moved = Spans.standingIn(moved, range: plain, length: (value as NSString).length)
                }
                words = ns.replacingCharacters(in: hit, with: value)
                before = hit.location
            }
        }
        text = words
        moveLines(from: oldPlain, lines)
        if spans != nil || spansText != nil { setSpans(moved) }
    }

    /// Spans for the words as they are now; none takes both keys away.
    mutating func setSpans(_ new: [TextSpan]) {
        let tidy = Spans.normalised(new)
        spans = tidy.isEmpty ? nil : tidy
        spansText = tidy.isEmpty ? nil : RichText.strip(text ?? "")
    }

    /// The whole box set in `key`: the faces chosen for words go, as a new
    /// face for the box takes every word with it.
    mutating func setFontFamily(_ key: String) {
        fontFamily = key
        guard spans != nil || spansText != nil else { return }
        setSpans(Spans.withoutFonts(liveSpans))
    }

    /// The faces it is set in, the box's own first, then its words', each
    /// once as stored: what the design's fonts of your own are gathered from.
    var fontKeys: [String] {
        var out: [String] = fontFamily.map { [$0] } ?? []
        for span in liveSpans {
            if let font = span.font, !out.contains(font) { out.append(font) }
        }
        return out
    }
}

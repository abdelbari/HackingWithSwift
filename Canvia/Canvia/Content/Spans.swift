// Colours and sizes on chosen words inside one text element.
//
// Written as the element's `spans`: stretches of the words as they read —
// RichText.strip(text), before any capitals — in UTF-16 offsets, as
// RichText.Run counts them, each with a colour, a size (a scale on the
// box's type size, so fitting and corner-resizing keep working) or both.
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

/// One stretch of words in a colour, a size, or both.
struct TextSpan: Codable, Equatable, Hashable {
    /// UTF-16 offsets into the words as they read, end exclusive.
    var start: Int
    var end: Int
    /// "#rrggbb"; nil leaves the element's own colour.
    var color: String?
    /// The box's type size times this, 0.3 to 4; nil is the box's own.
    var scale: Double?

    init(start: Int, end: Int, color: String? = nil, scale: Double? = nil) {
        self.start = start
        self.end = end
        self.color = color
        self.scale = scale
    }

    private enum CodingKeys: String, CodingKey { case start, end, color, scale }

    // Each key on its own: a stretch missing its ends reads as empty and is
    // dropped when the spans are tidied, never the design.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = (try? c.decode(Int.self, forKey: .start)) ?? 0
        end = (try? c.decode(Int.self, forKey: .end)) ?? 0
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        scale = try? c.decodeIfPresent(Double.self, forKey: .scale)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(scale, forKey: .scale)
    }

    var range: NSRange { NSRange(location: start, length: max(0, end - start)) }
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

    /// The attribute the drawn words carry their span's colour in, as hex,
    /// so outlines can be gathered by the colour each word is set in.
    static let colourKey = NSAttributedString.Key("CanviaSpanColour")

    /// The spans when they were made for `plain`, the words as they read
    /// now, tidied and cut to its length as on the Android twin; none when
    /// they were made for other words.
    static func live(_ spans: [TextSpan]?, madeFor spansText: String?, plain: String) -> [TextSpan] {
        guard let spans, !spans.isEmpty, spansText == plain else { return [] }
        return clipped(normalised(spans), to: plain.utf16.count)
    }

    /// The spans tidied: sorted, none overlapping — where two overlap, the
    /// later in the list wins — each with a colour or a size other than the
    /// box's own (a blank colour, or a size of 1, is none), sizes kept
    /// within `scaleRange`, neighbours alike joined into one, and no more
    /// than `maxCount`.
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
            guard out.end > out.start, out.color != nil || out.scale != nil else { return nil }
            return out
        }
        guard !tidy.isEmpty else { return [] }
        // Cut at every edge; each piece takes the last span over it.
        let edges = Set(tidy.flatMap { [$0.start, $0.end] }).sorted()
        var out: [TextSpan] = []
        for (from, to) in zip(edges, edges.dropFirst()) {
            guard let top = tidy.last(where: { $0.start <= from && $0.end >= to }) else { continue }
            if let last = out.last, last.end == from, last.color == top.color, last.scale == top.scale {
                out[out.count - 1].end = to
            } else {
                out.append(TextSpan(start: from, end: to, color: top.color, scale: top.scale))
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
                out.append(TextSpan(start: span.start, end: min(span.end, lo), color: span.color, scale: span.scale))
            }
            if span.end > hi {
                out.append(TextSpan(start: max(span.start, hi), end: span.end, color: span.color, scale: span.scale))
            }
            let from = max(span.start, lo), to = min(span.end, hi)
            guard to > from else { continue }
            if from > cursor { inside.append(TextSpan(start: cursor, end: from)) }
            inside.append(TextSpan(start: from, end: to, color: span.color, scale: span.scale))
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
        let lo = range.location, hi = NSMaxRange(range)
        var colours: [String?] = []
        var cursor = lo
        for span in spans where span.end > lo && span.start < hi {
            if span.start > cursor { colours.append(nil) }
            colours.append(span.color)
            cursor = min(span.end, hi)
        }
        if cursor < hi { colours.append(nil) }
        guard let first = colours.first else { return (nil, true) }
        return colours.allSatisfy({ $0 == first }) ? (first, true) : (nil, false)
    }
}

extension Element {

    /// The colours and sizes on its words that still fit them: none when
    /// the words were changed by something that did not carry them along.
    var liveSpans: [TextSpan] {
        guard let spans, !spans.isEmpty else { return [] }
        return Spans.live(spans, madeFor: spansText, plain: RichText.strip(text ?? ""))
    }

    /// The words changed to `new`, the colours and sizes on them moved
    /// along (Spans.remap) and written down against the new words. Every
    /// way the words are changed comes through here.
    mutating func setText(_ new: String) {
        let oldPlain = RichText.strip(text ?? "")
        let kept = liveSpans
        text = new
        guard spans != nil || spansText != nil else { return }
        setSpans(Spans.remap(oldPlain, RichText.strip(new), kept))
    }

    /// "{page}" and "{pages}" filled in with the page's number and the
    /// number of pages, where the page is known; a colour or size on a token
    /// stays on the number that stands for it.
    mutating func fillPageTokens(number: Int, count: Int) {
        guard let raw = text, raw.contains("{page") else { return }
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
        if spans != nil || spansText != nil { setSpans(moved) }
    }

    /// Spans for the words as they are now; none takes both keys away.
    mutating func setSpans(_ new: [TextSpan]) {
        let tidy = Spans.normalised(new)
        spans = tidy.isEmpty ? nil : tidy
        spansText = tidy.isEmpty ? nil : RichText.strip(text ?? "")
    }
}

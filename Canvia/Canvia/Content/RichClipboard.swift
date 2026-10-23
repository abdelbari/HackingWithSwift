// Words copied and pasted inside the typing field, as Canva copies them: as
// they read. The clipboard gets the plain words, which another app pastes
// as clean text, and beside them the words as Canvia keeps them — their
// bold, italic, underline and strike in markers, their colours, sizes,
// fonts, links, weights and slants (Spans), and the lists of the lines they
// cover (TextLists) — which a paste into another box here keeps:
//
//   {"canviaText":1, "text":"**Big** sale",
//    "spans":[{"start":0,"end":3,"color":"#ff0000"}],
//    "paragraphs":[{"list":"bullet"}]}
//
// "text" is the slice with its markers written again so every style opens
// and closes inside it (RichText.sliced), "spans" are moved to start at the
// slice's first letter, and "paragraphs" are the lines it covers, one each.
// Text from another app is pasted as it reads: its stars are stars
// (RichText.escapeLiteral), its bulleted or numbered lines a list
// (TextLists.fromPasted), in the box's style at the caret. The Android twin
// puts the same JSON on its clipboard under application/x-canvia-text+json,
// so words copied on one phone read the same pasted on the other.

import Foundation

enum RichClipboard {

    /// The pasteboard type the words as Canvia keeps them go under.
    static let type = "com.canvia.text+json"

    /// What a copy puts on the clipboard.
    struct Clip: Equatable {
        /// The words as they read, for any other app.
        var plain: String
        /// The words as stored, markers and all.
        var text: String
        /// Colours, sizes and the rest, over `plain`.
        var spans: [TextSpan] = []
        /// One for each line the words cover.
        var paragraphs: [TextParagraph] = []
    }

    private struct Wire: Codable {
        var canviaText: Int
        var text: String
        var spans: [TextSpan]?
        var paragraphs: [TextParagraph]?
    }

    /// Words `start..<end` of `el` — UTF-16 offsets of its words as they
    /// read — as the clipboard takes them.
    static func copy(_ el: Element, start: Int, end: Int) -> Clip {
        let text = el.text ?? ""
        let plain = RichText.strip(text) as NSString
        let lo = min(max(start, 0), plain.length)
        let hi = min(max(end, lo), plain.length)
        let spans = el.liveSpans.compactMap { span -> TextSpan? in
            let from = max(span.start, lo), to = min(span.end, hi)
            return to > from ? span.over(from - lo, to - lo) : nil
        }
        let words = plain.substring(with: NSRange(location: lo, length: hi - lo))
        let first = TextLists.lineRange(plain as String, NSRange(location: lo, length: 0)).lowerBound
        let count = words.components(separatedBy: "\n").count
        let lines = TextLists.lines(el)
        let paragraphs = (first..<(first + count)).map { $0 < lines.count ? lines[$0] : TextParagraph() }
        return Clip(plain: words, text: RichText.sliced(text, from: lo, to: hi), spans: spans,
                    paragraphs: paragraphs)
    }

    /// The JSON the clipboard keeps beside the plain words.
    static func json(_ clip: Clip) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let wire = Wire(canviaText: 1, text: clip.text, spans: clip.spans, paragraphs: clip.paragraphs)
        return (try? encoder.encode(wire)) ?? Data()
    }

    /// A clip read back from its JSON; nil for anything that is not one —
    /// another version, or no words.
    static func decode(_ data: Data?) -> Clip? {
        guard let data, let wire = try? JSONDecoder().decode(Wire.self, from: data),
              wire.canviaText == 1 else { return nil }
        return Clip(plain: RichText.strip(wire.text), text: wire.text, spans: wire.spans ?? [],
                    paragraphs: wire.paragraphs ?? [])
    }

    /// `el` with `clip` pasted over the `removed` UTF-16 units of its words
    /// as they read from `at`: its words in their own styles
    /// (RichText.splicing), the box's colours and sizes moved along
    /// (Spans.remap) and the clip's put on its words, and its lines' lists
    /// merged (lists).
    static func paste(_ el: Element, at: Int, removed: Int, clip: Clip) -> Element {
        let text = el.text ?? ""
        let range = NSRange(location: max(0, at), length: max(0, removed))
        var out = el
        let lines = TextLists.lines(el)
        let oldPlain = RichText.strip(text)
        out.setText(RichText.splicing(clip.text, over: range, in: text))
        let length = (clip.plain as NSString).length
        let shifted = clip.spans.compactMap { span -> TextSpan? in
            let to = min(span.end, length)
            return to > span.start ? span.over(span.start + range.location, to + range.location) : nil
        }
        if !shifted.isEmpty { out.setSpans(out.liveSpans + shifted) }
        merge(&out, lines: lines, from: oldPlain, at: range.location, pasted: clip.paragraphs)
        return out
    }

    /// `el` with `plainText` from another app pasted the same way: read as
    /// written, its bulleted and numbered lines a list (TextLists.fromPasted),
    /// in the box's style at the caret (RichText.typing).
    static func paste(_ el: Element, at: Int, removed: Int, plainText: String) -> Element {
        let text = el.text ?? ""
        let pasted = TextLists.fromPasted(plainText)
        let stored = RichText.storedRange(of: NSRange(location: max(0, at), length: max(0, removed)), in: text)
        let lines = TextLists.lines(el)
        let oldPlain = RichText.strip(text)
        var out = el
        out.setText(RichText.typing(pasted.text, over: stored, in: text, pending: nil).text)
        let listed = pasted.paragraphs.contains { $0.isListed }
        merge(&out, lines: lines, from: oldPlain, at: max(0, at), pasted: listed ? pasted.paragraphs : [])
        return out
    }

    /// The lists of `el`'s lines after a paste at `at`: each line keeps its
    /// own (TextLists.remap from `oldPlain`), and of several lines pasted,
    /// every one after the first takes the list it was copied with — and so
    /// does the first, when it was pasted at a line's start. One line
    /// pasted leaves the lists as they are. The rule both phones share.
    private static func merge(_ el: inout Element, lines: [TextParagraph], from oldPlain: String, at: Int,
                              pasted: [TextParagraph]) {
        let plain = RichText.strip(el.text ?? "")
        var now = TextLists.remap(oldPlain, plain, lines)
        if pasted.count > 1 {
            let first = TextLists.lineRange(plain, NSRange(location: at, length: 0)).lowerBound
            let ns = plain as NSString
            let atStart = at == 0 || (at <= ns.length && ns.character(at: at - 1) == 0x0A)
            for (i, p) in pasted.enumerated() where (i > 0 || atStart) && first + i < now.count {
                now[first + i] = p
            }
        }
        if now != TextLists.lines(el) { el.setLines(now) }
    }
}

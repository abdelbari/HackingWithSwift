// Captions on a text box — Canva's Video ▸ Captions: the words said in a
// clip or a voice-over, timed to the page, drawn one cue at a time as the
// page plays. A caption box is an ordinary text element with `captions`:
// {"source": "video:<id>" | "audio:<trackId>" | null, "cues": [{"start",
// "end", "text"}, …], "style": "plain" | "box" | "highlightWord"}, its times
// in page seconds. The renderer draws only the cue at the page's moment —
// Play, Present, the MP4 and GIF — and a still shows the first cue, or the
// cue at the timeline's playhead. The box's own `text` is kept at the first
// cue's words, so anything that reads the text alone reads the right thing.
//
// The pure parts — the cue at a moment, SRT and WebVTT in and out,
// splitting long cues, moving them with a page split or a clip's trim and
// speed, grouping the words a recogniser heard — are here and tested
// (CaptionsTests, the Android twin's CaptionsTest, row for row); the
// phone's own speech recognition only supplies words (CaptionSpeech).

import CoreGraphics
import Foundation

/// One caption: shown from `start` to `end` seconds into its page.
struct CaptionCue: Codable, Equatable, Hashable {
    var start: Double
    var end: Double
    var text: String

    private enum CodingKeys: String, CodingKey { case start, end, text }

    init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    /// Strictly: a cue that is not an object with a number for its start
    /// and end and words is no cue, and Captions passes over it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        text = try c.decode(String.self, forKey: .text)
        guard start.isFinite, end.isFinite else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Not a cue"))
        }
    }
}

struct Captions: Codable, Equatable, Hashable {
    var source: String?
    var cues: [CaptionCue] = []
    var style: String = Captions.plain

    static let plain = "plain"
    static let box = "box"
    static let highlightWord = "highlightWord"
    static let styles = [plain, box, highlightWord]

    /// A line holds at most this many characters, and a cue this many lines.
    static let maxLine = 42
    static let maxLines = 2

    /// The colour the word being said is drawn in, for "highlightWord".
    static let highlightColour = "#ffd60a"

    /// Automatic cues: a new cue after a silence this long, and none longer
    /// than `maxCue` seconds; the last word is held `wordHold`.
    static let gap = 1.0
    static let maxCue = 5.0
    static let wordHold = 0.5

    private enum CodingKeys: String, CodingKey { case source, cues, style }

    init(source: String? = nil, cues: [CaptionCue] = [], style: String = Captions.plain) {
        self.source = source
        self.cues = cues
        self.style = style
    }

    /// Leniently, as the Android twin reads them: a cue that cannot be read,
    /// or ends before it starts, is passed over; the cues come sorted by
    /// start; a style this build does not know reads as plain.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)).flatMap { $0 }
        let read = (try? c.decode([Lossy<CaptionCue>].self, forKey: .cues))?.compactMap(\.value) ?? []
        cues = Self.sorted(read)
        let style = (try? c.decodeIfPresent(String.self, forKey: .style)).flatMap { $0 } ?? Self.plain
        self.style = Self.styles.contains(style) ? style : Self.plain
    }

    /// The source written as null when there is none, every cue with its
    /// three fields, the style always.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let source { try c.encode(source, forKey: .source) } else { try c.encodeNil(forKey: .source) }
        try c.encode(Self.sorted(cues), forKey: .cues)
        try c.encode(Self.styles.contains(style) ? style : Self.plain, forKey: .style)
    }

    /// `cues` each starting no earlier than 0 and ending after it starts,
    /// sorted by start.
    static func sorted(_ cues: [CaptionCue]) -> [CaptionCue] {
        cues.map { CaptionCue(start: max(0, $0.start), end: $0.end, text: $0.text) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }

    /// The cue showing `t` seconds into the page: from its start, before
    /// its end — none between cues.
    func cueAt(_ t: Double) -> CaptionCue? {
        cues.first { t >= $0.start && t < $0.end }
    }

    /// A word the phone heard, `start` seconds into the sound.
    struct Word: Equatable {
        var start: Double
        var text: String
    }

    // MARK: on a box

    /// `el` carrying `captions` — its text the first cue's words, as a
    /// still shows it, its words' own colours and lines cleared — or with
    /// no captions for nil. A box of another kind is left alone.
    static func on(_ el: Element, _ captions: Captions?) -> Element {
        guard el.type == .text else { return el }
        var out = el
        guard let captions else {
            out.captions = nil
            return out
        }
        let cues = sorted(captions.cues)
        out.spans = nil
        out.spansText = nil
        out.dropParagraphs()
        // A cue reads as it was written: its stars are stars.
        out.text = RichText.escapeLiteral(cues.first?.text ?? "")
        out.captions = Captions(source: captions.source, cues: cues,
                                style: styles.contains(captions.style) ? captions.style : plain)
        return out
    }

    /// A new caption box for a page `width` × `height`: across the lower
    /// part of the page, eight tenths of its width, two lines of white type
    /// 4.5% of the page's height tall (never under 12), six percent up from
    /// the bottom.
    static func element(width: Double, height: Double, captions: Captions) -> Element {
        let size = max(12, (height * 0.045 + 0.5).rounded(.down))
        let h = size * 1.25 * Double(maxLines)
        var box = Element.text("", fontSize: size, w: width * 0.8)
        box.x = width * 0.1
        box.y = height - h - height * 0.06
        box.h = h
        box.fontWeight = 600
        box.color = "#ffffff"
        return on(box, captions)
    }

    // MARK: drawing

    /// Whether `el` is a caption box with any cue: its words change as the
    /// page plays — even one cue comes and goes — so its page is played
    /// frame by frame, as a clip's is. The rule both phones share.
    static func plays(_ el: Element) -> Bool {
        !(el.captions?.cues.isEmpty ?? true)
    }

    /// The box as the renderer draws it `t` seconds into its page: the cue
    /// at `t` alone — none between cues — or the first cue for a still
    /// (nil). A still at a moment (`still`, the editor's playhead at rest)
    /// shows the cue there, or the first cue while the moment is before it,
    /// so a page whose words start late is not drawn blank. "box" draws a
    /// highlight bar behind the words (the Highlight text effect);
    /// "highlightWord" colours the word being said, the words
    /// sharing the cue's time evenly, in `highlightColour` — the first word
    /// in a still. A box with no captions is left alone.
    static func shown(_ el: Element, at t: Double?, still: Bool = false) -> Element {
        guard let captions = el.captions else { return el }
        let first = captions.cues.first
        let cue: CaptionCue?
        if let t {
            let at = captions.cueAt(t)
            cue = still ? (at ?? first.flatMap { t < $0.start ? $0 : nil }) : at
        } else {
            cue = first
        }
        let text = cue?.text ?? ""
        var out = el
        out.spans = nil
        out.spansText = nil
        out.dropParagraphs()
        out.text = RichText.escapeLiteral(text)
        switch captions.style {
        case box:
            out.effect = TextEffectSpec(type: "highlight")
        case highlightWord:
            guard let cue else { break }
            let words = wordRanges(text)
            guard !words.isEmpty else { break }
            let share = t.map { min(max(($0 - cue.start) / (cue.end - cue.start), 0), 0.999999) } ?? 0
            let word = words[min(words.count - 1, Int((share * Double(words.count)).rounded(.down)))]
            out.setSpans([TextSpan(start: word.start, end: word.end, color: highlightColour)])
        default:
            break
        }
        return out
    }

    /// Each word's start and end in `text`, as UTF-16 offsets, as a span
    /// counts them.
    static func wordRanges(_ text: String) -> [(start: Int, end: Int)] {
        let units = Array(text.utf16)
        func blank(_ u: UInt16) -> Bool {
            guard let scalar = UnicodeScalar(u) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        var out: [(start: Int, end: Int)] = []
        var i = 0
        while i < units.count {
            while i < units.count && blank(units[i]) { i += 1 }
            let start = i
            while i < units.count && !blank(units[i]) { i += 1 }
            if i > start { out.append((start, i)) }
        }
        return out
    }

    // MARK: files

    /// The cues in `text`, an SRT or a WebVTT file: a header, a NOTE or a
    /// cue's number is passed over, a timing line is `start --> end`
    /// (`hh:mm:ss,mmm` or `mm:ss.mmm`, the hours and what follows the end
    /// optional), the words the lines after it to the next blank line, tags
    /// such as <b> dropped. A cue with no words, or ending before it starts,
    /// is left out; the rest come sorted by start.
    static func parse(_ text: String) -> [CaptionCue] {
        let lines = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var cues: [CaptionCue] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard let arrow = line.range(of: "-->") else {
                i += 1
                continue
            }
            let start = time(String(line[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces))
            let rest = String(line[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            let end = time(rest.components(separatedBy: CharacterSet(charactersIn: " \t")).first ?? "")
            i += 1
            var words: [String] = []
            while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                words.append(lines[i].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression))
                i += 1
            }
            let said = words.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if let start, let end, end > start, !said.isEmpty {
                cues.append(CaptionCue(start: start, end: end, text: said))
            }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// Seconds for `hh:mm:ss,mmm`, `hh:mm:ss.mmm` or `mm:ss.mmm`.
    static func time(_ text: String) -> Double? {
        let parts = text.components(separatedBy: ":")
        guard parts.count == 2 || parts.count == 3,
              let secs = Double(parts[parts.count - 1].replacingOccurrences(of: ",", with: ".")),
              let mins = Int(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? Int(parts[0]) : 0
        guard let hours, secs >= 0, mins >= 0, hours >= 0 else { return nil }
        return Double(hours) * 3600 + Double(mins) * 60 + secs
    }

    /// `hh:mm:ss,mmm` for SRT; with a dot for WebVTT.
    static func timeCode(_ seconds: Double, srt: Bool) -> String {
        let total = max(0, Int((seconds * 1000).rounded()))
        let ms = total % 1000
        let s = total / 1000 % 60
        let m = total / 60000 % 60
        let h = total / 3600000
        return String(format: "%02d:%02d:%02d", h, m, s) + (srt ? "," : ".") + String(format: "%03d", ms)
    }

    /// The cues as an SRT file: numbered from 1, a blank line between.
    static func srt(_ cues: [CaptionCue]) -> String {
        var out = ""
        for (n, cue) in cues.sorted(by: { $0.start < $1.start }).enumerated() {
            out += "\(n + 1)\n"
            out += timeCode(cue.start, srt: true) + " --> " + timeCode(cue.end, srt: true) + "\n"
            out += cue.text + "\n\n"
        }
        return out
    }

    /// The cues as a WebVTT file.
    static func vtt(_ cues: [CaptionCue]) -> String {
        var out = "WEBVTT\n\n"
        for cue in cues.sorted(by: { $0.start < $1.start }) {
            out += timeCode(cue.start, srt: false) + " --> " + timeCode(cue.end, srt: false) + "\n"
            out += cue.text + "\n\n"
        }
        return out
    }

    // MARK: splitting and shifting

    /// `text` wrapped by words to lines of at most `maxLine` characters
    /// (UTF-16 units, as the Android twin counts them); a word longer than
    /// a line stands alone on its own.
    static func wrapped(_ text: String, maxLine: Int = Captions.maxLine) -> [String] {
        var out: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var line = ""
            let words = paragraph.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            for word in words {
                if line.isEmpty {
                    line = word
                } else if line.utf16.count + 1 + word.utf16.count <= maxLine {
                    line += " " + word
                } else {
                    out.append(line)
                    line = word
                }
            }
            if !line.isEmpty { out.append(line) }
        }
        return out
    }

    /// The cues each at most `maxLines` lines of `maxLine` characters: a
    /// cue's words wrapped, and one that wraps to more lines cut into cues
    /// of two lines each, its time shared out by the characters each part
    /// holds, to a hundredth of a second.
    static func split(_ cues: [CaptionCue]) -> [CaptionCue] {
        cues.flatMap { cue -> [CaptionCue] in
            let lines = wrapped(cue.text)
            guard !lines.isEmpty else { return [] }
            var parts: [String] = []
            var i = 0
            while i < lines.count {
                parts.append(lines[i..<min(i + maxLines, lines.count)].joined(separator: "\n"))
                i += maxLines
            }
            guard parts.count > 1 else { return [CaptionCue(start: cue.start, end: cue.end, text: parts[0])] }
            let total = Double(parts.reduce(0) { $0 + $1.utf16.count })
            var at = cue.start
            return parts.enumerated().map { i, part in
                let end = i == parts.count - 1 ? cue.end
                    : hundredth(at + (cue.end - cue.start) * Double(part.utf16.count) / total)
                let out = CaptionCue(start: hundredth(at), end: end, text: part)
                at = end
                return out
            }
        }
    }

    /// The cues either side of a page split `at` seconds in: the first
    /// half's, ending at the cut at the latest; the second half's, moved
    /// back by the cut and starting no earlier than 0 — a cue gone by the
    /// cut is not on the second half, nor one starting after it on the
    /// first. To a hundredth of a second.
    static func cut(_ cues: [CaptionCue], at: Double) -> (first: [CaptionCue], second: [CaptionCue]) {
        let first = cues.filter { $0.start < at }
            .map { CaptionCue(start: $0.start, end: hundredth(min($0.end, at)), text: $0.text) }
            .filter { $0.end > $0.start }
        let second = cues.filter { $0.end > at }
            .map { CaptionCue(start: hundredth(max(0, $0.start - at)), end: hundredth($0.end - at), text: $0.text) }
            .filter { $0.end > $0.start }
        return (first, second)
    }

    /// The cues of a clip's captions once the clip plays as `to` rather
    /// than `from`: each cue's page time taken back into the clip's own
    /// time by the old trim and speed and out again by the new, so the
    /// words stay on the frames they were heard in. A cue now ending
    /// before the page starts goes; one starting before it is cut to 0. To
    /// a hundredth of a second.
    static func retimed(_ cues: [CaptionCue], from: ClipPlayback, to: ClipPlayback) -> [CaptionCue] {
        let fromSpeed = from.playbackSpeed, toSpeed = to.playbackSpeed
        func page(_ t: Double) -> Double { (max(0, from.start) + t * fromSpeed - max(0, to.start)) / toSpeed }
        return cues.map { CaptionCue(start: hundredth(max(0, page($0.start))), end: hundredth(page($0.end)), text: $0.text) }
            .filter { $0.end > $0.start }
    }

    /// Cues from the words a recogniser heard, each timed: a cue runs on
    /// while the words keep coming — a new one after a silence of `gap`
    /// seconds, once it would run past `maxCue` seconds, or once another
    /// word would not fit two lines — and ends where its last word ends, a
    /// word ending where the next starts or `wordHold` on, whichever is
    /// first. Then `split`, so every cue fits its lines.
    static func fromWords(_ words: [Word]) -> [CaptionCue] {
        let sorted = words.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }
        var cues: [CaptionCue] = []
        var text = ""
        var start = sorted[0].start
        var lastEnd = start
        for (i, word) in sorted.enumerated() {
            let next = i + 1 < sorted.count ? sorted[i + 1].start : Double.greatestFiniteMagnitude
            let end = min(next, word.start + wordHold)
            let said = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let joined = text.isEmpty ? said : text + " " + said
            let fits = wrapped(joined).count <= maxLines
            if !text.isEmpty && (word.start - lastEnd >= gap || end - start > maxCue || !fits) {
                cues.append(CaptionCue(start: hundredth(start), end: hundredth(lastEnd), text: text))
                text = ""
                start = word.start
            }
            if !text.isEmpty { text += " " }
            text += said
            lastEnd = max(end, word.start + 0.01)
        }
        if !text.isEmpty { cues.append(CaptionCue(start: hundredth(start), end: hundredth(lastEnd), text: text)) }
        return split(cues)
    }

    // MARK: the film

    /// Every caption on the pages `indices` of `design`, as one film — each
    /// page's cues moved on by where its page starts, the pages end to end
    /// in that order, holding `hold` seconds each — for the .srt saved
    /// beside a video. Sorted by start.
    static func film(_ design: Design, indices: [Int], hold: (Int) -> Double) -> [CaptionCue] {
        var out: [CaptionCue] = []
        var at = 0.0
        for index in indices where design.pages.indices.contains(index) {
            for el in design.pages[index].elements {
                guard let c = el.captions else { continue }
                for cue in c.cues {
                    out.append(CaptionCue(start: hundredth(at + cue.start), end: hundredth(at + cue.end), text: cue.text))
                }
            }
            at += hold(index)
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Whether any page of `design` has captions.
    static func any(_ design: Design) -> Bool {
        design.pages.contains { $0.elements.contains { $0.captions != nil } }
    }

    /// To the hundredth, half up.
    static func hundredth(_ v: Double) -> Double {
        (v * 100 + 0.5).rounded(.down) / 100
    }
}

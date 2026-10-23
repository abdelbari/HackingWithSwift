// What a finished PDF says about itself (PDFMetadata), added after Core
// Graphics has written it: a new information dictionary, the catalog
// written again with the language, an outline of bookmarks and the
// viewer's preferences, and each picture's alt text as an annotation on its
// page. Neither Core Graphics nor PDFKit can set the language, the viewer's
// preferences or an annotation that only carries words, so the document is
// left as it was and an incremental update appended — the Android twin's
// PdfLinks, line for line where the two meet. Any PDF reader applies the
// update; a file this cannot read as expected is left untouched.

import Foundation

enum PDFUpdate {

    /// A picture's alt text, over its area on the page in PDF points from
    /// the bottom left: written as an annotation a screen reader reads.
    struct Picture: Equatable {
        var left: Double
        var bottom: Double
        var right: Double
        var top: Double
        var alt: String
    }

    /// What the file says about itself: its information dictionary
    /// (`info`, Title, Creator and Producer in that order), its language
    /// (`lang`, BCP-47), a bookmark for each page (`bookmarks`,
    /// `bookmarks[i]` the title of page i, pointing at the top of that
    /// page, or nil for a page with none — a notes page, a poster's second
    /// sheet) and each page's pictures with alt text (`figures`,
    /// `figures[i]` on page i). The viewer is asked to show the title
    /// rather than the file name.
    struct Metadata {
        var info: [(key: String, value: String)]
        var lang: String
        var bookmarks: [String?] = []
        var figures: [[Picture]] = []
    }

    /// `pdf` with `metadata` added; `pdf` as it was when it could not be.
    static func annotated(_ pdf: Data, metadata: Metadata) -> Data {
        guard let tail = update(pdf, metadata: metadata) else { return pdf }
        return pdf + tail
    }

    /// `metadata` added to the PDF at `url`, in place: only the update is
    /// written, onto its end. False, with the file as it was, when it could
    /// not be.
    @discardableResult
    static func appendUpdate(to url: URL, metadata: Metadata) -> Bool {
        guard let pdf = try? Data(contentsOf: url, options: .mappedIfSafe),
              let tail = update(pdf, metadata: metadata) else { return false }
        let size = UInt64(pdf.count)
        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        do {
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: tail)
            return true
        } catch {
            // Half an update is a broken file: back to the one written.
            try? handle.truncate(atOffset: size)
            return false
        }
    }

    // MARK: the update

    /// The update for `pdf`: the alt texts' annotations and their pages
    /// written again, the information dictionary, the outline and the
    /// catalog, a cross-reference section and a trailer, offsets counted on
    /// from its end. Nil for a file this does not know.
    static func update(_ pdf: Data, metadata: Metadata) -> Data? {
        pdf.withUnsafeBytes { raw -> Data? in
            Writer(text: Bytes(raw: raw), metadata: metadata).update()
        }
    }

    /// The file's bytes, read as text one character a byte, so every index
    /// is a byte offset — without copying them.
    private struct Bytes {
        let raw: UnsafeRawBufferPointer
        var count: Int { raw.count }

        func starts(with s: String, at i: Int) -> Bool {
            let u = Array(s.utf8)
            guard i >= 0, i + u.count <= count else { return false }
            for k in 0..<u.count where raw[i + k] != u[k] { return false }
            return true
        }

        func index(of s: String, from: Int) -> Int? {
            guard let first = s.utf8.first else { return nil }
            var i = max(0, from)
            while i < count {
                if raw[i] == first && starts(with: s, at: i) { return i }
                i += 1
            }
            return nil
        }

        /// Bytes `from` up to `to` as Latin-1 text: one UTF-16 unit a byte,
        /// so an NSRange in it is a byte range.
        func string(_ from: Int, _ to: Int) -> String {
            let a = max(0, from), b = min(count, to)
            guard a < b else { return "" }
            return String(bytes: raw[a..<b], encoding: .isoLatin1) ?? ""
        }

        func isSpace(_ i: Int) -> Bool {
            let c = raw[i]
            return c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0x00
        }

        /// The dictionary that opens at `start`, nested ones included;
        /// strings are stepped over, which a page or trailer needs no more.
        func dictionary(at start: Int) -> String? {
            guard start >= 0, starts(with: "<<", at: start) else { return nil }
            var depth = 0
            var i = start
            while i < count - 1 {
                if starts(with: "<<", at: i) {
                    depth += 1
                    i += 2
                } else if starts(with: ">>", at: i) {
                    depth -= 1
                    i += 2
                    if depth == 0 { return string(start, i) }
                } else if raw[i] == UInt8(ascii: "(") {
                    i = endOfString(i)
                } else {
                    i += 1
                }
            }
            return nil
        }

        private func endOfString(_ open: Int) -> Int {
            var depth = 0
            var i = open
            while i < count {
                switch raw[i] {
                case UInt8(ascii: "\\"): i += 1
                case UInt8(ascii: "("): depth += 1
                case UInt8(ascii: ")"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default: break
                }
                i += 1
            }
            return count
        }
    }

    private struct Writer {
        let text: Bytes
        let metadata: Metadata

        func update() -> Data? {
            // The last startxref is in the file's last kilobyte or so.
            let tail = text.string(max(0, text.count - 2048), text.count)
            guard let startxref = PDFUpdate.firstGroup(#"startxref\s+(\d+)\s+%%EOF\s*$"#, in: tail).flatMap({ Int($0) }),
                  text.starts(with: "xref", at: startxref),   // an xref stream: not a file this knows
                  let trailerAt = text.index(of: "trailer", from: startxref),
                  let open = text.index(of: "<<", from: trailerAt),
                  let trailer = text.dictionary(at: open),
                  let size = PDFUpdate.firstGroup(#"/Size\s+(\d+)"#, in: trailer).flatMap({ Int($0) }),
                  let root = PDFUpdate.reference(trailer, "Root") else { return nil }
            let offsets = xref(startxref)

            func objectText(_ number: Int) -> String? {
                guard var at = offsets[number] else { return nil }
                while at < text.count && text.isSpace(at) { at += 1 }
                // The header right there, not the next one anywhere on.
                let head = text.string(at, at + 64)
                guard let match = PDFUpdate.match(#"^(\d+)\s+\d+\s+obj"#, in: head),
                      Int((head as NSString).substring(with: match.range(at: 1))) == number,
                      let open = text.index(of: "<<", from: at + match.range.length) else { return nil }
                return text.dictionary(at: open)
            }

            /// The array object `number` is, "[" to "]" with neither
            /// written: a page's annotations kept apart, as Core Graphics
            /// writes its links, which hold references and nothing nested.
            func arrayText(_ number: Int) -> String? {
                guard var at = offsets[number] else { return nil }
                while at < text.count && text.isSpace(at) { at += 1 }
                let head = text.string(at, at + 64)
                guard let match = PDFUpdate.match(#"^(\d+)\s+\d+\s+obj\s*\["#, in: head),
                      Int((head as NSString).substring(with: match.range(at: 1))) == number,
                      let close = text.index(of: "]", from: at + match.range.length) else { return nil }
                return text.string(at + match.range.length, close)
            }

            guard let catalog = objectText(root), let pagesRoot = PDFUpdate.reference(catalog, "Pages") else { return nil }
            var pages: [Int] = []
            func walk(_ number: Int, depth: Int) {
                guard depth <= 32, let dict = objectText(number) else { return }
                if PDFUpdate.match(#"/Type\s*/Pages\b"#, in: dict) != nil {
                    guard let kids = PDFUpdate.firstGroup(#"/Kids\s*\[([^\]]*)\]"#, in: dict) else { return }
                    for kid in PDFUpdate.allGroups(#"(\d+)\s+0\s+R"#, in: kids) {
                        if let n = Int(kid) { walk(n, depth: depth + 1) }
                    }
                } else {
                    pages.append(number)
                }
            }
            walk(pagesRoot, depth: 0)
            guard !pages.isEmpty else { return nil }

            var out = Data()
            var position = text.count
            func emit(_ s: String) {
                // One byte a character: every one written is Latin-1.
                let bytes = Data(s.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
                out.append(bytes)
                position += bytes.count
            }
            // An update starts on a line of its own.
            if text.count > 0 && text.raw[text.count - 1] != UInt8(ascii: "\n") { emit("\n") }

            var written: [Int: Int] = [:]
            var next = size
            for (index, pageFigures) in metadata.figures.enumerated() where !pageFigures.isEmpty && index < pages.count {
                let page = pages[index]
                guard let dict = objectText(page) else { continue }
                // The page's own annotations — its links — kept, when they
                // are an array of their own the page's is written in place of.
                var refs: [String] = PDFUpdate.reference(dict, "Annots").flatMap(arrayText)
                    .map { PDFUpdate.allGroups(#"(\d+\s+\d+\s+R)"#, in: $0) } ?? []
                // A picture's alt text: a widget over its area with nothing
                // to draw and nothing to click, whose contents a screen
                // reader reads in the page's order.
                for figure in pageFigures {
                    let number = next
                    next += 1
                    written[number] = position
                    let rect = "[\(num(figure.left)) \(num(figure.bottom)) \(num(figure.right)) \(num(figure.top))]"
                    emit("\(number) 0 obj\n<< /Type /Annot /Subtype /Widget /Rect \(rect) "
                         + "/Border [0 0 0] /F 4 /Contents \(PDFUpdate.textString(figure.alt)) >>\nendobj\n")
                    refs.append("\(number) 0 R")
                }
                written[page] = position
                emit("\(page) 0 obj\n\(PDFUpdate.withAnnots(dict, refs))\nendobj\n")
            }
            // The information dictionary afresh, in place of the writer's.
            let newInfo = next
            next += 1
            written[newInfo] = position
            let entries = metadata.info.map { " /\($0.key) \(PDFUpdate.textString($0.value))" }.joined()
            emit("\(newInfo) 0 obj\n<<\(entries) >>\nendobj\n")
            // The outline: one entry a page, each pointing at the top of its
            // page, chained to the one before and after.
            let titles: [(page: Int, title: String)] = metadata.bookmarks.prefix(pages.count).enumerated()
                .compactMap { i, title in title.map { (page: pages[i], title: $0) } }
            var outlines: Int?
            if !titles.isEmpty {
                let head = next
                next += 1
                let items = titles.indices.map { next + $0 }
                next += titles.count
                outlines = head
                written[head] = position
                emit("\(head) 0 obj\n<< /Type /Outlines /First \(items[0]) 0 R /Last \(items[items.count - 1]) 0 R "
                     + "/Count \(items.count) >>\nendobj\n")
                for (n, entry) in titles.enumerated() {
                    let top = objectText(entry.page).flatMap(PDFUpdate.mediaBoxTop)
                    let dest = top.map { "[\(entry.page) 0 R /XYZ 0 \(num($0)) null]" } ?? "[\(entry.page) 0 R /XYZ null null null]"
                    let prev = n > 0 ? " /Prev \(items[n - 1]) 0 R" : ""
                    let after = n + 1 < items.count ? " /Next \(items[n + 1]) 0 R" : ""
                    written[items[n]] = position
                    emit("\(items[n]) 0 obj\n<< /Title \(PDFUpdate.textString(entry.title)) /Parent \(head) 0 R"
                         + "\(prev)\(after) /Dest \(dest) >>\nendobj\n")
                }
            }
            // The catalog again, saying the language, the outline and that
            // the title is what a viewer shows; anything it said before of
            // those is replaced.
            var stripped = catalog
            for pattern in [#"/Lang\s*\([^)]*\)"#, #"/Lang\s*<[^>]*>"#, #"/Outlines\s+\d+\s+0\s+R"#,
                            #"/ViewerPreferences\s*<<[^>]*>>"#] {
                stripped = PDFUpdate.removing(pattern, from: stripped)
            }
            let outlinePart = outlines.map { " /Outlines \($0) 0 R" } ?? ""
            written[root] = position
            emit("\(root) 0 obj\n\(String(stripped.dropLast(2))) /Lang \(PDFUpdate.literal(metadata.lang))\(outlinePart) "
                 + "/ViewerPreferences << /DisplayDocTitle true >> >>\nendobj\n")

            let xrefAt = position
            // The free list's head first, as Acrobat writes an update.
            var table = "xref\n0 1\n0000000000 65535 f \n"
            // Runs of consecutive numbers, each a subsection of its own.
            let numbers = written.keys.sorted()
            var i = 0
            while i < numbers.count {
                var j = i
                while j + 1 < numbers.count && numbers[j + 1] == numbers[j] + 1 { j += 1 }
                table += "\(numbers[i]) \(j - i + 1)\n"
                for k in i...j {
                    let offset = String(written[numbers[k]] ?? 0)
                    table += String(repeating: "0", count: max(0, 10 - offset.count)) + offset + " 00000 n \n"
                }
                i = j + 1
            }
            emit(table)
            // An update's trailer carries the old one's entries, the file's
            // identifier among them.
            let idPart = PDFUpdate.match(#"/ID\s*\[[^\]]*\]"#, in: trailer).map { " " + (trailer as NSString).substring(with: $0.range) } ?? ""
            emit("trailer\n<< /Size \(next) /Root \(root) 0 R /Info \(newInfo) 0 R\(idPart) /Prev \(startxref) >>\n"
                 + "startxref\n\(xrefAt)\n%%EOF\n")
            return out
        }

        /// Every in-use entry of the cross-reference sections from `at` back
        /// through each /Prev, the newest winning.
        private func xref(_ at: Int) -> [Int: Int] {
            var offsets: [Int: Int] = [:]
            var section: Int? = at
            var guardCount = 0
            while let start = section, guardCount < 64 {
                guardCount += 1
                let cursor = start + 4
                guard let trailerAt = text.index(of: "trailer", from: cursor) else { break }
                let lines = text.string(cursor, trailerAt).components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                var n = 0
                while n < lines.count {
                    let head = lines[n].split(separator: " ")
                    if head.count == 2, let number = Int(head[0]), let count = Int(head[1]) {
                        for k in 0..<count where n + 1 + k < lines.count {
                            let entry = lines[n + 1 + k].split(separator: " ")
                            if entry.count >= 3, entry[2] == "n", let offset = Int(entry[0]), offsets[number + k] == nil {
                                offsets[number + k] = offset
                            }
                        }
                        n += count + 1
                    } else {
                        n += 1
                    }
                }
                guard let open = text.index(of: "<<", from: trailerAt), let trailer = text.dictionary(at: open) else { break }
                section = PDFUpdate.firstGroup(#"/Prev\s+(\d+)"#, in: trailer).flatMap { Int($0) }
            }
            return offsets
        }

        private func num(_ v: Double) -> String { String(format: "%.2f", v) }
    }

    // MARK: text

    private static func match(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let m = match(pattern, in: text), m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return (text as NSString).substring(with: m.range(at: 1))
    }

    private static func allGroups(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func removing(_ pattern: String, from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                              withTemplate: "")
    }

    private static func reference(_ dict: String, _ key: String) -> Int? {
        firstGroup("/\(key)\\s+(\\d+)\\s+0\\s+R", in: dict).flatMap { Int($0) }
    }

    /// The page's dictionary with `refs` added to its annotations.
    private static func withAnnots(_ dict: String, _ refs: [String]) -> String {
        let ns = dict as NSString
        if let existing = match(#"/Annots\s*\["#, in: dict) {
            let close = ns.range(of: "]", range: NSRange(location: existing.range.upperBound,
                                                         length: ns.length - existing.range.upperBound))
            if close.location != NSNotFound {
                return ns.substring(to: close.location) + " " + refs.joined(separator: " ") + ns.substring(from: close.location)
            }
        }
        // A reference to an array elsewhere is replaced: the update's own
        // list, which starts with that array's references, stands for the
        // page from now on.
        let stripped = removing(#"/Annots\s+\d+\s+0\s+R"#, from: dict)
        return String(stripped.dropLast(2)) + " /Annots [\(refs.joined(separator: " "))] >>"
    }

    /// Words — a title, a bookmark, an alt text — as a PDF text string: hex
    /// UTF-16BE behind a byte-order mark, so any language's go in whole.
    static func textString(_ s: String) -> String {
        "<FEFF" + s.utf16.map { String(format: "%04X", $0) }.joined() + ">"
    }

    /// An ASCII value — a language tag — as a literal string.
    static func literal(_ s: String) -> String {
        let ascii = String(String.UnicodeScalarView(s.unicodeScalars.filter { (32...126).contains($0.value) }))
        let escaped = ascii.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        return "(" + escaped + ")"
    }

    /// The top of a page's MediaBox, in points, or nil when the page's
    /// dictionary does not say (it may inherit one).
    private static func mediaBoxTop(_ dict: String) -> Double? {
        let pattern = #"/MediaBox\s*\[\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\]"#
        guard let m = match(pattern, in: dict), m.numberOfRanges > 4 else { return nil }
        return Double((dict as NSString).substring(with: m.range(at: 4)))
    }
}

// What a finished PDF says about itself (PDFMetadata), added after Core
// Graphics has written it: a new information dictionary, the catalog
// written again with the language, an outline of bookmarks and the
// viewer's preferences, and each picture's alt text as an annotation on its
// page. Neither Core Graphics nor PDFKit can set the language, the viewer's
// preferences or an annotation that only carries words, so the document is
// left as it was and an incremental update appended — the Android twin's
// PdfLinks, line for line where the two meet. Any PDF reader applies the
// update; a file this cannot read as expected is left untouched.
//
// Tagged (PdfTags), the update also writes each page's content again with
// its sentinels turned into marked content, the structure tree and its
// parent tree, and the catalog's /MarkInfo — the twin's PdfLinks again.

import Compression
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
        /// The structure to tag the file with, `tags[i]` page i's, or nil
        /// for an untagged file (PdfTags).
        var tags: [PageTags?]? = nil
    }

    /// A page's structure (`nodes`, PdfTags.page) and the elements drawn on
    /// it in the order their sentinels were (`drawn`: sentinel k is
    /// `drawn[k - 1]`). The page's content streams are written again with
    /// the sentinels turned into marked content (PdfTags.mark), and the
    /// structure tree written to match: a /Sect for the page under one
    /// /Document, the page given /StructParents and /Tabs /S.
    struct PageTags {
        var nodes: [PdfTags.StructNode]
        var drawn: [String]
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

            /// Where object `number`'s body starts, past its header.
            func bodyAt(_ number: Int) -> Int? {
                guard var at = offsets[number] else { return nil }
                while at < text.count && text.isSpace(at) { at += 1 }
                // The header right there, not the next one anywhere on.
                let head = text.string(at, at + 64)
                guard let match = PDFUpdate.match(#"^(\d+)\s+\d+\s+obj"#, in: head),
                      Int((head as NSString).substring(with: match.range(at: 1))) == number else { return nil }
                return at + match.range.length
            }

            func objectText(_ number: Int) -> String? {
                guard let body = bodyAt(number), let open = text.index(of: "<<", from: body) else { return nil }
                return text.dictionary(at: open)
            }

            /// Stream object `number`'s dictionary and its bytes, undecoded.
            func streamOf(_ number: Int) -> (dict: String, data: Data)? {
                guard let body = bodyAt(number), let open = text.index(of: "<<", from: body),
                      let dict = text.dictionary(at: open) else { return nil }
                var at = open + (dict as NSString).length
                while at < text.count && text.isSpace(at) { at += 1 }
                guard text.starts(with: "stream", at: at) else { return nil }
                at += "stream".utf8.count
                if at < text.count && text.raw[at] == 0x0D { at += 1 }
                if at < text.count && text.raw[at] == 0x0A { at += 1 }
                var length = PDFUpdate.firstGroup(#"/Length\s+(\d++)(?!\s+\d+\s+R)"#, in: dict).flatMap { Int($0) }
                if length == nil, let n = PDFUpdate.reference(dict, "Length"), let b = bodyAt(n) {
                    length = PDFUpdate.firstGroup(#"^\s*(\d+)"#, in: text.string(b, b + 32)).flatMap { Int($0) }
                }
                guard let length, length >= 0, at + length <= text.count else { return nil }
                return (dict, Data(text.raw[at..<(at + length)]))
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
                emitBytes(PDFUpdate.latin1(s))
            }
            func emitBytes(_ bytes: Data) {
                out.append(bytes)
                position += bytes.count
            }
            // An update starts on a line of its own.
            if text.count > 0 && text.raw[text.count - 1] != UInt8(ascii: "\n") { emit("\n") }

            var written: [Int: Int] = [:]
            var next = size
            let tags = metadata.tags
            // Each tagged page's marked content: its MCIDs, in order, and the
            // element each draws.
            var marked: [Int: [PdfTags.Marked]] = [:]
            let pageCount = min(max(metadata.figures.count, tags?.count ?? 0), pages.count)
            for index in 0..<pageCount {
                let pageFigures = index < metadata.figures.count ? metadata.figures[index] : []
                let pageTags: PageTags? = tags.flatMap { index < $0.count ? $0[index] : nil }
                guard !pageFigures.isEmpty || pageTags != nil else { continue }
                let page = pages[index]
                guard let dict = objectText(page) else { continue }
                if let pageTags {
                    // Each content stream again, its sentinels marked content.
                    let contents = PDFUpdate.firstGroup(#"/Contents\s*(\[[^\]]*\]|\d+\s+0\s+R)"#, in: dict) ?? ""
                    let roles = PdfTags.roles(pageTags.nodes)
                    var pageMarked: [PdfTags.Marked] = []
                    for ref in PDFUpdate.allGroups(#"(\d+)\s+0\s+R"#, in: contents) {
                        guard let number = Int(ref), let stream = streamOf(number),
                              let plain = PDFUpdate.decoded(stream.dict, stream.data) else { continue }
                        let result = PdfTags.mark(plain, drawn: pageTags.drawn, roleOf: { roles[$0] },
                                                  firstMcid: pageMarked.count)
                        guard let packed = PDFUpdate.deflated(PDFUpdate.latin1(result.content)) else { continue }
                        pageMarked += result.marked
                        written[number] = position
                        emit("\(number) 0 obj\n<< /Length \(packed.count) /Filter /FlateDecode >>\nstream\n")
                        emitBytes(packed)
                        emit("\nendstream\nendobj\n")
                    }
                    marked[index] = pageMarked
                }
                guard !pageFigures.isEmpty else {
                    written[page] = position
                    emit("\(page) 0 obj\n\(PDFUpdate.withStructParents(dict, key: index))\nendobj\n")
                    continue
                }
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
                let annotated = PDFUpdate.withAnnots(dict, refs)
                written[page] = position
                emit("\(page) 0 obj\n\(pageTags == nil ? annotated : PDFUpdate.withStructParents(annotated, key: index))\nendobj\n")
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
            // The structure tree: one /Document, a /Sect a tagged page, and
            // each page's structure under it; the parent tree says, a page
            // at a time, which element each MCID belongs to.
            var structRoot: Int?
            if let tags {
                let rootNumber = next
                let document = next + 1
                let parentTree = next + 2
                next += 3
                structRoot = rootNumber
                var parents: [Int: [Int?]] = [:]
                var sects: [Int] = []
                func writeNode(_ node: PdfTags.StructNode, parent: Int, index: Int, mcids: [String: [Int]]) -> Int {
                    let number = next
                    next += 1
                    let kids = node.kids.map { writeNode($0, parent: number, index: index, mcids: mcids) }
                    let own = node.ids.flatMap { mcids[$0] ?? [] }
                    for m in own where m < (parents[index]?.count ?? 0) { parents[index]?[m] = number }
                    let k = (own.map { String($0) } + kids.map { String($0) + " 0 R" }).joined(separator: " ")
                    let alt = node.alt.map { " /Alt \(PDFUpdate.textString($0))" } ?? ""
                    let actual = node.text.map { " /ActualText \(PDFUpdate.textString($0))" } ?? ""
                    let scope = node.role == PdfTags.th ? " /A << /O /Table /Scope /Column >>" : ""
                    written[number] = position
                    emit("\(number) 0 obj\n<< /Type /StructElem /S /\(node.role) /P \(parent) 0 R /Pg \(pages[index]) 0 R "
                         + "/K [\(k)]\(alt)\(actual)\(scope) >>\nendobj\n")
                    return number
                }
                for (index, pageTags) in tags.enumerated() where index < pages.count {
                    guard let pageTags else { continue }
                    let pageMarked = marked[index] ?? []
                    parents[index] = Array(repeating: nil, count: pageMarked.count)
                    var mcids: [String: [Int]] = [:]
                    for m in pageMarked { mcids[m.elementId, default: []].append(m.mcid) }
                    let sect = next
                    next += 1
                    sects.append(sect)
                    let kids = pageTags.nodes.map { writeNode($0, parent: sect, index: index, mcids: mcids) }
                    let k = kids.map { String($0) + " 0 R" }.joined(separator: " ")
                    written[sect] = position
                    emit("\(sect) 0 obj\n<< /Type /StructElem /S /\(PdfTags.sect) /P \(document) 0 R /Pg \(pages[index]) 0 R "
                         + "/K [\(k)] >>\nendobj\n")
                }
                let sectRefs = sects.map { String($0) + " 0 R" }.joined(separator: " ")
                written[document] = position
                emit("\(document) 0 obj\n<< /Type /StructElem /S /\(PdfTags.document) /P \(rootNumber) 0 R "
                     + "/K [\(sectRefs)] >>\nendobj\n")
                let nums = parents.keys.sorted().map { index -> String in
                    let refs = (parents[index] ?? []).map { r in r.map { String($0) + " 0 R" } ?? "null" }
                    return String(index) + " [" + refs.joined(separator: " ") + "]"
                }
                written[parentTree] = position
                emit("\(parentTree) 0 obj\n<< /Nums [\(nums.joined(separator: " "))] >>\nendobj\n")
                let nextKey = (parents.keys.max() ?? -1) + 1
                written[rootNumber] = position
                emit("\(rootNumber) 0 obj\n<< /Type /StructTreeRoot /K [\(document) 0 R] /ParentTree \(parentTree) 0 R "
                     + "/ParentTreeNextKey \(nextKey) /RoleMap << >> >>\nendobj\n")
            }
            // The catalog again, saying the language, the outline and that
            // the title is what a viewer shows — and, tagged, its structure
            // and that it is marked; anything it said before of those is
            // replaced.
            var stripped = catalog
            for pattern in [#"/Lang\s*\([^)]*\)"#, #"/Lang\s*<[^>]*>"#, #"/Outlines\s+\d+\s+0\s+R"#,
                            #"/ViewerPreferences\s*<<[^>]*>>"#, #"/MarkInfo\s*<<[^>]*>>"#,
                            #"/StructTreeRoot\s+\d+\s+0\s+R"#] {
                stripped = PDFUpdate.removing(pattern, from: stripped)
            }
            let outlinePart = outlines.map { " /Outlines \($0) 0 R" } ?? ""
            let structPart = structRoot.map { " /MarkInfo << /Marked true >> /StructTreeRoot \($0) 0 R" } ?? ""
            written[root] = position
            emit("\(root) 0 obj\n\(String(stripped.dropLast(2))) /Lang \(PDFUpdate.literal(metadata.lang))\(outlinePart) "
                 + "/ViewerPreferences << /DisplayDocTitle true >>\(structPart) >>\nendobj\n")

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

    /// A tagged page's dictionary: its key into the parent tree, and its
    /// tab order the structure's.
    private static func withStructParents(_ dict: String, key: Int) -> String {
        let stripped = removing(#"/Tabs\s*/\w+"#, from: removing(#"/StructParents\s+\d+"#, from: dict))
        return String(stripped.dropLast(2)) + " /StructParents \(key) /Tabs /S >>"
    }

    /// Text one character a byte, as everything the update writes is.
    static func latin1(_ s: String) -> Data {
        Data(s.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
    }

    /// A content stream's operators, one character a byte: inflated when it
    /// is deflated, as Core Graphics writes it; nil for any other filter.
    static func decoded(_ dict: String, _ data: Data) -> String? {
        guard let filter = firstGroup(#"/Filter\s*(?:\[\s*)?/(\w+)"#, in: dict) else {
            return String(data: data, encoding: .isoLatin1)
        }
        guard filter == "FlateDecode", match(#"/Filter\s*\[\s*/\w+\s+/"#, in: dict) == nil,
              !dict.contains("/DecodeParms"), let plain = inflated(data) else { return nil }
        return String(data: plain, encoding: .isoLatin1)
    }

    /// A zlib stream — its 2-byte header, the deflated bytes, its check —
    /// inflated, however long it comes out, to a quarter of a gigabyte; nil
    /// when it is not one.
    static func inflated(_ packed: Data) -> Data? {
        guard packed.count > 2 else { return nil }
        let raw = packed.dropFirst(2)
        var capacity = max(packed.count * 8, 64 * 1024)
        while capacity <= 256 * 1024 * 1024 {
            let size = capacity
            var out = Data(count: size)
            let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                raw.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                    guard let to = dst.bindMemory(to: UInt8.self).baseAddress,
                          let from = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(to, size, from, raw.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard written > 0 else { return nil }
            // Filled to the brim: there may be more, so again with more room.
            if written < size { return out.prefix(written) }
            capacity *= 4
        }
        return nil
    }

    /// `plain` deflated as FlateDecode reads it (CmykPdf.Flate).
    static func deflated(_ plain: Data) -> Data? {
        var out = Data()
        guard let flate = try? CmykPdf.Flate(emit: { out.append($0) }) else { return nil }
        let bytes = [UInt8](plain)
        do {
            try flate.write(bytes, count: bytes.count)
            try flate.finish()
        } catch {
            return nil
        }
        return out
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

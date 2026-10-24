// A PDF brought in as editable text: its words read by PdfText, each page
// drawn as PDFImporter draws one with every line of words painted over in
// the median colour of a 3-pixel ring around it (PdfText.ringMedian), kept
// as a locked photo named "PDF page", and its paragraphs as text boxes over
// it (PdfText.editablePage) — the Android twin's PdfPages.editable.

import UIKit

enum PdfEditable {

    /// The most of a PDF read for its words, in bytes.
    static let maxTextBytes = 64 * 1024 * 1024

    /// The PDF at `url` read for its words (PdfText); nil when it is too big
    /// or does not read.
    static func text(at url: URL) -> PdfText.Outcome? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size <= maxTextBytes, let data = try? Data(contentsOf: url) else { return nil }
        return PdfText.read(data)
    }

    /// Whether any page of `outcome` would come in as editable text.
    static func hasText(_ outcome: PdfText.Outcome?) -> Bool {
        guard case .document(let pages, _)? = outcome else { return false }
        return pages.contains(where: PdfText.editable)
    }

    /// A PDF brought in as editable text: its pages, and how many of them
    /// came in as pictures instead.
    struct Editable {
        var pages: [Page]
        var pictured: Int
    }

    /// The PDF at `url`, called `name`, as pages `pageSize` big with its
    /// words editable: a page with no words, or a Type3 font, or turned by
    /// its /Rotate, comes in as its picture alone. Nil when the document's
    /// words cannot be read at all — encrypted, or not a PDF this reads —
    /// so it comes in as pictures.
    static func pages(at url: URL, name: String, pageSize: CGSize, maxEdge: CGFloat = 1600) -> Editable? {
        guard case .document(let words, _)? = text(at: url),
              let document = CGPDFDocument(url as CFURL), !document.isEncrypted else { return nil }
        var pages: [Page] = []
        var pictured = 0
        let count = min(document.numberOfPages, words.count, PdfText.maxPages)
        guard count > 0 else { return nil }
        for index in 0..<count {
            autoreleasepool {
                guard let page = document.page(at: index + 1) else { return }
                let read = words[index]
                if PdfText.editable(read), let src = drawnWithoutWords(page, words: read, maxEdge: maxEdge) {
                    pages.append(PdfText.editablePage(read, src: src, name: name, number: index + 1, pageSize: pageSize,
                                                      layerName: tr("PDF page"),
                                                      heightFor: { FontLibrary.layoutHeight(for: $0) }))
                    return
                }
                pictured += 1
                if let picture = picturePage(page, maxEdge: maxEdge, size: pageSize) { pages.append(picture) }
            }
        }
        return Editable(pages: pages, pictured: pictured)
    }

    /// A page holding the PDF page's picture alone, as large as fits and
    /// centred, as the pictures import makes one.
    private static func picturePage(_ page: CGPDFPage, maxEdge: CGFloat, size: CGSize) -> Page? {
        guard let drawn = draw(page, maxEdge: maxEdge, words: nil), let src = MediaStore.storeOpaque(drawn) else { return nil }
        let nw = max(drawn.size.width, 1), nh = max(drawn.size.height, 1)
        let scale = min(size.width / nw, size.height / nh)
        var el = Element.image(src, w: (nw * scale).rounded(), h: (nh * scale).rounded())
        el.x = ((size.width - el.w) / 2).rounded()
        el.y = ((size.height - el.h) / 2).rounded()
        return Page(elements: [el])
    }

    /// The page drawn, each of `words`' lines painted over with the colour
    /// around it, and stored; its src. Nil for a page turned by its
    /// /Rotate, whose words are not where they say.
    private static func drawnWithoutWords(_ page: CGPDFPage, words: PdfText.TextPage, maxEdge: CGFloat) -> String? {
        guard page.rotationAngle % 360 == 0 else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard abs(Double(box.width) - words.width) <= 1, abs(Double(box.height) - words.height) <= 1,
              let drawn = draw(page, maxEdge: maxEdge, words: words) else { return nil }
        return MediaStore.storeOpaque(drawn)
    }

    /// The page drawn upright over white at up to `maxEdge` pixels on its
    /// longer side, as PDFImporter draws it — and with `words`, each of
    /// their lines then painted over.
    private static func draw(_ page: CGPDFPage, maxEdge: CGFloat, words: PdfText.TextPage?) -> UIImage? {
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let rotation = page.rotationAngle
        let turned = rotation == 90 || rotation == 270
        let pageW = turned ? box.height : box.width
        let pageH = turned ? box.width : box.height
        let scale = min(maxEdge / max(pageW, pageH), 4)
        let width = max(1, Int((pageW * scale).rounded()))
        let height = max(1, Int((pageH * scale).rounded()))
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        cg.setFillColor(gray: 1, alpha: 1)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        cg.interpolationQuality = .high
        cg.saveGState()
        cg.scaleBy(x: scale, y: scale)
        cg.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: pageW, height: pageH),
                                                rotate: 0, preserveAspectRatio: true))
        cg.drawPDFPage(page)
        cg.restoreGState()
        if let words { paintOver(words, in: cg, width: width, height: height) }
        guard let image = cg.makeImage() else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    /// Each of `words`' lines (PdfText.lineBoxes) filled with the median of
    /// the ring around it, read from the page as drawn before any is filled.
    private static func paintOver(_ words: PdfText.TextPage, in cg: CGContext, width: Int, height: Int) {
        guard let data = cg.data else { return }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // The page's pixels as ARGB, a row at a time from the top: the
        // context's memory starts at its top row.
        var pixels = [UInt32](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = UInt32(bytes[i * 4]), g = UInt32(bytes[i * 4 + 1]), b = UInt32(bytes[i * 4 + 2])
            pixels[i] = 0xff00_0000 | r << 16 | g << 8 | b
        }
        let sx = Double(width) / max(words.width, 1)
        let sy = Double(height) / max(words.height, 1)
        func px(_ v: Double, _ limit: Int) -> Int { min(max(Int(v.rounded()), 0), limit) }
        for box in PdfText.lineBoxes(words) {
            let left = px(Double(box.minX) * sx, width), right = px(Double(box.maxX) * sx, width)
            let top = px(Double(box.minY) * sy, height), bottom = px(Double(box.maxY) * sy, height)
            guard right > left, bottom > top else { continue }
            let c = PdfText.ringMedian(pixels, width: width, height: height, left: left, top: top, right: right, bottom: bottom)
            cg.setFillColor(red: CGFloat((c >> 16) & 0xff) / 255, green: CGFloat((c >> 8) & 0xff) / 255,
                            blue: CGFloat(c & 0xff) / 255, alpha: 1)
            // The context's y runs up from its foot.
            cg.fill(CGRect(x: left, y: height - bottom, width: right - left, height: bottom - top))
        }
    }
}

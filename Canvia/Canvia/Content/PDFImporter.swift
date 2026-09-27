// PDF pages as pictures.
//
// A menu from the printer, a poster from last year, a slide from a deck:
// designs often start from a PDF someone already made. Each page is
// rendered to a bitmap at a sensible size and imported like a photo.

import UIKit

enum PDFImporter {

    /// Every page of the document, rendered upright at up to `maxEdge`
    /// pixels on the longer side, over white.
    static func pages(of url: URL, maxEdge: CGFloat = 1600) -> [UIImage] {
        guard let document = CGPDFDocument(url as CFURL) else { return [] }
        return (1...max(document.numberOfPages, 1)).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            return render(page, maxEdge: maxEdge)
        }
    }

    static func pages(of data: Data, maxEdge: CGFloat = 1600) -> [UIImage] {
        var images: [UIImage] = []
        forEachPage(of: data, maxEdge: maxEdge) { images.append($0) }
        return images
    }

    /// The most pages one import brings in, as on the Android twin: a
    /// hundred-page manual is not a design, and each page is a picture held
    /// in memory while it is stored.
    static let maxPages = 60

    /// What reading a PDF came to, as the Android twin tells them apart:
    /// pages, a password it cannot open, or not a PDF this phone can read.
    enum Outcome: Equatable {
        /// How many pages were rendered, of how many the document has.
        case pages(rendered: Int, total: Int)
        case locked
        case unreadable
    }

    /// Each of the first `limit` pages rendered and handed to `body` in turn,
    /// so only one is held at a time. A PDF locked with a password is found
    /// out before anything is drawn — a locked document gives no pages, which
    /// used to look like an empty one — and one whose every page fails to
    /// draw counts as unreadable.
    @discardableResult
    static func forEachPage(of data: Data, limit: Int = maxPages, maxEdge: CGFloat = 1600,
                            _ body: (UIImage) -> Void) -> Outcome {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { return .unreadable }
        // An empty user password is how most "protected" PDFs open: they
        // only restrict printing or copying.
        if document.isEncrypted && !document.isUnlocked && !document.unlockWithPassword("") { return .locked }
        guard document.numberOfPages > 0 else { return .unreadable }
        var rendered = 0
        for index in 1...min(document.numberOfPages, max(limit, 1)) {
            autoreleasepool {
                if let page = document.page(at: index), let image = render(page, maxEdge: maxEdge) {
                    body(image)
                    rendered += 1
                }
            }
        }
        return rendered == 0 ? .unreadable : .pages(rendered: rendered, total: document.numberOfPages)
    }

    /// What to say once a PDF's pages are in: nothing for a single page;
    /// how many when several came; and when fewer came than the document
    /// has — cut at the limit, or pages that would not draw — the first
    /// how many of how many, as the Android twin says it.
    static func summary(brought: Int, total: Int) -> String? {
        if total > brought { return "Brought in the first \(brought) of \(total) pages" }
        if brought > 1 { return "Brought in \(brought) pages" }
        return nil
    }

    private static func render(_ page: CGPDFPage, maxEdge: CGFloat) -> UIImage? {
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        // The page's own rotation tag turns a landscape scan the right way.
        let rotation = page.rotationAngle
        let turned = rotation == 90 || rotation == 270
        let pageW = turned ? box.height : box.width
        let pageH = turned ? box.width : box.height
        let scale = min(maxEdge / max(pageW, pageH), 4)
        let width = max(1, Int((pageW * scale).rounded()))
        let height = max(1, Int((pageH * scale).rounded()))
        // A plain bitmap context, not a UIKit renderer: its origin is
        // bottom-left with y up, which is PDF's own space, so the page draws
        // upright with no flip to get wrong — and the CGImage it makes has
        // its first row at the top like any other.
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        cg.setFillColor(gray: 1, alpha: 1)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        cg.interpolationQuality = .high
        // The scale is ours: CGPDFPage's drawing transform fits a page into
        // a rect by scaling *down* only, so asked for a bitmap larger than
        // the page in points it centres the page at 1:1 and leaves a
        // border. Scale first, then let the transform handle the crop box's
        // origin and the page's /Rotate at the page's own size.
        cg.scaleBy(x: scale, y: scale)
        let transform = page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: pageW, height: pageH),
                                                 rotate: 0, preserveAspectRatio: true)
        cg.concatenate(transform)
        cg.drawPDFPage(page)
        guard let image = cg.makeImage() else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}

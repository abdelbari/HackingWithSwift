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
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { return [] }
        return (1...max(document.numberOfPages, 1)).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            return render(page, maxEdge: maxEdge)
        }
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
        let transform = page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height),
                                                 rotate: 0, preserveAspectRatio: true)
        cg.concatenate(transform)
        cg.drawPDFPage(page)
        guard let image = cg.makeImage() else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}

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
        let size = CGSize(width: (pageW * scale).rounded(), height: (pageH * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            // PDF space has its origin at the bottom-left; the renderer's is
            // top-left. Flip, then let Quartz fit the page (rotation included).
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            let transform = page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                                     rotate: 0, preserveAspectRatio: true)
            cg.concatenate(transform)
            cg.drawPDFPage(page)
        }
    }
}

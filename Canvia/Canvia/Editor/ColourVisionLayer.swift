// Check accessibility's "View as" on the canvas: the page drawn as a picture
// (DesignExporter.render) and put through CIColorMatrix with ColourVision's
// rows, laid over the page while the sheet is open. Core Image works in
// linear light, so the rows apply as the check applies them. Never written
// to the design; it goes when the sheet does.

import SwiftUI
import CoreImage

struct ColourVisionLayer: View {
    let store: DesignStore
    let kind: ColourVision.Sight
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
            } else {
                Color.clear
            }
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Drawn again as the page changes under the sheet.
        .task(id: Key(kind: kind, page: store.page)) { draw() }
    }

    private struct Key: Equatable {
        var kind: ColourVision.Sight
        var page: Page
    }

    @MainActor
    private func draw() {
        // A picture about the size of the screen is plenty for a preview.
        let longest = max(store.pageWidth, store.pageHeight, 1)
        let scale = min(1, 1600 / longest)
        guard let drawn = DesignExporter.render(design: store.design, page: store.page, scale: scale) else {
            image = nil
            return
        }
        image = Self.filtered(drawn, kind)
    }

    private static let context = CIContext()

    /// `picture` as `kind` sees it; nil for typical sight.
    static func filtered(_ picture: CGImage, _ kind: ColourVision.Sight) -> UIImage? {
        guard let rows = ColourVision.previewVectors(kind), let filter = CIFilter(name: "CIColorMatrix") else { return nil }
        func vector(_ v: [Double]) -> CIVector {
            CIVector(x: CGFloat(v[0]), y: CGFloat(v[1]), z: CGFloat(v[2]), w: CGFloat(v[3]))
        }
        let input = CIImage(cgImage: picture)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(vector(rows[0]), forKey: "inputRVector")
        filter.setValue(vector(rows[1]), forKey: "inputGVector")
        filter.setValue(vector(rows[2]), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        guard let output = filter.outputImage,
              let made = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: made)
    }
}

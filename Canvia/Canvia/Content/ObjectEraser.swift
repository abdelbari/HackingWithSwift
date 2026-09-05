// Removing something from a photo: paint over it and the patch fills in
// from its surroundings.
//
// Not a network model — an onion-peel fill. On a small working copy, every
// masked pixel that touches an unmasked one takes the average of those
// neighbours, layer after layer until the hole is closed; the fill is then
// softened and blended back into the full-size picture through a feathered
// mask. Skies, walls, grass and tabletops come out clean; a person in front
// of a busy pattern comes out as a smudge, which is what the honest tools
// on a phone do too.

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

enum ObjectEraser {

    /// A finger stroke over an image element, mapped into the picture's own
    /// pixels: undoes the element's rotation, the crop's zoom about its
    /// focus, and the fill or fit placement. Straightening is ignored, so a
    /// levelled photo's mask lands a little off along the tilt.
    static func imagePoint(_ page: CGPoint, element el: Element, imageSize: CGSize) -> CGPoint {
        let frameW = el.w, frameH = el.h
        guard frameW > 0, frameH > 0, imageSize.width > 0, imageSize.height > 0 else { return .zero }
        // Into the element's own space: un-rotate about its centre.
        let centre = CGPoint(x: el.x + frameW / 2, y: el.y + frameH / 2)
        let a = -el.rotation * .pi / 180
        let dx = page.x - centre.x, dy = page.y - centre.y
        let local = CGPoint(x: dx * cos(a) - dy * sin(a) + frameW / 2, y: dx * sin(a) + dy * cos(a) + frameH / 2)
        // The picture as displayed: fit or fill, then offset by the focus.
        let fit = el.cropFit == true
        let scale = fit ? min(frameW / imageSize.width, frameH / imageSize.height)
                        : max(frameW / imageSize.width, frameH / imageSize.height)
        let dispW = imageSize.width * scale, dispH = imageSize.height * scale
        let cropX = el.cropX ?? 0.5, cropY = el.cropY ?? 0.5
        let offsetX = (dispW - frameW) * (0.5 - cropX), offsetY = (dispH - frameH) * (0.5 - cropY)
        let origin = CGPoint(x: frameW / 2 + offsetX - dispW / 2, y: frameH / 2 + offsetY - dispH / 2)
        // The zoom scales the displayed picture about its focus point.
        let zoom = max(el.cropScale ?? 1, 0.01)
        let anchor = CGPoint(x: origin.x + cropX * dispW, y: origin.y + cropY * dispH)
        let unzoomed = CGPoint(x: anchor.x + (local.x - anchor.x) / zoom, y: anchor.y + (local.y - anchor.y) / zoom)
        return CGPoint(x: (unzoomed.x - origin.x) / dispW * imageSize.width,
                       y: (unzoomed.y - origin.y) / dispH * imageSize.height)
    }

    /// Strokes in image pixels, each `width` pixels wide, painted into a
    /// mask of the picture's size; white is what goes.
    static func mask(size: CGSize, strokes: [[CGPoint]], width: Double) -> CGImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Image pixel space has row 0 at the top; the context's does not.
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            ctx.beginPath()
            ctx.move(to: first)
            if stroke.count == 1 { ctx.addLine(to: first) }
            for p in stroke.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    /// Grid of RGBA and a mask, both `w`×`h`, filled where the mask is set.
    /// Returns the filled pixels. Exposed for tests; the peel is the whole
    /// of the algorithm.
    static func peelFill(pixels: inout [UInt8], masked: [Bool], width w: Int, height h: Int) {
        var hole = masked
        var remaining = hole.filter { $0 }.count
        var passes = 0
        while remaining > 0 && passes < max(w, h) {
            var next = hole
            var changed = false
            for y in 0..<h {
                for x in 0..<w where hole[y * w + x] {
                    var r = 0, g = 0, b = 0, n = 0
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < w, ny < h, !hole[ny * w + nx] else { continue }
                            let i = (ny * w + nx) * 4
                            r += Int(pixels[i]); g += Int(pixels[i + 1]); b += Int(pixels[i + 2]); n += 1
                        }
                    }
                    guard n > 0 else { continue }
                    let i = (y * w + x) * 4
                    pixels[i] = UInt8(r / n); pixels[i + 1] = UInt8(g / n); pixels[i + 2] = UInt8(b / n); pixels[i + 3] = 255
                    next[y * w + x] = false
                    remaining -= 1
                    changed = true
                }
            }
            hole = next
            passes += 1
            if !changed { break }
        }
    }

    /// The picture with the masked region filled from its surroundings.
    static func erase(_ image: UIImage, strokes: [[CGPoint]], width: Double, feather: Double = 6) -> UIImage? {
        guard let cg = image.cgImage, !strokes.isEmpty,
              let maskImage = mask(size: CGSize(width: cg.width, height: cg.height), strokes: strokes, width: width) else { return nil }
        // Work small: the fill's detail is what the blur removes anyway.
        let maxEdge = 384.0
        let s = min(1, maxEdge / Double(max(cg.width, cg.height)))
        let w = max(2, Int((Double(cg.width) * s).rounded())), h = max(2, Int((Double(cg.height) * s).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        var maskPixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let mctx = CGContext(data: &maskPixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        mctx.draw(maskImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        let masked = maskPixels.map { $0 > 127 }
        guard masked.contains(true) else { return image }
        peelFill(pixels: &pixels, masked: masked, width: w, height: h)
        guard let filledSmall = ctx.makeImage() else { return nil }

        // Full size: the blurred fill shows through the feathered mask only.
        let extent = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let original = CIImage(cgImage: cg)
        let fill = CIImage(cgImage: filledSmall)
            .transformed(by: CGAffineTransform(scaleX: Double(cg.width) / Double(w), y: Double(cg.height) / Double(h)))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = fill.clampedToExtent()
        blur.radius = Float(max(2, Double(cg.width) / Double(w) * 1.5))
        let soft = (blur.outputImage ?? fill).cropped(to: extent)
        let maskBlur = CIFilter.gaussianBlur()
        maskBlur.inputImage = CIImage(cgImage: maskImage).clampedToExtent()
        maskBlur.radius = Float(feather)
        let softMask = (maskBlur.outputImage ?? CIImage(cgImage: maskImage)).cropped(to: extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = soft
        blend.backgroundImage = original
        blend.maskImage = softMask
        guard let out = blend.outputImage,
              let result = CIContext().createCGImage(out, from: extent) else { return nil }
        return UIImage(cgImage: result, scale: image.scale, orientation: .up)
    }
}

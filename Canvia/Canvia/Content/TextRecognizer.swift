// Words out of a picture, and codes out of a picture.
//
// A photo of a menu, a screenshot of a caption, a poster on a wall: Vision
// reads the text off it and the words become text elements at the spot
// they were in the picture, so a scan turns into something editable rather
// than something to retype. A QR code in a photo comes back as its payload
// and re-generates as a clean, scalable code element.

import UIKit
import Vision

enum TextRecognizer {

    struct Line: Equatable {
        var text: String
        /// Unit box, origin top-left.
        var box: CGRect
    }

    static func lines(in image: UIImage) -> [Line] { lines(in: image, languages: nil) }

    static func lines(in image: UIImage, languages: [String]?) -> [Line] {
        guard let cg = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let languages { request.recognitionLanguages = languages }
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do { try handler.perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap { obs in
            guard let top = obs.topCandidates(1).first, !top.string.isEmpty else { return nil }
            let b = obs.boundingBox
            // Vision's origin is bottom-left.
            return Line(text: top.string, box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
        }
        .sorted { $0.box.minY != $1.box.minY ? $0.box.minY < $1.box.minY : $0.box.minX < $1.box.minX }
    }

    /// Recognised lines as text elements laid over `frame` (the picture's
    /// place on the page), sized so each line's type roughly fills its box.
    static func elements(from lines: [Line], in frame: CGRect, ink: String = "#1f2430") -> [Element] {
        lines.map { line in
            let box = CGRect(x: frame.minX + line.box.minX * frame.width, y: frame.minY + line.box.minY * frame.height,
                             width: line.box.width * frame.width, height: line.box.height * frame.height)
            var el = Element.text(line.text, fontSize: max(8, (box.height * 0.8).rounded()), w: max(20, box.width.rounded() + 8))
            el.align = "left"
            el.color = ink
            el.x = box.minX.rounded(); el.y = box.minY.rounded()
            el.h = FontLibrary.layoutHeight(for: el)
            return el
        }
    }

    /// The payload of the first QR code (or other barcode) in the picture.
    static func codePayload(in image: UIImage) -> String? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }
        return (request.results ?? []).compactMap(\.payloadStringValue).first
    }
}

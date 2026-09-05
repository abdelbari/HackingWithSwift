// Tone curves as presets: the five-point curves a photographer reaches
// for, by name rather than by dragging points on a phone-sized graph.

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum ToneCurve {

    struct Preset: Identifiable, Equatable {
        var id: String
        var name: String
        /// Five points on the unit square, x ascending from 0 to 1.
        var points: [CGPoint]
    }

    static let presets: [Preset] = [
        Preset(id: "fade", name: "Fade", points: [CGPoint(x: 0, y: 0.1), CGPoint(x: 0.25, y: 0.3), CGPoint(x: 0.5, y: 0.52), CGPoint(x: 0.75, y: 0.75), CGPoint(x: 1, y: 0.95)]),
        Preset(id: "lift", name: "Lift shadows", points: [CGPoint(x: 0, y: 0.08), CGPoint(x: 0.25, y: 0.34), CGPoint(x: 0.5, y: 0.55), CGPoint(x: 0.75, y: 0.76), CGPoint(x: 1, y: 1)]),
        Preset(id: "crush", name: "Crush blacks", points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.15), CGPoint(x: 0.5, y: 0.48), CGPoint(x: 0.75, y: 0.76), CGPoint(x: 1, y: 1)]),
        Preset(id: "scurve", name: "S-curve", points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.18), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.75, y: 0.82), CGPoint(x: 1, y: 1)]),
        Preset(id: "matte", name: "Matte", points: [CGPoint(x: 0, y: 0.12), CGPoint(x: 0.25, y: 0.3), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.75, y: 0.7), CGPoint(x: 1, y: 0.9)]),
        Preset(id: "bright", name: "Brighten mids", points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.32), CGPoint(x: 0.5, y: 0.6), CGPoint(x: 0.75, y: 0.82), CGPoint(x: 1, y: 1)]),
    ]

    static func preset(_ id: String?) -> Preset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    /// The curve applied to `image` through CIToneCurve; an unknown or nil
    /// name leaves it alone.
    static func apply(_ id: String?, to image: CIImage) -> CIImage {
        guard let p = preset(id) else { return image }
        let f = CIFilter.toneCurve()
        f.inputImage = image
        f.point0 = p.points[0]
        f.point1 = p.points[1]
        f.point2 = p.points[2]
        f.point3 = p.points[3]
        f.point4 = p.points[4]
        return f.outputImage ?? image
    }
}

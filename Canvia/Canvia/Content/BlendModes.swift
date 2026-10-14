// Per-element blend modes.
//
// Multiply a texture over a photo, screen a light leak, overlay a colour
// wash: the compositing modes are what make a flat stack of layers look
// like one picture. The names are the CSS mix-blend-mode names, which are
// the SVG names too, so the same string drives the canvas, the export and
// the SVG.

import SwiftUI

enum BlendModes {

    struct Mode: Identifiable {
        var id: String
        var name: String
        var swiftUI: BlendMode
    }

    static let all: [Mode] = [
        Mode(id: "normal", name: tr("Normal"), swiftUI: .normal),
        Mode(id: "multiply", name: tr("Multiply"), swiftUI: .multiply),
        Mode(id: "screen", name: tr("Screen"), swiftUI: .screen),
        Mode(id: "overlay", name: tr("Overlay"), swiftUI: .overlay),
        Mode(id: "darken", name: tr("Darken"), swiftUI: .darken),
        Mode(id: "lighten", name: tr("Lighten"), swiftUI: .lighten),
        Mode(id: "color-dodge", name: tr("Color dodge"), swiftUI: .colorDodge),
        Mode(id: "color-burn", name: tr("Color burn"), swiftUI: .colorBurn),
        Mode(id: "soft-light", name: tr("Soft light"), swiftUI: .softLight),
        Mode(id: "hard-light", name: tr("Hard light"), swiftUI: .hardLight),
        Mode(id: "difference", name: tr("Difference"), swiftUI: .difference),
        Mode(id: "exclusion", name: tr("Exclusion"), swiftUI: .exclusion),
        Mode(id: "hue", name: tr("Hue"), swiftUI: .hue),
        Mode(id: "saturation", name: tr("Saturation"), swiftUI: .saturation),
        Mode(id: "color", name: tr("Color"), swiftUI: .color),
        Mode(id: "luminosity", name: tr("Luminosity"), swiftUI: .luminosity),
    ]

    static func mode(_ id: String?) -> Mode {
        all.first { $0.id == id } ?? all[0]
    }

    static func swiftUI(_ id: String?) -> BlendMode { mode(id).swiftUI }

    static func isNormal(_ id: String?) -> Bool { id == nil || id == "normal" }

    /// The CSS declaration for an SVG group, or nothing for normal.
    static func svgStyle(_ id: String?) -> String {
        isNormal(id) ? "" : " style=\"mix-blend-mode:\(mode(id).id)\""
    }
}

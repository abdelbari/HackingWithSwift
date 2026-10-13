// Real sizes: a design measured in millimetres, centimetres or inches as
// well as pixels, so a print design exports and prints at its true size.
//
// Pixels stay the truth. A page is still its width and height in pixels,
// and every element is placed in them; a design in a physical unit adds
// only the unit it is read in and its dots per inch, so its physical size is
// width / dpi inches. A design with neither key is pixels at 96 dpi, which
// is what every page was drawn at before units existed — its PDF comes out
// exactly as it always has. The Android twin's Units, row for row.

import Foundation

enum Units {

    /// The units a size may be typed in, in the order the pickers show them.
    static let all = ["px", "in", "mm", "cm"]

    /// What a design without a dpi of its own is at.
    static let screenDPI = 96.0
    /// What a size typed in a physical unit is stored at.
    static let printDPI = 300.0

    /// The sides the app makes, in pixels once converted: one limit on both
    /// phones, whatever unit it was typed in.
    static let pixelRange: ClosedRange<Double> = 40...8000
    static let rangeText = "40 to 8000 px"
    static let outOfRangeText = "Must be 40 to 8000 px"

    /// Millimetres, centimetres and inches; pixels — or anything a newer
    /// build writes — are not.
    static func isPhysical(_ unit: String?) -> Bool {
        unit == "mm" || unit == "cm" || unit == "in"
    }

    /// How many of `unit` make an inch.
    static func perInch(_ unit: String) -> Double {
        switch unit {
        case "mm": return 25.4
        case "cm": return 2.54
        default: return 1
        }
    }

    /// A length typed in `unit` as whole pixels at `dpi`, rounded half up:
    /// 85 mm at 300 dpi is 1004 px.
    static func pixels(_ value: Double, unit: String, dpi: Double) -> Double {
        guard isPhysical(unit), dpi > 0 else { return value.rounded() }
        return (value / perInch(unit) * dpi).rounded()
    }

    /// Pixels read in `unit` at `dpi`: 1004 px at 300 dpi is 85.01 mm.
    static func value(ofPixels px: Double, unit: String, dpi: Double) -> Double {
        guard isPhysical(unit), dpi > 0 else { return px }
        return px / dpi * perInch(unit)
    }

    /// A length as a size field and a readout show it: pixels whole,
    /// millimetres to a tenth, centimetres and inches to a hundredth, with
    /// trailing zeros dropped — "210", "29.7", "8.5".
    static func format(_ value: Double, unit: String) -> String {
        guard value.isFinite else { return "0" }
        let places: Double = unit == "mm" ? 10 : (isPhysical(unit) ? 100 : 1)
        let rounded = (value * places).rounded() / places
        if rounded == rounded.rounded(), abs(rounded) < 1e9 { return String(Int(rounded)) }
        var text = String(format: places == 10 ? "%.1f" : "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// "210 × 297 mm" for a design in a physical unit; "1080 × 1920" — the
    /// readout as it always was — in pixels.
    static func dimensions(width: Double, height: Double, unit: String?, dpi: Double?) -> String {
        guard let unit, isPhysical(unit) else { return "\(Int(width)) × \(Int(height))" }
        let d = dpi ?? printDPI
        return "\(format(value(ofPixels: width, unit: unit, dpi: d), unit: unit)) × "
            + "\(format(value(ofPixels: height, unit: unit, dpi: d), unit: unit)) \(unit)"
    }

    /// PDF points per page pixel: 72 / dpi, and 72 / 96 for a design with
    /// none.
    static func pointsPerPixel(dpi: Double?) -> Double {
        guard let dpi, dpi > 0, dpi.isFinite else { return 72 / screenDPI }
        return 72 / dpi
    }
}

/// A unit and dpi a design is resized into: nil unit is pixels, at 96.
struct UnitChoice: Equatable {
    var unit: String?
    var dpi: Double?

    /// Pixels, as every design was before units.
    static let pixels = UnitChoice(unit: nil, dpi: nil)

    /// A size typed in `unit`: physical ones at 300 dpi.
    static func typed(_ unit: String) -> UnitChoice {
        Units.isPhysical(unit) ? UnitChoice(unit: unit, dpi: Units.printDPI) : .pixels
    }
}

extension Design {
    /// The unit the design is read in, when it is a physical one.
    var physicalUnit: String? { Units.isPhysical(unit) ? unit : nil }

    /// What its pixels are at: its own dpi; else 300 for a design in a
    /// physical unit, as a size typed in one is made, and 96 in pixels.
    var effectiveDPI: Double {
        if let dpi, dpi > 0, dpi.isFinite { return dpi }
        return physicalUnit != nil ? Units.printDPI : Units.screenDPI
    }

    /// PDF points per page pixel — 72 / dpi — for every PDF and print path.
    var pointsPerPixel: Double { Units.pointsPerPixel(dpi: effectiveDPI) }

    /// A size of this design, in its own unit: "210 × 297 mm" or
    /// "1080 × 1920".
    func readout(width: Double, height: Double) -> String {
        Units.dimensions(width: width, height: height, unit: physicalUnit, dpi: dpi)
    }

    /// The design's own size so: the Home card's line.
    var sizeReadout: String { readout(width: width, height: height) }
}

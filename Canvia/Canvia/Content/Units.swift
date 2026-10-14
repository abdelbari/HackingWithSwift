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

    /// A length typed in `unit` as whole pixels at `dpi`, rounded half up —
    /// -1.5 to -1 as well, as Android's floor(x + 0.5) takes it: 85 mm at
    /// 300 dpi is 1004 px.
    static func pixels(_ value: Double, unit: String, dpi: Double) -> Double {
        guard isPhysical(unit), dpi > 0 else { return value.rounded() }
        return (value / perInch(unit) * dpi + 0.5).rounded(.down)
    }

    /// Pixels read in `unit` at `dpi`: 1004 px at 300 dpi is 85.01 mm.
    static func value(ofPixels px: Double, unit: String, dpi: Double) -> Double {
        guard isPhysical(unit), dpi > 0 else { return px }
        return px / dpi * perInch(unit)
    }

    /// A length as a size field and a readout show it: pixels whole (cut,
    /// as the readout's `Int(w)` writes them), millimetres whole,
    /// centimetres to a tenth and inches to a hundredth, with trailing zeros
    /// dropped and always a "." — "210", "29.7", "8.5". Whole millimetres,
    /// because a poster at 96 dpi is 419.89 of them and reads as the 420 it
    /// was made as. Android's Units.number, row for row.
    static func format(_ value: Double, unit: String) -> String {
        guard value.isFinite, abs(value) < 1e9 else { return "0" }
        guard isPhysical(unit) else { return String(Int(value)) }
        let places: Double = unit == "mm" ? 1 : (unit == "cm" ? 10 : 100)
        let rounded = (value * places).rounded() / places
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: unit == "cm" ? "%.1f" : "%.2f", rounded)
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

    // MARK: lengths on the page

    // Where things sit and how big they are — the Position panel's X, Y,
    // W and H, the readouts under a drag, the nudge steps and a guide's
    // typed place — read and typed in the design's own unit: to a tenth of
    // a millimetre, a hundredth of a centimetre or an inch. A design in
    // pixels reads in whole pixels, as it always did. The Android twin's
    // Units.readout, row for row.

    /// The places a length on the page is shown to in `unit`: 1 for mm, 2
    /// for cm and in, none for pixels.
    static func places(_ unit: String?) -> Int {
        switch unit {
        case "mm": return 1
        case "cm", "in": return 2
        default: return 0
        }
    }

    /// `value` to `unit`'s places, with trailing zeros and a bare "."
    /// dropped: "12.5", "40", "0.33".
    static func decimal(_ value: Double, unit: String?) -> String {
        guard value.isFinite, abs(value) < 1e9 else { return "0" }
        let places = self.places(unit)
        let scale = pow(10, Double(places))
        let rounded = (value * scale).rounded() / scale
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.\(places)f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// A length in `unit` as pixels at `dpi`, not rounded — a nudge of
    /// 0.1 mm stays 0.1 mm, where a typed length is made whole (`pixels`,
    /// `typedLength`), as on Android. Pixels as they are.
    static func exactPixels(_ value: Double, unit: String?, dpi: Double) -> Double {
        guard let unit, isPhysical(unit), dpi > 0 else { return value }
        return value / perInch(unit) * dpi
    }

    /// A length on the page, `px` pixels, as `design` reads it — the number
    /// alone, its unit said after it (`suffix`) or in the field's label:
    /// "12.5", "0.33"; in pixels the nearest whole pixel, halves up, "120".
    /// Never "-0". Android's Units.readout, with the same rows.
    static func readout(_ px: Double, _ design: Design) -> String {
        guard let unit = design.physicalUnit else { return px.isFinite ? String(Int((px + 0.5).rounded(.down))) : "0" }
        return decimal(value(ofPixels: px, unit: unit, dpi: design.effectiveDPI), unit: unit)
    }

    /// What follows a readout of `design`'s: " mm", " cm" or " in", and
    /// nothing for pixels — "x 12.5 mm", "x 120".
    static func suffix(_ design: Design) -> String {
        design.physicalUnit.map { " " + $0 } ?? ""
    }

    /// A box's size as the size badge reads it: "210 × 99 mm"; in pixels
    /// "120 × 48", cut to whole pixels as it always was.
    static func readout(width: Double, height: Double, _ design: Design) -> String {
        guard let unit = design.physicalUnit else {
            guard width.isFinite, height.isFinite else { return "0 × 0" }
            return "\(Int(width)) × \(Int(height))"
        }
        return "\(readout(width, design)) × \(readout(height, design)) \(unit)"
    }

    /// The Position panel's nudge steps in `unit`, smallest first: 0.1, 1
    /// and 10 mm; 0.01, 0.1 and 1 cm or in; 1, 10 and 100 pixels.
    static func nudgeSteps(_ unit: String?) -> [Double] {
        switch unit {
        case "mm": return [0.1, 1, 10]
        case "cm", "in": return [0.01, 0.1, 1]
        default: return [1, 10, 100]
        }
    }

    /// A position or a length typed in `unit` at `dpi` — "12.5", "12,5",
    /// "-3", "12.5 mm" — as page pixels: whole pixels for a physical unit
    /// (`pixels`), and as typed for pixels, where "120 px" reads too. Only
    /// that unit may follow the number; nil when it is not a number.
    /// Android's Units.typedLength, row for row.
    static func typedLength(_ text: String, unit: String?, dpi: Double) -> Double? {
        let physical = unit.flatMap { isPhysical($0) ? $0 : nil }
        let name = physical ?? "px"
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasSuffix(name) { t = String(t.dropLast(name.count)).trimmingCharacters(in: .whitespaces) }
        guard let value = Double(t.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        if let physical { return pixels(value, unit: physical, dpi: dpi) }
        return value
    }

    /// The same, typed in `design`'s unit.
    static func typedLength(_ text: String, _ design: Design) -> Double? {
        typedLength(text, unit: design.physicalUnit, dpi: design.effectiveDPI)
    }

    /// One of those steps in `design` as page pixels.
    static func stepPixels(_ step: Double, _ design: Design) -> Double {
        exactPixels(step, unit: design.physicalUnit, dpi: design.effectiveDPI)
    }

    /// An arrow key's step, in page pixels: the smallest nudge step, or the
    /// middle one with Shift — 1 or 10 pixels, 0.1 or 1 mm.
    static func arrowStep(_ design: Design, shift: Bool) -> Double {
        stepPixels(nudgeSteps(design.physicalUnit)[shift ? 1 : 0], design)
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

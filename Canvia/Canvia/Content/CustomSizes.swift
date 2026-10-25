// A page at whatever size is actually needed: the range a side may be, the
// ratio shortcuts, and the last few sizes typed, as the Android twin's
// custom-size sheet has them.
//
// The recent sizes are a setting of this phone, never of a design, so they
// live in UserDefaults and nothing about them reaches the file.

import Foundation

enum CustomSizes {

    /// A size as typed: whole pixels on each side.
    struct Entry: Hashable {
        var width: Int
        var height: Int

        /// "1600×900" — tight, as a chip reads it.
        var label: String { "\(width)×\(height)" }
    }

    static let key = "canvia.recentSizes"
    /// As many as fit on one row of chips.
    static let limit = 4

    /// The sides this app makes, in pixels once a size typed in another
    /// unit is converted: 40 to 8000, the same limit and words on both
    /// phones. The export budget renders a page this big at a lower scale
    /// rather than refusing it.
    static let range: ClosedRange<Double> = Units.pixelRange
    /// Stated up front, under the field, rather than first heard of as a
    /// Create button that does nothing.
    static let rangeText = Units.rangeText
    static let outOfRangeText = Units.outOfRangeText

    /// Four ratios, each keeping the width and setting the height from it.
    static let ratios: [(label: String, ratio: Double)] = [
        ("1:1", 1), ("4:5", 0.8), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16),
    ]

    /// Digits only, five at most: what a side's field keeps of what is typed
    /// or pasted into it.
    static func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(5))
    }

    /// What a side's field keeps in `unit`: digits in pixels; digits and
    /// one decimal point, seven characters at most, in mm, cm or inches.
    static func field(_ text: String, unit: String) -> String {
        guard Units.isPhysical(unit) else { return digits(text) }
        var out = ""
        var point = false
        for ch in text where ch.isASCII && (ch.isNumber || ch == "." || ch == ",") {
            if ch == "." || ch == "," {
                guard !point else { continue }
                point = true
                out.append(".")
            } else {
                out.append(ch)
            }
        }
        return String(out.prefix(7))
    }

    /// The side a field holds, in whole pixels — typed in `unit`, at 300
    /// dpi when that is a physical one — or nil when it is empty or out of
    /// range once converted.
    static func side(_ text: String, unit: String = "px") -> Double? {
        guard let value = Double(text), value > 0 else { return nil }
        let px = Units.pixels(value, unit: unit, dpi: Units.printDPI)
        return range.contains(px) ? px : nil
    }

    /// Both sides as typed, in pixels, when both are in range; nil otherwise.
    static func size(width: String, height: String, unit: String = "px") -> (width: Double, height: Double)? {
        guard let w = side(width, unit: unit), let h = side(height, unit: unit) else { return nil }
        return (w, h)
    }

    /// What Resize's custom button says: the size it will make, or, until
    /// both sides are in range, the range to type — as the Android twin's
    /// Resize button reads.
    static func resizeTitle(width: String, height: String, unit: String = "px") -> String {
        guard let size = size(width: width, height: height, unit: unit) else { return tr("Enter a size from %@", rangeText) }
        return tr("Resize to %@", title(width: size.width, height: size.height, unit: unit))
    }

    /// The height a ratio gives the width in the field — 1080 when the
    /// field holds nothing — truncated as the Android twin truncates it,
    /// and not clamped: a ratio that runs past the range says so under the
    /// field rather than quietly becoming another ratio. In mm, cm or
    /// inches, to the places the unit is shown in.
    static func height(forWidth text: String, ratio: Double, unit: String = "px") -> String {
        let base = Double(text) ?? 1080
        guard Units.isPhysical(unit) else { return String(Int(base / ratio)) }
        return Units.format(base / ratio, unit: unit)
    }

    /// Resize's Portrait | Landscape: a size turned to stand the way
    /// chosen — its longer side down for Portrait, across for Landscape; a
    /// square as it is. So A4 chosen Landscape is 297 × 210 mm without a
    /// preset of its own, as on the Android twin.
    static func turned(width: Double, height: Double, landscape: Bool) -> (width: Double, height: Double) {
        let long = max(width, height), short = min(width, height)
        return landscape ? (long, short) : (short, long)
    }

    /// Which way `width` × `height` stands: true landscape, false portrait,
    /// nil for a square, which has no way round — Resize's Portrait |
    /// Landscape shows it, and is off for a square. The Android twin's
    /// SizePresets.isLandscape.
    static func isLandscape(width: Double, height: Double) -> Bool? {
        width == height ? nil : width > height
    }

    /// The fields as Portrait or Landscape leaves them: swapped when what
    /// they hold stands the other way; as they are when square, or when
    /// either does not read as a number.
    static func turnedFields(width: String, height: String, landscape: Bool) -> (width: String, height: String) {
        guard let w = Double(width), let h = Double(height), w != h, (w > h) != landscape else { return (width, height) }
        return (height, width)
    }

    /// A side typed in one unit, written in another: what a field holds
    /// when the unit picker changes, so the size stays the size.
    static func convert(_ text: String, from old: String, to new: String) -> String {
        guard old != new, let value = Double(text), value > 0 else { return text }
        let px = Units.pixels(value, unit: old, dpi: Units.printDPI)
        return Units.format(Units.value(ofPixels: px, unit: new, dpi: Units.printDPI), unit: new)
    }

    /// A new design's name: its size, "1600 × 900".
    static func title(width: Double, height: Double) -> String {
        "\(Int(width)) × \(Int(height))"
    }

    /// The same in the unit it was typed in: "210 × 297 mm".
    static func title(width: Double, height: Double, unit: String) -> String {
        Units.dimensions(width: width, height: height, unit: unit, dpi: Units.printDPI)
    }

    /// A blank design of the size typed: whole pixels, and in a physical
    /// unit that unit at 300 dpi.
    static func design(width: Double, height: Double, unit: String) -> Design {
        var design = Design(title: title(width: width, height: height, unit: unit), width: width, height: height)
        if Units.isPhysical(unit) {
            design.unit = unit
            design.dpi = Units.printDPI
        }
        return design
    }

    /// The sizes last made here, newest first; entries that do not read as
    /// two positive sides are passed over.
    static func recent(_ defaults: UserDefaults) -> [Entry] {
        (defaults.stringArray(forKey: key) ?? []).compactMap(entry)
    }

    static func recent() -> [Entry] { recent(.standard) }

    /// Put a size at the front of the recent ones, once, keeping four.
    static func remember(width: Double, height: Double, defaults: UserDefaults) {
        let entry = "\(Int(width))x\(Int(height))"
        var list = (defaults.stringArray(forKey: key) ?? []).filter { $0 != entry && !$0.isEmpty }
        list.insert(entry, at: 0)
        defaults.set(Array(list.prefix(limit)), forKey: key)
    }

    static func remember(width: Double, height: Double) {
        remember(width: width, height: height, defaults: .standard)
    }

    /// "1600x900" as a size, as the Android twin writes it.
    private static func entry(_ raw: String) -> Entry? {
        let parts = raw.split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else { return nil }
        return Entry(width: Int(w), height: Int(h))
    }
}

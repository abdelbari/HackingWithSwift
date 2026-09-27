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

    /// The sides this app makes. Held where they were rather than widened
    /// to the Android twin's 32 to 10000: the canvas and the export budget
    /// were both sized around a 4000 × 4000 page.
    static let range: ClosedRange<Double> = 40...4000
    /// Stated up front, under the field, rather than first heard of as a
    /// Create button that does nothing.
    static let rangeText = "40 to 4000"
    static let outOfRangeText = "Must be 40 to 4000"

    /// Four ratios, each keeping the width and setting the height from it.
    static let ratios: [(label: String, ratio: Double)] = [
        ("1:1", 1), ("4:5", 0.8), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16),
    ]

    /// Digits only, five at most: what a side's field keeps of what is typed
    /// or pasted into it.
    static func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(5))
    }

    /// The side a field holds, or nil when it is empty or out of range.
    static func side(_ text: String) -> Double? {
        guard let value = Double(text), range.contains(value) else { return nil }
        return value
    }

    /// Both sides as typed, when both are in range; nil otherwise.
    static func size(width: String, height: String) -> (width: Double, height: Double)? {
        guard let w = side(width), let h = side(height) else { return nil }
        return (w, h)
    }

    /// What Resize's custom button says: the size it will make, or, until
    /// both sides are in range, the range to type — as the Android twin's
    /// Resize button reads.
    static func resizeTitle(width: String, height: String) -> String {
        guard let size = size(width: width, height: height) else { return "Enter a size from \(rangeText)" }
        return "Resize to \(Int(size.width)) × \(Int(size.height))"
    }

    /// The height a ratio gives the width in the field — 1080 when the
    /// field holds nothing — truncated as the Android twin truncates it,
    /// and not clamped: a ratio that runs past the range says so under the
    /// field rather than quietly becoming another ratio.
    static func height(forWidth text: String, ratio: Double) -> String {
        let base = Double(text) ?? 1080
        return String(Int(base / ratio))
    }

    /// A new design's name: its size, "1600 × 900".
    static func title(width: Double, height: Double) -> String {
        "\(Int(width)) × \(Int(height))"
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

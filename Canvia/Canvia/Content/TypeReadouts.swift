// The words the type controls say — beside a slider, and to VoiceOver — and
// the ranges they run over, as the Android twin's text panel has them.

import Foundation

enum TypeReadouts {

    /// Line spacing, as a multiple of the type size.
    static let lineHeightRange: ClosedRange<Double> = 0.5...2.5
    /// Paragraph spacing, in ems after each line break.
    static let paragraphSpacingRange: ClosedRange<Double> = 0...2
    /// Letter spacing's reach, as a share of the type size: Canva's −200 to
    /// 800 thousandths of an em.
    static let letterSpacingShare: ClosedRange<Double> = -0.2...0.8

    /// Letter spacing from a fifth of the type size tighter to four fifths
    /// of it looser — never narrower than -2…20, which the iPhone always
    /// allowed, and always wide enough for what the box already has. Worked
    /// out once per box and size, so it never moves under a drag. The
    /// Android twin's TextBoxes.letterSpacingRange.
    static func letterSpacingRange(size: Double, current: Double) -> ClosedRange<Double> {
        min(letterSpacingShare.lowerBound * size, -2, current)...max(letterSpacingShare.upperBound * size, 20, current)
    }

    // MARK: spacing typed

    /// Letter spacing typed as a share of type `size` in whole percent
    /// ("12", "-5%") — as its readout shows it — as the spacing it sets,
    /// within letterSpacingShare of the size; nil for anything that is not
    /// a number, which changes nothing.
    static func typedLetterSpacing(_ typed: String, size: Double) -> Double? {
        guard let percent = number(typed) else { return nil }
        let whole = min(letterSpacingShare.upperBound * 100, max(letterSpacingShare.lowerBound * 100, halfUp(percent)))
        return whole / 100 * size
    }

    /// Line spacing typed ("1.4"), to two places — as its readout shows it
    /// — within lineHeightRange; nil for anything that is not a number.
    static func typedLineHeight(_ typed: String) -> Double? {
        guard let value = number(typed) else { return nil }
        return min(lineHeightRange.upperBound, max(lineHeightRange.lowerBound, halfUp(value * 100) / 100))
    }

    /// Paragraph spacing typed in ems ("0.5"), to one place — as its
    /// readout shows it — within paragraphSpacingRange; nil for anything
    /// that is not a number.
    static func typedParagraphSpacing(_ typed: String) -> Double? {
        guard let value = number(typed) else { return nil }
        return min(paragraphSpacingRange.upperBound, max(paragraphSpacingRange.lowerBound, halfUp(value * 10) / 10))
    }

    /// `value` to the nearest whole, a half up — never to the even one, so
    /// 1.25 ems typed reads 1.3 on both phones.
    private static func halfUp(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    /// A number as typed, spaces and one "%" at its end aside and a decimal
    /// comma read as a point; nil for anything that is not a finite one.
    private static func number(_ typed: String) -> Double? {
        var trimmed = typed.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%") { trimmed.removeLast() }
        let cleaned = trimmed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// Letter spacing as a share of the size the type is drawn at: "12%".
    static func letterSpacing(_ value: Double, size: Double) -> String {
        "\(Int((value / max(size, 1) * 100).rounded()))%"
    }

    /// "1.25": two places, always.
    static func lineHeight(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// "None", or "0.4 em".
    static func paragraphSpacing(_ value: Double) -> String {
        value < 0.01 ? tr("None") : "\(Double((value * 10).rounded()) / 10) em"
    }

    /// The alignment as a word, for VoiceOver.
    static func alignment(_ align: String?) -> String {
        switch align ?? "center" {
        case "left": return tr("Left")
        case "right": return tr("Right")
        case "justify": return tr("Justify")
        default: return tr("Center")
        }
    }

    /// Left, centre, right, justify and round again: the Align button's turn.
    static func nextAlignment(after align: String?) -> String {
        switch align ?? "center" {
        case "left": return "center"
        case "center": return "right"
        case "right": return "justify"
        default: return "left"
        }
    }

    // MARK: type size

    /// How small and how large type is set: 1 to 800, Canva's reach, as the
    /// Android twin's TextBoxes.MIN_TYPE and MAX_TYPE.
    static let sizeRange: ClosedRange<Double> = 1...800

    /// The sizes listed under the typed one, as the Android twin lists them.
    static let presetSizes: [Double] = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56,
                                        64, 72, 80, 96, 120, 144, 200]

    /// A size in whole points, inside the range.
    static func wholeSize(_ size: Double) -> Double {
        min(sizeRange.upperBound, max(sizeRange.lowerBound, size.rounded()))
    }

    /// A size as typed — "24", " 36 ", "12.5" — in whole points inside the
    /// range; nil when what is typed is not a number.
    static func typedSize(_ typed: String) -> Double? {
        let number = typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(number), value.isFinite else { return nil }
        return wholeSize(value)
    }

    /// The size the size control shows: the nearest whole point, as on the
    /// Android twin, or "Mixed".
    static func fontSize(_ size: Double?) -> String {
        size.map { "\(Int($0.rounded()))" } ?? mixed
    }

    // MARK: several texts

    /// What a control says where the texts selected differ.
    static let mixed = tr("Mixed")

    /// The one value every item has, or nil when they differ or there are
    /// none.
    static func shared<T: Equatable>(_ values: [T]) -> T? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    // MARK: weights

    /// The texts the Weight row is for: every one not set in a font of your
    /// own of one face, which is drawn at its own weight whatever is asked —
    /// a family of yours with several weights here is.
    private static func weighable(_ texts: [Element]) -> [Element] {
        texts.filter(isWeighable)
    }

    /// Whether the Weight row is for `el`: not a font of your own, or one
    /// whose family offers more than one weight on this phone.
    static func isWeighable(_ el: Element) -> Bool {
        !CustomFonts.isCustom(el.fontFamily) || (FontLibrary.customWeights(el.fontFamily)?.count ?? 0) > 1
    }

    /// The weights the Weight row offers `texts`: every weight their fonts
    /// have, together, lightest first — none, and no row, when they are all
    /// in fonts of your own of one face. The Android twin's
    /// TextSelection.weights.
    static func weights(_ texts: [Element]) -> [Int] {
        Array(Set(weighable(texts).flatMap { FontLibrary.weights($0.fontFamily) })).sorted()
    }

    /// The weight every text is drawn at (FontLibrary.resolveWeight), or nil
    /// when they differ — the chip the Weight row shows chosen.
    static func drawnWeight(_ texts: [Element]) -> Int? {
        shared(weighable(texts).map { FontLibrary.resolveWeight($0.fontFamily, FontLibrary.weight(of: $0)) })
    }

    /// The Weight row's readout: the name of the weight they are drawn at
    /// ("Semibold"), or "Mixed".
    static func weightReadout(_ texts: [Element]) -> String {
        drawnWeight(texts).map(FontLibrary.weightName) ?? mixed
    }

    /// The list style as the List menu names it.
    static func listStyle(_ style: String?) -> String {
        switch style {
        case "bullet": return tr("Bullets")
        case "number": return tr("Numbers")
        case "letter": return tr("Letters")
        default: return tr("No list")
        }
    }
}

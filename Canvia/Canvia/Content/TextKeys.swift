// The hardware keyboard's formatting keys while words are typed in place:
// what Canva's are, as one table the Android twin's TextKeys shares, so the
// two phones answer the same keys with the same functions as the bar over
// the keyboard — the words chosen marked (RichText.toggling), the whole box
// set (TextSelection), the lines the choice covers listed (TextLists), the
// words chosen a step smaller or larger (Spans), the words chosen linked
// (a Spans `link`), the box's line and letter spacing a step tighter or
// looser, and its whole look copied and pasted as Copy style does — each as
// a step of its own between the words typed before and after.

import Foundation

enum TextKeys {

    /// What a key does.
    enum Command: CaseIterable, Equatable {
        case bold, italic, underline, strike, uppercase
        case alignLeft, alignCenter, alignRight, alignJustify
        case numberedList, bulletedList
        case smaller, larger
        case link
        case lineTighter, lineLooser, letterTighter, letterLooser
        case copyStyle, pasteStyle
    }

    /// The arrow keys, as `Key.key` names them.
    static let up = "↑"
    static let down = "↓"
    static let left = "←"
    static let right = "→"

    /// What one press of ⌥⌘↑ or ↓ moves line spacing by.
    static let lineStep = 0.1
    /// What one press of ⌥⌘→ or ← moves letter spacing by, as a share of
    /// the type size: 1%.
    static let letterStep = 0.01

    /// A key with Ctrl on Android and ⌘ on the iPhone, with Shift or not,
    /// and with Alt (⌥) or not: a lower-case letter, a digit, a mark as the
    /// key cap shows it, or an arrow (`up`, `down`, `left`, `right`).
    struct Key: Equatable {
        var key: String
        var shift: Bool
        var action: Command
        var alt = false
    }

    /// Every key, as Canva has them: B, I and U; Shift with X to strike
    /// through, K for capitals, L, C, R and J to align, 7 and 8 for numbered
    /// and bulleted lists, comma and full stop for smaller and larger.
    static let all: [Key] = [
        Key(key: "b", shift: false, action: .bold),
        Key(key: "i", shift: false, action: .italic),
        Key(key: "u", shift: false, action: .underline),
        Key(key: "x", shift: true, action: .strike),
        Key(key: "k", shift: true, action: .uppercase),
        Key(key: "l", shift: true, action: .alignLeft),
        Key(key: "c", shift: true, action: .alignCenter),
        Key(key: "r", shift: true, action: .alignRight),
        Key(key: "j", shift: true, action: .alignJustify),
        Key(key: "7", shift: true, action: .numberedList),
        Key(key: "8", shift: true, action: .bulletedList),
        Key(key: ",", shift: true, action: .smaller),
        Key(key: ".", shift: true, action: .larger),
        Key(key: "k", shift: false, action: .link),
        Key(key: down, shift: false, action: .lineTighter, alt: true),
        Key(key: up, shift: false, action: .lineLooser, alt: true),
        Key(key: left, shift: false, action: .letterTighter, alt: true),
        Key(key: right, shift: false, action: .letterLooser, alt: true),
        Key(key: "c", shift: false, action: .copyStyle, alt: true),
        Key(key: "v", shift: false, action: .pasteStyle, alt: true),
    ]

    /// Outside typing, the one key with nothing held: T adds a text box in
    /// the middle of the page.
    static let addText = "t"

    /// The keys typing shares with the editor, outside the ⌘ table: F5 and
    /// ⇧F5 end the typing, as Done does, and present from the beginning or
    /// from this page (PresentFrom.keys) — the Android twin's
    /// TextKeys.present.
    static var present: [PresentFrom.Shortcut] { PresentFrom.keys }

    /// What `key` (either case) does with Shift and Alt held or not; nil
    /// for a key that is none of these.
    static func action(for key: String, shift: Bool, alt: Bool = false) -> Command? {
        let lower = key.lowercased()
        return all.first { $0.key == lower && $0.shift == shift && $0.alt == alt }?.action
    }

    /// How a key is written in the ⌘ overlay's order: ⌥⇧⌘ and the key cap,
    /// "⇧⌘K", "⌥⌘↑".
    static func shown(_ key: Key) -> String {
        (key.alt ? "⌥" : "") + (key.shift ? "⇧" : "") + "⌘" + key.key.uppercased()
    }

    /// Line spacing one step looser (by 1) or tighter (by -1) than
    /// `lineHeight` (nil for the box's 1.25): `lineStep` a press, to two
    /// places, within TypeReadouts.lineHeightRange — the Android twin's
    /// TextBoxes.MIN_LINE to MAX_LINE.
    static func lineHeightStepped(_ lineHeight: Double?, by step: Int) -> Double {
        let next = (lineHeight ?? 1.25) + lineStep * Double(step)
        let range = TypeReadouts.lineHeightRange
        return min(max((next * 100 + 0.5).rounded(.down) / 100, range.lowerBound), range.upperBound)
    }

    /// Letter spacing one step looser (by 1) or tighter (by -1) than
    /// `spacing` (nil for none), `letterStep` of type `size` a press, within
    /// TypeReadouts.letterSpacingRange.
    static func letterSpacingStepped(_ spacing: Double?, size: Double, by step: Int) -> Double {
        let now = spacing ?? 0
        let range = TypeReadouts.letterSpacingRange(size: size, current: now)
        let next = now + letterStep * size * Double(step)
        return min(max((next * 10_000 + 0.5).rounded(.down) / 10_000, range.lowerBound), range.upperBound)
    }

    /// What VoiceOver says after a line spacing step: "Line spacing 1.4" —
    /// to at most two places, no trailing zeros.
    static func lineHeightSaid(_ lineHeight: Double) -> String {
        let hundredths = Int((lineHeight * 100 + 0.5).rounded(.down))
        var text = String(hundredths / 100) + "." + String(format: "%02d", hundredths % 100)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return tr("Line spacing %@", text)
    }

    /// What VoiceOver says after a letter spacing step: "Letter spacing
    /// 4%", in whole percent of type `size`, as its readout shows it.
    static func letterSpacingSaid(_ spacing: Double, size: Double) -> String {
        tr("Letter spacing %d%%", Int((spacing / max(size, 1) * 100 + 0.5).rounded(.down)))
    }

    /// The key's name in the ⌘ overlay and the keyboard help.
    static func keyName(_ action: Command) -> String {
        switch action {
        case .bold: return tr("Bold")
        case .italic: return tr("Italic")
        case .underline: return tr("Underline")
        case .strike: return tr("Strikethrough")
        case .uppercase: return tr("Uppercase")
        case .alignLeft: return tr("Align left")
        case .alignCenter: return tr("Align centre")
        case .alignRight: return tr("Align right")
        case .alignJustify: return tr("Justify")
        case .numberedList: return tr("Numbered list")
        case .bulletedList: return tr("Bulleted list")
        case .smaller: return tr("Smaller")
        case .larger: return tr("Larger")
        case .link: return tr("Add link")
        case .lineTighter: return tr("Decrease line spacing")
        case .lineLooser: return tr("Increase line spacing")
        case .letterTighter: return tr("Decrease letter spacing")
        case .letterLooser: return tr("Increase letter spacing")
        case .copyStyle: return tr("Copy style")
        case .pasteStyle: return tr("Paste style")
        }
    }

    /// The alignment an align key sets, as the box stores it; nil for the
    /// other keys.
    static func keyAlignment(_ action: Command) -> String? {
        switch action {
        case .alignLeft: return "left"
        case .alignCenter: return "center"
        case .alignRight: return "right"
        case .alignJustify: return "justify"
        default: return nil
        }
    }

    /// The list an list key sets on the lines, and takes off again when the
    /// first of them has it; nil for the other keys.
    static func keyList(_ action: Command) -> String? {
        switch action {
        case .numberedList: return "number"
        case .bulletedList: return "bullet"
        default: return nil
        }
    }
}

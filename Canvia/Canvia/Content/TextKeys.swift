// The hardware keyboard's formatting keys while words are typed in place:
// what Canva's are, as one table the Android twin's TextKeys shares, so the
// two phones answer the same keys with the same functions as the bar over
// the keyboard — the words chosen marked (RichText.toggling), the whole box
// set (TextSelection), the lines the choice covers listed (TextLists), the
// words chosen a step smaller or larger (Spans) — each as a step of its
// own between the words typed before and after.

import Foundation

enum TextKeys {

    /// What a key does.
    enum Command: CaseIterable, Equatable {
        case bold, italic, underline, strike, uppercase
        case alignLeft, alignCenter, alignRight, alignJustify
        case numberedList, bulletedList
        case smaller, larger
    }

    /// A key with Ctrl on Android and ⌘ on the iPhone, with Shift or not.
    struct Key: Equatable {
        var key: String
        var shift: Bool
        var action: Command
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
    ]

    /// Outside typing, the one key with nothing held: T adds a text box in
    /// the middle of the page.
    static let addText = "t"

    /// What `key` (either case) does with Shift held or not; nil for a key
    /// that is none of these.
    static func action(for key: String, shift: Bool) -> Command? {
        let lower = key.lowercased()
        return all.first { $0.key == lower && $0.shift == shift }?.action
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

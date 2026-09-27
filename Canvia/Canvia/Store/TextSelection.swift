// Type set on several text boxes at once, and the switches the text
// controls and the typing bar share: bold, italic, underline and capitals.
//
// A band's worth of captions, or a group of nothing but text, is styled in
// one step as one box is: every selected, unlocked text takes the change and
// is measured again. Where they differ the controls say "Mixed", and a
// switch turns its style on for all of them unless every one has it already,
// when it turns it off for all — so one tap never leaves them still mixed.

import Foundation

/// A style a text box has, or has not, as a whole.
enum TextToggle: CaseIterable {
    case bold, italic, underline, uppercase

    /// The box's own switch for a style the typing bar marks on words;
    /// strike has none, since no box is struck through as a whole.
    init?(_ mark: RichText.Mark) {
        switch mark {
        case .bold: self = .bold
        case .italic: self = .italic
        case .underline: self = .underline
        case .strike: return nil
        }
    }

    func isOn(_ el: Element) -> Bool {
        switch self {
        case .bold: return (el.fontWeight ?? 400) >= 700
        case .italic: return el.italic == true
        case .underline: return el.underline == true
        case .uppercase: return el.uppercase == true
        }
    }

    /// Bold turned on leaves a heavier weight as it is, and turned off is
    /// regular again; capitals turned off leave no key behind.
    func apply(_ on: Bool, to el: inout Element) {
        switch self {
        case .bold:
            if !on {
                el.fontWeight = 400
            } else if (el.fontWeight ?? 400) < 700 {
                el.fontWeight = 700
            }
        case .italic: el.italic = on
        case .underline: el.underline = on
        case .uppercase: el.uppercase = on ? true : nil
        }
    }
}

extension DesignStore {

    /// Everything selected, when there is more than one thing and every one
    /// is a text: several boxes, or a group of nothing but text. The text
    /// controls then set them together. nil otherwise — and for a single box,
    /// which has its own controls.
    var textSelection: [Element]? {
        let chosen = selectedElements
        guard chosen.count > 1, chosen.allSatisfy({ $0.type == .text }) else { return nil }
        return chosen
    }

    /// What every selected text reads for `value`, or nil when they differ:
    /// what the controls show, or "Mixed".
    func sharedText<T: Equatable>(_ value: (Element) -> T) -> T? {
        TypeReadouts.shared(selectedElements.filter { $0.type == .text }.map(value))
    }

    /// Bold, italic, underline or capitals on for every selected, unlocked
    /// text — or off for all of them when every one has it already. One
    /// step, each box measured again.
    func toggleText(_ toggle: TextToggle) {
        let texts = selectedElements.filter { $0.type == .text && !$0.locked }
        guard !texts.isEmpty else { return }
        let on = !texts.allSatisfy { toggle.isOn($0) }
        updateSelected { el in
            guard el.type == .text else { return }
            toggle.apply(on, to: &el)
        }
    }

    /// Every selected, unlocked text at one type size, in whole points from
    /// 6 to 500, each box measured again to fit. One step.
    func setFontSize(_ size: Double) {
        let size = TypeReadouts.wholeSize(size)
        updateSelected { el in
            guard el.type == .text else { return }
            el.fontSize = size
            el.h = FontLibrary.layoutHeight(for: el)
        }
    }
}

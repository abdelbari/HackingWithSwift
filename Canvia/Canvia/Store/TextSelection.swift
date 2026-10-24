// Type set on several text boxes at once, and the switches the text
// controls and the typing bar share: bold, italic, underline, strikethrough
// and capitals.
//
// A band's worth of captions, or a group of nothing but text, is styled in
// one step as one box is: every selected, unlocked text takes the change and
// is measured again. Where they differ the controls say "Mixed", and a
// switch turns its style on for all of them unless every one has it already,
// when it turns it off for all — so one tap never leaves them still mixed.

import Foundation
import UIKit

/// A style a text box has, or has not, as a whole.
enum TextToggle: CaseIterable {
    case bold, italic, underline, strike, uppercase

    /// The box's own switch for a style the typing bar marks on words.
    init?(_ mark: RichText.Mark) {
        switch mark {
        case .bold: self = .bold
        case .italic: self = .italic
        case .underline: self = .underline
        case .strike: self = .strike
        }
    }

    func isOn(_ el: Element) -> Bool {
        switch self {
        case .bold: return Self.isBold(el)
        case .italic: return FontLibrary.isItalic(el)
        case .underline: return el.underline == true
        case .strike: return Self.isStruck(el)
        case .uppercase: return el.uppercase == true
        }
    }

    /// Whether Strikethrough reads on for `el`: every letter of its words —
    /// spaces aside — is struck (RichText.selectionHas over the whole box).
    /// There is no box-wide strike key; the words carry it, as the typing
    /// bar strikes them. The Android twin's TextSelection.isStruck.
    static func isStruck(_ el: Element) -> Bool {
        let text = el.text ?? ""
        return RichText.selectionHas(.strike, in: text, selection: NSRange(location: 0, length: (text as NSString).length))
    }

    /// Whether Bold reads on for `el`: the weight it is drawn at
    /// (FontLibrary.resolveWeight) is 700 or more, so Bold and the Weight
    /// row never disagree — 600 in Modern Sans (300, 400, 500, 700) is
    /// drawn Bold and reads on, 600 in Roboto, which has a Semibold, reads
    /// off. A font of your own of one face, or one with no weight of 700 or
    /// more (Anton), is one face drawn at its own weight whatever is asked,
    /// so its stored weight is read, and Bold still turns on and off. A
    /// family of your own with a Bold reads as a library family does. As on
    /// the Android twin.
    static func isBold(_ el: Element) -> Bool {
        let weight = FontLibrary.weight(of: el)
        let oneFace = !TypeReadouts.isWeighable(el)
            || !FontLibrary.weights(el.fontFamily).contains { $0 >= 700 }
        return (oneFace ? weight : FontLibrary.resolveWeight(el.fontFamily, weight)) >= 700
    }

    /// Bold turned on sets 700 where it reads off (isBold) and leaves a
    /// weight already drawn bold (600 in Modern Sans, 800, 900) as it is,
    /// and turned off is regular again; capitals turned off leave no key
    /// behind.
    func apply(_ on: Bool, to el: inout Element) {
        switch self {
        case .bold:
            if !on {
                el.fontWeight = 400
            } else if !Self.isBold(el) {
                el.fontWeight = 700
            }
        case .italic: el.italic = on
        case .underline: el.underline = on
        case .strike: Self.strike(on, &el)
        case .uppercase: el.uppercase = on ? true : nil
        }
    }

    /// Every word of `el` struck through, or none: the whole box's words
    /// wrapped in, or taken out of, strike markers (RichText.toggling over
    /// all of it) — what the typing bar's Strikethrough does with the whole
    /// box chosen — its spans and paragraphs moved with the words. A box
    /// already as asked is left as it is.
    private static func strike(_ on: Bool, _ el: inout Element) {
        guard isStruck(el) != on else { return }
        let text = el.text ?? ""
        let whole = NSRange(location: 0, length: (text as NSString).length)
        guard let edit = RichText.toggling(.strike, in: text, selection: whole), edit.text != text else { return }
        el.setText(edit.text)
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

    /// What every selected text a change will reach reads for `value` — the
    /// unlocked ones, or all of them when every one is locked — or nil when
    /// they differ: what the controls show, or "Mixed". As on the Android
    /// twin. A shape's words count as a text (ShapeText.carriesWords).
    func sharedText<T: Equatable>(_ value: (Element) -> T) -> T? {
        TypeReadouts.shared(textsRead.map(value))
    }

    /// The selected texts the controls read, a shape's words among them:
    /// the unlocked ones, or all of them when every one is locked.
    var textsRead: [Element] {
        let texts = selectedElements.filter(ShapeText.carriesWords)
        let reached = texts.filter { !$0.locked }
        return reached.isEmpty ? texts : reached
    }

    /// Bold, italic, underline, strikethrough or capitals on for every
    /// selected, unlocked text, a shape's words among them — or off for all of them when every
    /// one has it already. One step, each box measured again.
    func toggleText(_ toggle: TextToggle) {
        let texts = selectedElements.filter { ShapeText.carriesWords($0) && !$0.locked }
        guard !texts.isEmpty else { return }
        let on = !texts.allSatisfy { toggle.isOn($0) }
        updateSelected { el in
            guard ShapeText.carriesWords(el) else { return }
            toggle.apply(on, to: &el)
        }
    }

    /// ⌥⌘ and an arrow, ⌥⌘C or ⌥⌘V while typing (TextKeys): the box's line
    /// spacing a tenth looser or tighter, its letter spacing a hundredth of
    /// its type size, or its look copied or pasted as Copy style and Paste
    /// style do — each a step of its own between the words typed before and
    /// after. A spacing step is said to VoiceOver, "Line spacing 1.4", and
    /// returned; nil for the other keys, or when nothing changed.
    @discardableResult
    func typingBoxKey(_ action: TextKeys.Command) -> String? {
        switch action {
        case .copyStyle:
            copyStyle()
            return nil
        case .pasteStyle:
            styleWhileTyping { pasteStyle() }
            return nil
        case .lineTighter, .lineLooser, .letterTighter, .letterLooser:
            guard let el = singleSelection, ShapeText.carriesWords(el), !el.locked else { return nil }
            var said: String?
            styleWhileTyping {
                updateSelected { e in
                    guard ShapeText.carriesWords(e) else { return }
                    said = Self.steppedSpacing(&e, action)
                }
            }
            if let said { UIAccessibility.post(notification: .announcement, argument: said) }
            return said
        default:
            return nil
        }
    }

    /// `el` a spacing step tighter or looser (TextKeys), and what that says.
    static func steppedSpacing(_ el: inout Element, _ action: TextKeys.Command) -> String? {
        switch action {
        case .lineTighter, .lineLooser:
            let next = TextKeys.lineHeightStepped(el.lineHeight, by: action == .lineLooser ? 1 : -1)
            el.lineHeight = next
            return TextKeys.lineHeightSaid(next)
        case .letterTighter, .letterLooser:
            let size = el.fontSize ?? 42
            let next = TextKeys.letterSpacingStepped(el.letterSpacing, size: size, by: action == .letterLooser ? 1 : -1)
            el.letterSpacing = next
            return TextKeys.letterSpacingSaid(next, size: size)
        default:
            return nil
        }
    }

    /// A style put on words from the bar over the keyboard while they are
    /// typed: a step of its own, between the words typed before it and
    /// after, so each press is one Undo, as on the Android twin.
    func styleWhileTyping(_ change: () -> Void) {
        commit()
        change()
        commit()
    }

    /// Every selected, unlocked text — a shape's words among them — at one
    /// weight, the Weight row's chip, each box measured again. One step.
    /// Bold keeps its own rule (TextToggle).
    func setFontWeight(_ weight: Int) {
        updateSelected { el in
            guard ShapeText.carriesWords(el) else { return }
            el.fontWeight = weight
            ShapeText.fitWords(&el)
        }
    }

    /// Every selected, unlocked text at one type size, in whole points from
    /// 1 to 800, each box measured again to fit — a shape grown for its
    /// words when they need it. One step.
    func setFontSize(_ size: Double) {
        let size = TypeReadouts.wholeSize(size)
        updateSelected { el in
            guard ShapeText.carriesWords(el) else { return }
            el.fontSize = size
            ShapeText.fitWords(&el)
        }
    }
}

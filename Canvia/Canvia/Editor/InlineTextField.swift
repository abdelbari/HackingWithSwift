// The field for typing in place on the canvas.
//
// A SwiftUI TextField takes a font, a colour and an alignment and nothing
// more, so the words jumped the moment typing began: fitted type went back
// to its stored size, tracking and line pitch vanished, justified text
// centred itself. A UITextView takes the very attributes the canvas draws
// with (FontLibrary.attributes), at the size the canvas draws — the Android
// twin's inline field does the same from its own text layout — so the
// words stay exactly where they were while they are typed.
//
// The bar over the keyboard styles the words chosen as they are typed:
// Bold, Italic, Underline and Strikethrough put the rich-text markers round
// them, or take them off (RichText.toggling). With nothing chosen, the
// first three style the whole box, as its own controls do. A box set in
// capitals is still typed as its words are kept: the capitals are drawn.

import SwiftUI
import UIKit

struct InlineTextField: UIViewRepresentable {
    let element: Element
    /// The words as typed, on every change.
    var onChange: (String) -> Void
    /// Typing is over: Done on the keyboard's bar, or Escape.
    var onDone: () -> Void
    /// Bold, italic or underline for the whole box: its bar's button with
    /// nothing chosen.
    var onToggle: (TextToggle) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> InlineTextView {
        let view = InlineTextView()
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.tintColor = UIColor(Theme.accent)
        view.delegate = context.coordinator
        let coordinator = context.coordinator
        view.onEscape = { [weak coordinator] in coordinator?.parent.onDone() }
        view.inputAccessoryView = context.coordinator.typingBar()
        context.coordinator.view = view
        context.coordinator.apply(element, to: view)
        // The caret at the end of the words, as it opens on the Android twin.
        let end = view.endOfDocument
        view.selectedTextRange = view.textRange(from: end, to: end)
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: InlineTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(element, to: view)
    }

    /// As wide as the box, as tall as the words need.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: InlineTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? CGFloat(element.w)
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, 1))
    }

    /// The element as the canvas draws it: fitted type at the size it fits.
    static func drawn(_ el: Element) -> Element {
        var out = el
        out.fontSize = FontLibrary.effectiveFontSize(for: el)
        out.fitText = nil
        return out
    }

    /// What the field's look depends on; when it changes, the words are set
    /// again in the new look.
    static func signature(_ el: Element) -> String {
        [el.fontFamily ?? "", "\(el.fontSize ?? 42)", "\(el.fontWeight ?? 400)", "\(el.italic == true)",
         "\(el.underline == true)", el.align ?? "", "\(el.lineHeight ?? 1.25)", "\(el.letterSpacing ?? 0)",
         el.color ?? "", "\(el.paragraphSpacing ?? 0)", "\(el.indent ?? 0)", el.listStyle ?? ""]
            .joined(separator: "|")
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: InlineTextField
        weak var view: UITextView?
        private var look = ""
        /// The bar's style buttons, in RichText.Mark's order.
        private var styleItems: [UIBarButtonItem] = []

        init(_ parent: InlineTextField) {
            self.parent = parent
        }

        /// Sets the words and their look, keeping the caret — but never in
        /// the middle of a composition, which resetting would break.
        func apply(_ el: Element, to view: UITextView) {
            let drawn = InlineTextField.drawn(el)
            let attrs = FontLibrary.attributes(for: drawn)
            view.typingAttributes = attrs
            guard view.markedTextRange == nil else { return }
            let words = el.text ?? ""
            let signature = InlineTextField.signature(drawn)
            // The bar's buttons follow the box's own bold and the rest.
            defer { refreshStyles(view) }
            guard view.text != words || signature != look else { return }
            look = signature
            let kept = view.selectedRange
            view.attributedText = NSAttributedString(string: words, attributes: attrs)
            let length = (words as NSString).length
            let start = min(kept.location, length)
            view.selectedRange = NSRange(location: start, length: min(kept.length, length - start))
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.onChange(textView.text ?? "")
            refreshStyles(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            refreshStyles(textView)
        }

        /// A bar over the keyboard: Bold, Italic, Underline and
        /// Strikethrough for the words chosen, and Done, the plainest way out.
        func typingBar() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            styleItems = RichText.Mark.allCases.enumerated().map { entry -> UIBarButtonItem in
                let face = InlineTextField.face(of: entry.element)
                let item = UIBarButtonItem(image: UIImage(systemName: face.symbol), style: .plain,
                                           target: self, action: #selector(style(_:)))
                item.tag = entry.offset
                item.accessibilityLabel = face.name
                return item
            }
            let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(finish))
            bar.items = styleItems + [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
            bar.sizeToFit()
            return bar
        }

        @objc private func finish() {
            parent.onDone()
        }

        /// The words chosen marked in the style, or unmarked when they all
        /// have it, and the same words left chosen. With nothing chosen,
        /// bold, italic and underline are the whole box's; strike, which a
        /// box has no switch for, marks all of its words.
        @objc private func style(_ sender: UIBarButtonItem) {
            guard let view, view.markedTextRange == nil,
                  RichText.Mark.allCases.indices.contains(sender.tag) else { return }
            let mark = RichText.Mark.allCases[sender.tag]
            let words = view.text ?? ""
            let chosen = view.selectedRange
            guard chosen.location != NSNotFound else { return }
            if chosen.length == 0, let toggle = TextToggle(mark) {
                parent.onToggle(toggle)
                return
            }
            let range = chosen.length > 0 ? chosen : NSRange(location: 0, length: (words as NSString).length)
            guard let result = RichText.toggling(mark, in: words, selection: range) else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            // Replaced as an edit, so the text's own Undo (⌘Z, a shake) takes
            // the markers back; the caret goes before the letter it was before.
            if let all = view.textRange(from: view.beginningOfDocument, to: view.endOfDocument) {
                view.replace(all, withText: result.text)
            }
            view.selectedRange = chosen.length > 0
                ? result.selection
                : NSRange(location: RichText.caret(at: chosen.location, from: words, to: result.text), length: 0)
            parent.onChange(result.text)
            refreshStyles(view)
        }

        /// Each style button lit when the words chosen all have its style —
        /// or, with nothing chosen, when the whole box has it.
        func refreshStyles(_ view: UITextView) {
            guard !styleItems.isEmpty else { return }
            let words = view.text ?? ""
            let chosen = view.selectedRange
            let all = NSRange(location: 0, length: (words as NSString).length)
            for (item, mark) in zip(styleItems, RichText.Mark.allCases) {
                let on: Bool
                if chosen.length > 0 {
                    on = RichText.selectionHas(mark, in: words, selection: chosen)
                } else if let toggle = TextToggle(mark) {
                    on = toggle.isOn(parent.element)
                } else {
                    on = RichText.selectionHas(mark, in: words, selection: all)
                }
                item.tintColor = on ? UIColor(Theme.accent) : .label
                item.accessibilityTraits = on ? [.button, .selected] : .button
            }
        }
    }

    /// The bar's face for each style.
    static func face(of mark: RichText.Mark) -> (symbol: String, name: String) {
        switch mark {
        case .bold: return ("bold", "Bold")
        case .italic: return ("italic", "Italic")
        case .underline: return ("underline", "Underline")
        case .strike: return ("strikethrough", "Strikethrough")
        }
    }
}

/// A text view that hands Escape on a hardware keyboard back as Done.
final class InlineTextView: UITextView {
    var onEscape: () -> Void = {}

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.keyCode == .keyboardEscape }) {
            onEscape()
            return
        }
        super.pressesBegan(presses, with: event)
    }
}

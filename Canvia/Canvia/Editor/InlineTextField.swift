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
//
// Beside them a colour well and A- and A+ colour the words chosen, or set
// them a step smaller or larger (see Spans) — only with words chosen — and
// the field shows the words in those colours and sizes as they are typed.

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
    /// Runs a style the bar puts on the words as a step of its own.
    var onStyled: (() -> Void) -> Void = { $0() }
    /// The colour well, for the words chosen: a range of the words as they
    /// read.
    var onWordColour: (NSRange) -> Void = { _ in }
    /// A- or A+ for the words chosen, and what their size is multiplied by.
    var onWordScale: (NSRange, Double) -> Void = { _, _ in }

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
        /// The colour well, A- and A+, for the words chosen.
        private var wordItems: [UIBarButtonItem] = []
        /// The colours and sizes the words are shown in now, and the words
        /// they were put on.
        private var painted: [TextSpan] = []
        private var paintedWords = ""

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
            let spans = InlineTextField.shownSpans(el)
            // The bar's buttons follow the box's own bold and the rest.
            defer { refreshStyles(view) }
            // Painted again after every change of the words, too: a letter
            // typed just after a coloured word picks up its colour in the
            // field, and is put back as the canvas will draw it.
            let repaint = spans != painted || (!spans.isEmpty && words != paintedWords)
            guard view.text != words || signature != look || repaint else { return }
            if view.text != words || signature != look {
                look = signature
                let kept = view.selectedRange
                view.attributedText = NSAttributedString(string: words, attributes: attrs)
                let length = (words as NSString).length
                let start = min(kept.location, length)
                view.selectedRange = NSRange(location: start, length: min(kept.length, length - start))
            }
            guard !spans.isEmpty || !painted.isEmpty else { return }
            painted = spans
            paintedWords = words
            InlineTextField.paint(view.textStorage, words: words, spans: spans, attrs: attrs)
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.onChange(textView.text ?? "")
            refreshStyles(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            refreshStyles(textView)
        }

        /// A bar over the keyboard: Bold, Italic, Underline and
        /// Strikethrough for the words chosen, their colour and A- and A+,
        /// and Done, the plainest way out.
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
            let well = UIBarButtonItem(image: UIImage(systemName: "circle.fill"), style: .plain,
                                       target: self, action: #selector(colourWords))
            well.accessibilityLabel = "Colour of the selected words"
            let smaller = UIBarButtonItem(title: "A-", style: .plain, target: self, action: #selector(sizeWords(_:)))
            smaller.tag = 0
            smaller.accessibilityLabel = "Smaller"
            let larger = UIBarButtonItem(title: "A+", style: .plain, target: self, action: #selector(sizeWords(_:)))
            larger.tag = 1
            larger.accessibilityLabel = "Larger"
            wordItems = [well, smaller, larger]
            let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(finish))
            bar.items = styleItems + wordItems
                + [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
            bar.sizeToFit()
            return bar
        }

        @objc private func finish() {
            parent.onDone()
        }

        /// The words chosen, as a range of the words as they read; nil with
        /// none chosen.
        private func chosenWords(_ view: UITextView) -> NSRange? {
            guard view.markedTextRange == nil else { return nil }
            return RichText.plainRange(of: view.selectedRange, in: view.text ?? "")
        }

        /// The colour sheet, for the words chosen.
        @objc private func colourWords() {
            guard let view, let range = chosenWords(view) else { return }
            parent.onWordColour(range)
        }

        /// A- or A+: the words chosen a step smaller or larger, as a step of
        /// their own; the same words stay chosen.
        @objc private func sizeWords(_ sender: UIBarButtonItem) {
            guard let view, let range = chosenWords(view) else { return }
            parent.onWordScale(range, sender.tag == 0 ? Spans.smaller : Spans.larger)
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
            // In the design it is a step of its own, as each press is.
            parent.onStyled {
                if let all = view.textRange(from: view.beginningOfDocument, to: view.endOfDocument) {
                    view.replace(all, withText: result.text)
                }
                view.selectedRange = chosen.length > 0
                    ? result.selection
                    : NSRange(location: RichText.caret(at: chosen.location, from: words, to: result.text), length: 0)
                parent.onChange(result.text)
            }
            refreshStyles(view)
        }

        /// Each style button lit when the words chosen all have its style —
        /// or, with nothing chosen, when the whole box has it.
        func refreshStyles(_ view: UITextView) {
            guard !styleItems.isEmpty else { return }
            let words = view.text ?? ""
            let chosen = view.selectedRange
            let all = NSRange(location: 0, length: (words as NSString).length)
            // The colour well and the sizes, only with words chosen; the well
            // in the colour they share.
            let picked = chosenWords(view)
            for item in wordItems { item.isEnabled = picked != nil }
            if let well = wordItems.first {
                let el = parent.element
                var hex: String?
                if let picked {
                    let shared = Spans.colour(of: el.liveSpans, in: picked)
                    if shared.shared { hex = shared.color ?? el.color ?? "#1f2430" }
                }
                well.tintColor = hex.map { UIColor(hex: $0) } ?? .label
            }
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

    /// The colours and sizes the field shows the words in: the element's,
    /// less the colours while its letters are a gradient, as on the canvas.
    static func shownSpans(_ el: Element) -> [TextSpan] {
        let spans = el.liveSpans
        guard el.textFill?.kind == "gradient" else { return spans }
        return Spans.normalised(spans.map { TextSpan(start: $0.start, end: $0.end, scale: $0.scale) })
    }

    /// The typed words, markers and all, in `attrs`, with the colours and
    /// sizes of `spans` — counted in the words as they read — on the letters
    /// they belong to.
    static func paint(_ storage: NSTextStorage, words: String, spans: [TextSpan],
                      attrs: [NSAttributedString.Key: Any]) {
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(attrs, range: whole)
        if !spans.isEmpty, storage.length == (words as NSString).length {
            let units = RichText.typedUnits(words)
            let font = attrs[.font] as? UIFont
            for span in spans {
                for range in RichText.typedRanges(of: span.range, units: units) {
                    if let color = span.color {
                        storage.addAttribute(.foregroundColor, value: UIColor(hex: color), range: range)
                    }
                    if let scale = span.scale, let font {
                        storage.addAttribute(.font, value: font.withSize(font.pointSize * scale), range: range)
                    }
                }
            }
        }
        storage.endEditing()
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

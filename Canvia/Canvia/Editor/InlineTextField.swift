// The field for typing in place on the canvas.
//
// A SwiftUI TextField takes a font, a colour and an alignment and nothing
// more, so the words jumped the moment typing began: fitted type went back
// to its stored size, tracking and line pitch vanished, justified text
// centred itself. A UITextView takes the very attributes the canvas draws
// with (FontLibrary.attributes), at the size the canvas draws — the Android
// twin's inline field does the same from its own text layout — so the
// words stay exactly where they were while they are typed.

import SwiftUI
import UIKit

struct InlineTextField: UIViewRepresentable {
    let element: Element
    /// The words as typed, on every change.
    var onChange: (String) -> Void
    /// Typing is over: Done on the keyboard's bar, or Escape.
    var onDone: () -> Void

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
        view.inputAccessoryView = context.coordinator.doneBar()
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
        private var look = ""

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
        }

        /// A bar over the keyboard with Done, the plainest way out.
        func doneBar() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            let item = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(finish))
            bar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), item]
            bar.sizeToFit()
            return bar
        }

        @objc private func finish() {
            parent.onDone()
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

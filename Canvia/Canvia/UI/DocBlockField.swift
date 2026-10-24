// A Doc block's words typed as they read, as the canvas's own field types
// a text box's: the RichText markers kept in what is stored but drawn as
// nothing (InlineTextField.paint), and what is typed put in as the words
// read (RichText.typing) — bold words in bold, never a star in sight. The
// block's colours, highlights and links (Spans) are shown on its words.
//
// Over the keyboard while a block has the caret, the format bar: Bold,
// Italic, Underline and Strikethrough mark the words chosen, or wait for
// what is typed next with none chosen (RichText.toggling, Pending); Link,
// Colour and Highlight ask the editor for the words chosen (Spans `link`,
// `color`, `highlight`); Align steps the block left, centre, right and
// justified (`align`). ⌘B, ⌘I, ⌘U, ⇧⌘X, ⌘K and the align keys do the
// same on a hardware keyboard (TextKeys). Each is a step of its own.

import SwiftUI
import UIKit

struct DocBlockField: UIViewRepresentable {
    let block: DocBlock
    /// The block's type face, at its size.
    let font: UIFont
    /// The block's name, for VoiceOver.
    let label: String
    let heading: Bool
    /// Which block has the caret; this one takes it when it is asked to.
    @Binding var focus: String?
    /// The words as stored, on every change.
    var onChange: (String) -> Void
    /// A style the bar put on the words, as a step of its own: the words.
    var onStyled: (String) -> Void
    /// Colour, Highlight and Link for the words chosen, as they read.
    var onColour: (NSRange) -> Void
    var onHighlight: (NSRange) -> Void
    var onLink: (NSRange) -> Void
    /// Align and the align keys: the block's next alignment.
    var onAlign: (String) -> Void
    /// The keyboard's Undo and Redo.
    var onUndo: () -> Void
    var onRedo: () -> Void

    func makeCoordinator() -> BlockCoordinator { BlockCoordinator(self) }

    func makeUIView(context: Context) -> InlineTextView {
        let view = InlineTextView()
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.tintColor = UIColor(Theme.accent)
        view.delegate = context.coordinator
        view.accessibilityLabel = label
        if heading { view.accessibilityTraits.insert(.header) }
        let coordinator = context.coordinator
        view.onKey = { [weak coordinator] action in coordinator?.key(action) }
        view.onEscape = { [weak view] in _ = view?.resignFirstResponder() }
        view.typingUndo.onUndo = { [weak coordinator] in coordinator?.parent.onUndo() }
        view.typingUndo.onRedo = { [weak coordinator] in coordinator?.parent.onRedo() }
        view.typingUndo.canUndoing = { true }
        view.inputAccessoryView = coordinator.formatBar()
        coordinator.view = view
        coordinator.apply(to: view)
        return view
    }

    func updateUIView(_ view: InlineTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(to: view)
        if focus == block.id, !view.isFirstResponder {
            DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        }
    }

    /// As wide as the column, as tall as the words need.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: InlineTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, font.lineHeight))
    }

    /// The words' look: the block's face, the label colour, its alignment.
    var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        switch block.align {
        case "center": paragraph.alignment = .center
        case "right": paragraph.alignment = .right
        case "justify": paragraph.alignment = .justified
        default: paragraph.alignment = .left
        }
        return [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
    }

    /// The face a **bold** or *italic* run is shown in: the block's own,
    /// bolder or slanted.
    var runFont: (_ bold: Bool, _ italic: Bool) -> UIFont? {
        let base = font
        return { bold, italic in
            var traits = base.fontDescriptor.symbolicTraits
            if bold { traits.insert(.traitBold) }
            if italic { traits.insert(.traitItalic) }
            guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
            return UIFont(descriptor: descriptor, size: base.pointSize)
        }
    }

    final class BlockCoordinator: NSObject, UITextViewDelegate {
        var parent: DocBlockField
        weak var view: UITextView?
        /// What is drawn now: the words, their spans and their look.
        private var shown: (words: String, spans: [TextSpan], align: String?)?
        private var applying = false
        private var editing = false
        private var lastSelection: NSRange?
        /// A style waiting for what is typed next, and the caret it waits at.
        private var pending: RichText.Pending?
        private var pendingCaret: Int?
        /// The bar's Bold, Italic, Underline and Strikethrough, and Align.
        private var styleItems: [UIBarButtonItem] = []
        private var alignItem: UIBarButtonItem?

        init(_ parent: DocBlockField) {
            self.parent = parent
        }

        /// The block's words and look drawn, the caret kept — never in the
        /// middle of a composition.
        func apply(to view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let words = parent.block.text
            let spans = Docs.spansOf(parent.block)
            if let shown, shown.words == words, shown.spans == spans, shown.align == parent.block.align,
               view.text == words { return }
            let kept = view.selectedRange
            applying = true
            if view.text != words {
                view.text = words
                pending = nil
                pendingCaret = nil
            }
            paint(view, words: words, spans: spans)
            let length = (words as NSString).length
            let start = min(kept.location, length)
            view.selectedRange = NSRange(location: start, length: min(kept.length, length - start))
            applying = false
            refreshBar(view)
        }

        private func paint(_ view: UITextView, words: String, spans: [TextSpan]) {
            let attrs = parent.attributes
            InlineTextField.paint(view.textStorage, words: words, spans: spans, attrs: attrs, runFont: parent.runFont)
            view.typingAttributes = attrs
            shown = (words, spans, parent.block.align)
        }

        // MARK: typing

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard textView.markedTextRange == nil else {
                editing = true
                return true
            }
            let words = textView.text ?? ""
            let waiting = range.length == 0 && pendingCaret == range.location ? pending : nil
            let typed = RichText.typing(text, over: range, in: words, pending: waiting)
            let plainly = (words as NSString).replacingCharacters(in: range, with: text)
            if typed.text == plainly, typed.pending == nil,
               typed.caret == range.location + (text as NSString).length {
                editing = true
                return true
            }
            applying = true
            textView.textStorage.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage.length),
                                                   with: typed.text)
            textView.selectedRange = NSRange(location: typed.caret, length: 0)
            applying = false
            changed(textView)
            pending = typed.pending
            pendingCaret = typed.pending == nil ? nil : typed.caret
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            editing = false
            guard !applying else { return }
            changed(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if !applying, !editing, textView.markedTextRange == nil {
                let chosen = textView.selectedRange
                if chosen.location != NSNotFound {
                    let kept = RichText.snapped(chosen, in: textView.text ?? "", was: lastSelection)
                    if kept != chosen {
                        applying = true
                        textView.selectedRange = kept
                        applying = false
                    }
                    lastSelection = kept
                    if kept.length > 0 || kept.location != pendingCaret {
                        pending = nil
                        pendingCaret = nil
                    }
                }
            }
            refreshBar(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if parent.focus != parent.block.id { parent.focus = parent.block.id }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focus == parent.block.id { parent.focus = nil }
        }

        /// The words changed: shown as they read, their spans moved along,
        /// and handed over.
        private func changed(_ view: UITextView) {
            let words = view.text ?? ""
            pending = nil
            pendingCaret = nil
            if view.markedTextRange == nil {
                let old = parent.block.text
                let spans = Spans.remap(RichText.strip(old), RichText.strip(words), Docs.spansOf(parent.block))
                paint(view, words: words, spans: spans)
            }
            lastSelection = view.selectedRange
            parent.onChange(words)
            refreshBar(view)
        }

        // MARK: the format bar

        /// The bar in a strip that scrolls sideways on a narrow phone, Done
        /// always in reach at its end, as the canvas's typing bar has it.
        func formatBar() -> UIView {
            let accessory = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            accessory.autoresizingMask = .flexibleWidth
            let backing = UIToolbar(frame: accessory.bounds)
            backing.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            accessory.addSubview(backing)
            let tools = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            tools.items = barItems()
            tools.frame.size.width = CGFloat((tools.items ?? []).count) * 44 + 16
            let strip = UIScrollView()
            strip.showsHorizontalScrollIndicator = false
            strip.addSubview(tools)
            strip.contentSize = tools.frame.size
            let ending = UIToolbar()
            ending.items = [UIBarButtonItem(title: tr("Done"), style: .done, target: self, action: #selector(finish))]
            for bar in [tools, ending] {
                bar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
                bar.setShadowImage(UIImage(), forToolbarPosition: .any)
            }
            for part in [strip, ending] as [UIView] {
                part.translatesAutoresizingMaskIntoConstraints = false
                accessory.addSubview(part)
            }
            NSLayoutConstraint.activate([
                strip.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
                strip.topAnchor.constraint(equalTo: accessory.topAnchor),
                strip.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
                strip.trailingAnchor.constraint(equalTo: ending.leadingAnchor),
                ending.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
                ending.topAnchor.constraint(equalTo: accessory.topAnchor),
                ending.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
                ending.widthAnchor.constraint(equalToConstant: 76),
            ])
            return accessory
        }

        /// B, I, U, S, then Link, Colour, Highlight and Align.
        private func barItems() -> [UIBarButtonItem] {
            styleItems = RichText.Mark.allCases.enumerated().map { entry -> UIBarButtonItem in
                let face = InlineTextField.face(of: entry.element)
                let item = UIBarButtonItem(image: UIImage(systemName: face.symbol), style: .plain,
                                           target: self, action: #selector(styleItem(_:)))
                item.tag = entry.offset
                item.accessibilityLabel = face.name
                return item
            }
            let link = item("link", tr("Link"), #selector(linkWords))
            let colour = item("paintpalette", tr("Text colour"), #selector(colourWords))
            let marker = item("highlighter", tr("Highlight"), #selector(highlightWords))
            let align = item(Self.alignSymbol(nil), tr("Align"), #selector(alignBlock))
            alignItem = align
            return styleItems + [link, colour, marker, align]
        }

        private func item(_ symbol: String, _ name: String, _ action: Selector) -> UIBarButtonItem {
            let item = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: action)
            item.accessibilityLabel = name
            return item
        }

        /// The symbol Align shows for an alignment.
        static func alignSymbol(_ align: String?) -> String {
            switch align {
            case "center": return "text.aligncenter"
            case "right": return "text.alignright"
            case "justify": return "text.justify"
            default: return "text.alignleft"
            }
        }

        /// What Align says the block is: "Left", "Centre"…
        static func alignName(_ align: String?) -> String {
            switch align {
            case "center": return tr("Centre")
            case "right": return tr("Right")
            case "justify": return tr("Justify")
            default: return tr("Left")
            }
        }

        @objc private func finish() {
            _ = view?.resignFirstResponder()
        }

        @objc private func styleItem(_ sender: UIBarButtonItem) {
            guard RichText.Mark.allCases.indices.contains(sender.tag) else { return }
            style(RichText.Mark.allCases[sender.tag])
        }

        /// The words chosen marked in the style, or unmarked when they all
        /// have it, the same words left chosen, as a step of its own; with
        /// none chosen, the style waits for what is typed next.
        private func style(_ mark: RichText.Mark) {
            guard let view, view.markedTextRange == nil else { return }
            let words = view.text ?? ""
            let chosen = view.selectedRange
            guard chosen.location != NSNotFound else { return }
            guard chosen.length > 0 else {
                var waiting = caretStyle(view)
                mark.turn(!mark.isOn(waiting), in: &waiting)
                pending = RichText.Pending(style: waiting, from: RichText.plainCaret(chosen.location, in: words))
                pendingCaret = chosen.location
                refreshBar(view)
                return
            }
            guard let result = RichText.toggling(mark, in: words, selection: chosen) else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            applying = true
            view.textStorage.replaceCharacters(in: NSRange(location: 0, length: view.textStorage.length), with: result.text)
            paint(view, words: result.text, spans: Docs.spansOf(parent.block))
            view.selectedRange = result.selection
            applying = false
            lastSelection = result.selection
            parent.onStyled(result.text)
            refreshBar(view)
        }

        /// The words chosen, as a range of the words as they read; nil with
        /// none.
        private func chosenWords() -> NSRange? {
            guard let view, view.markedTextRange == nil else { return nil }
            return RichText.plainRange(of: view.selectedRange, in: view.text ?? "")
        }

        @objc private func linkWords() {
            if let range = chosenWords() { parent.onLink(range) }
        }

        @objc private func colourWords() {
            if let range = chosenWords() { parent.onColour(range) }
        }

        @objc private func highlightWords() {
            if let range = chosenWords() { parent.onHighlight(range) }
        }

        /// Align: left, centre, right, justified, and round again.
        @objc private func alignBlock() {
            let aligns = Docs.aligns
            let now = aligns.firstIndex(of: parent.block.align ?? Docs.left) ?? 0
            parent.onAlign(aligns[(now + 1) % aligns.count])
        }

        /// A formatting key (TextKeys) inside a block: the styles, Link and
        /// the alignments; the rest are the canvas's.
        func key(_ action: TextKeys.Command) {
            switch action {
            case .bold: style(.bold)
            case .italic: style(.italic)
            case .underline: style(.underline)
            case .strike: style(.strike)
            case .link: linkWords()
            case .alignLeft, .alignCenter, .alignRight, .alignJustify:
                if let align = TextKeys.keyAlignment(action) { parent.onAlign(align) }
            default: break
            }
        }

        /// The style what is typed at the caret takes.
        private func caretStyle(_ view: UITextView) -> RichText.Style {
            let at = view.selectedRange.location
            if let pending, pendingCaret == at { return pending.style }
            let words = view.text ?? ""
            return RichText.styleAt(max(RichText.plainCaret(at, in: words) - 1, 0), in: words)
        }

        /// Each style lit when the words chosen all have it — or, with none
        /// chosen, when what is typed next will; Link, Colour and Highlight
        /// only with words chosen; Align showing the block's.
        private func refreshBar(_ view: UITextView) {
            let words = view.text ?? ""
            let chosen = view.selectedRange
            let atCaret = chosen.length == 0 ? caretStyle(view) : RichText.Style()
            for (item, mark) in zip(styleItems, RichText.Mark.allCases) {
                let on = chosen.length > 0 ? RichText.selectionHas(mark, in: words, selection: chosen) : mark.isOn(atCaret)
                item.tintColor = on ? UIColor(Theme.accent) : .label
                item.accessibilityTraits = on ? [.button, .selected] : .button
            }
            alignItem?.image = UIImage(systemName: Self.alignSymbol(parent.block.align))
            alignItem?.accessibilityValue = Self.alignName(parent.block.align)
        }
    }
}

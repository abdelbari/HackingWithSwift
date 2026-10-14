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
// The words show as they read, as Canva edits text in place: bold, italic,
// underlined and struck words in their styles, and no marker ever seen. The
// markers stay in what is stored — the words as typed, which the field
// holds — but are drawn as nothing, a hundredth of a point and clear, their
// width taken back (paint). The caret and any choice keep off them
// (RichText.snapped), and what is typed goes in as the words read
// (RichText.typing): at the end of a styled word inside its markers, so the
// style carries on; a backspace just after hidden markers takes the letter
// before them. The Android twin's field maps its offsets by the same rules.
//
// The bar over the keyboard styles the words chosen as they are typed:
// Bold, Italic, Underline and Strikethrough put the rich-text markers round
// them, or take them off (RichText.toggling). With nothing chosen, the style
// waits for what is typed next (RichText.Pending), as in Canva. A box set in
// capitals is still typed as its words are kept: the capitals are drawn.
//
// Beside them a colour well and A- and A+ colour the words chosen, or set
// them a step smaller or larger, Aa sets them in a face of their own and
// Link links them (see Spans) — only with words chosen — and the field
// shows the words in those colours, sizes and faces, linked ones underlined,
// as they are typed. A shape's words take none, so its bar leaves them out,
// as the Android twin's bar keeps them off.
//
// Typing is taken back a burst at a time (TypingCoalescer): the field tells
// the store where each burst ends, and the keyboard's own Undo — ⌘Z, a
// shake, three fingers — is the store's, so the typing stays open.

import SwiftUI
import UIKit

struct InlineTextField: UIViewRepresentable {
    let element: Element
    /// The words as typed, on every change.
    var onChange: (String) -> Void
    /// Typing is over: Done on the keyboard's bar, or Escape.
    var onDone: () -> Void
    /// Runs a style the bar puts on the words as a step of its own.
    var onStyled: (() -> Void) -> Void = { $0() }
    /// The colour well, for the words chosen: a range of the words as they
    /// read.
    var onWordColour: (NSRange) -> Void = { _ in }
    /// A- or A+ for the words chosen, and what their size is multiplied by.
    var onWordScale: (NSRange, Double) -> Void = { _, _ in }
    /// Aa, the font sheet for the words chosen.
    var onWordFont: (NSRange) -> Void = { _ in }
    /// Link, for the words chosen.
    var onWordLink: (NSRange) -> Void = { _ in }
    /// Whether the bar has the colour well, A- and A+, Aa and Link: not for
    /// a shape's words, which take no colours, sizes, fonts or links.
    var wordStyles = true
    /// The typing itself, apart from its words: its caret, its bursts and
    /// their Undo.
    var typing = Typing()

    /// What the field tells the store of the typing besides its words, and
    /// what it is asked.
    struct Typing {
        /// Where the caret or choice is now, in the stored words.
        var selection: (NSRange) -> Void = { _ in }
        /// A burst of typing is over: the step open closes.
        var step: () -> Void = {}
        /// The keyboard's Undo and Redo, and whether they have anything to do.
        var undo: () -> Void = {}
        var redo: () -> Void = {}
        var canUndo: () -> Bool = { false }
        var canRedo: () -> Bool = { false }
        /// A choice to make once (DesignStore.typingSelectionAsked).
        var asked: DesignStore.AskedSelection?
    }

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
        view.typingUndo.undoing = { [weak coordinator] in coordinator?.undo() }
        view.typingUndo.redoing = { [weak coordinator] in coordinator?.redo() }
        view.typingUndo.canUndoing = { [weak coordinator] in coordinator?.parent.typing.canUndo() ?? false }
        view.typingUndo.canRedoing = { [weak coordinator] in coordinator?.parent.typing.canRedo() ?? false }
        view.inputAccessoryView = context.coordinator.typingBar()
        context.coordinator.view = view
        context.coordinator.apply(element, to: view)
        // The caret at the end of the words, as it opens on the Android twin,
        // unless the store asked for a place of its own (apply made it).
        if typing.asked == nil {
            let end = view.endOfDocument
            view.selectedTextRange = view.textRange(from: end, to: end)
        }
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
        /// The colour well, A- and A+, Aa and Link, for the words chosen.
        private var wordItems: [UIBarButtonItem] = []
        /// The colours and sizes the words are shown in now, and the words
        /// they were put on.
        private var painted: [TextSpan] = []
        private var paintedWords: String?
        /// The words the store was last given: what a change is from.
        private var typedWords = ""
        /// Where each burst of typing ends.
        private var coalescer = TypingCoalescer()
        /// Where the last change left the caret, and the range the change
        /// under way replaces: a change anywhere else is a jump.
        private var lastCaret: NSRange?
        private var editRange: NSRange?
        /// The choice as last kept off the markers, for the arrow keys.
        private var lastSelection: NSRange?
        /// A style waiting for what is typed next, and the caret it waits at.
        private var pending: RichText.Pending?
        private var pendingCaret: Int?
        /// True while the field changes its own words or choice, and while a
        /// key's change it let through is under way: neither is the person
        /// moving the caret.
        private var applying = false
        private var editing = false
        /// The last choice asked of the field that it made.
        private var askedSerial: Int?

        init(_ parent: InlineTextField) {
            self.parent = parent
        }

        /// Sets the words and their look, keeping the caret — but never in
        /// the middle of a composition, which resetting would break — and
        /// makes any choice the store asks for.
        func apply(_ el: Element, to view: UITextView) {
            let drawn = InlineTextField.drawn(el)
            let attrs = FontLibrary.attributes(for: drawn)
            view.typingAttributes = attrs
            guard view.markedTextRange == nil else { return }
            let words = el.text ?? ""
            let signature = InlineTextField.signature(drawn)
            // The bar's buttons follow the box's own bold and the rest.
            defer { refreshStyles(view) }
            if view.text != words || signature != look {
                if view.text != words {
                    // Words set from outside — an Undo, a style, another box:
                    // what is typed next is a burst of its own.
                    coalescer.close()
                    pending = nil
                    typedWords = words
                }
                look = signature
                let kept = view.selectedRange
                applying = true
                view.attributedText = NSAttributedString(string: words, attributes: attrs)
                let length = (words as NSString).length
                let start = min(kept.location, length)
                view.selectedRange = NSRange(location: start, length: min(kept.length, length - start))
                applying = false
                paintedWords = nil
            }
            // Painted again whenever the words or their colours change: a
            // letter typed just after a coloured word picks up its colour in
            // the field, and is put back as the canvas will draw it.
            let spans = InlineTextField.shownSpans(el)
            if spans != painted || words != paintedWords {
                show(view, words: words, spans: spans)
            }
            applyAsked(view)
        }

        /// The words shown as they read, in `spans`, in the element's look.
        private func show(_ view: UITextView, words: String, spans: [TextSpan]) {
            let el = parent.element
            let drawn = InlineTextField.drawn(el)
            let attrs = FontLibrary.attributes(for: drawn)
            painted = spans
            paintedWords = words
            InlineTextField.paint(view.textStorage, words: words, spans: spans, attrs: attrs,
                                  weight: drawn.fontWeight ?? 400, italic: drawn.italic == true,
                                  gradient: el.textFill?.kind == "gradient",
                                  runFont: InlineTextField.runFont(for: drawn))
            view.typingAttributes = attrs
        }

        /// The choice the store asks for, made once.
        private func applyAsked(_ view: UITextView) {
            guard let asked = parent.typing.asked, asked.serial != askedSerial else { return }
            askedSerial = asked.serial
            let length = ((view.text ?? "") as NSString).length
            let start = min(max(asked.range.location, 0), length)
            applying = true
            view.selectedRange = NSRange(location: start, length: min(max(asked.range.length, 0), length - start))
            applying = false
            lastSelection = nil
            keepOffMarkers(view)
            lastCaret = view.selectedRange
            coalescer.close()
        }

        // MARK: typing

        /// What is typed goes in as the words read (RichText.typing): let
        /// through as it is when that is what the key does anyway, so the
        /// keyboard's own corrections and capitals carry on; otherwise put in
        /// by the field itself. A composition is let be.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            editRange = range
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
                keepOffMarkers(textView)
            }
            refreshStyles(textView)
        }

        /// The words changed, by a key or by the field: shown as they read,
        /// handed over, and the burst they are in closed when it is over.
        private func changed(_ view: UITextView) {
            let words = view.text ?? ""
            let before = typedWords
            pending = nil
            pendingCaret = nil
            if view.markedTextRange == nil {
                show(view, words: words, spans: Spans.remap(RichText.strip(before), RichText.strip(words), painted))
            }
            var jumped = false
            if let last = lastCaret, let range = editRange { jumped = !Self.continues(range, from: last) }
            let verdict = coalescer.change(from: before, to: words, at: ProcessInfo.processInfo.systemUptime,
                                           jumped: jumped)
            if verdict.closeFirst { parent.typing.step() }
            typedWords = words
            parent.onChange(words)
            lastCaret = view.selectedRange
            lastSelection = view.selectedRange
            parent.typing.selection(view.selectedRange)
            if verdict.closeAfter { parent.typing.step() }
            editRange = nil
            refreshStyles(view)
        }

        /// Whether a change over `range` carries on from where the change
        /// before left the caret, `last`: typed at it, deleted back from it,
        /// or over the words it had chosen.
        private static func continues(_ range: NSRange, from last: NSRange) -> Bool {
            range.location == last.location || NSMaxRange(range) == last.location
                || NSMaxRange(range) == NSMaxRange(last)
        }

        /// The caret or choice kept off the hidden markers, said to the
        /// store, and a waiting style dropped once the caret leaves it.
        private func keepOffMarkers(_ view: UITextView) {
            let chosen = view.selectedRange
            guard chosen.location != NSNotFound else { return }
            let kept = RichText.snapped(chosen, in: view.text ?? "", was: lastSelection)
            if kept != chosen {
                applying = true
                view.selectedRange = kept
                applying = false
            }
            lastSelection = kept
            if kept.length > 0 || kept.location != pendingCaret {
                pending = nil
                pendingCaret = nil
            }
            view.typingAttributes = FontLibrary.attributes(for: InlineTextField.drawn(parent.element))
            parent.typing.selection(kept)
        }

        /// The keyboard's Undo: the store's, a burst at a time.
        func undo() {
            coalescer.close()
            parent.typing.undo()
        }

        func redo() {
            coalescer.close()
            parent.typing.redo()
        }

        /// A bar over the keyboard: Bold, Italic, Underline and
        /// Strikethrough for the words chosen, their colour, A- and A+, their
        /// font and a link, and Done, the plainest way out.
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
            let face = UIBarButtonItem(title: "Aa", style: .plain, target: self, action: #selector(fontWords))
            face.accessibilityLabel = "Font of the selected words"
            let link = UIBarButtonItem(image: UIImage(systemName: "link"), style: .plain,
                                       target: self, action: #selector(linkWords))
            link.accessibilityLabel = "Link"
            wordItems = parent.wordStyles ? [well, smaller, larger, face, link] : []
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
        /// none chosen. Whatever the bar does with them is a step of its
        /// own, so each button ends the burst typed before it.
        private func chosenWords(_ view: UITextView) -> NSRange? {
            guard view.markedTextRange == nil else { return nil }
            return RichText.plainRange(of: view.selectedRange, in: view.text ?? "")
        }

        /// The colour sheet, for the words chosen.
        @objc private func colourWords() {
            guard let view, let range = chosenWords(view) else { return }
            coalescer.close()
            parent.onWordColour(range)
        }

        /// Aa: the font sheet, for the words chosen.
        @objc private func fontWords() {
            guard let view, let range = chosenWords(view) else { return }
            coalescer.close()
            parent.onWordFont(range)
        }

        /// Link: the link prompt, for the words chosen.
        @objc private func linkWords() {
            guard let view, let range = chosenWords(view) else { return }
            coalescer.close()
            parent.onWordLink(range)
        }

        /// A- or A+: the words chosen a step smaller or larger, as a step of
        /// their own; the same words stay chosen.
        @objc private func sizeWords(_ sender: UIBarButtonItem) {
            guard let view, let range = chosenWords(view) else { return }
            coalescer.close()
            parent.onWordScale(range, sender.tag == 0 ? Spans.smaller : Spans.larger)
        }

        /// The words chosen marked in the style, or unmarked when they all
        /// have it, and the same words left chosen, as a step of their own.
        /// With nothing chosen, the style waits for what is typed next — or
        /// stops waiting, pressed again — as in Canva.
        @objc private func style(_ sender: UIBarButtonItem) {
            guard let view, view.markedTextRange == nil,
                  RichText.Mark.allCases.indices.contains(sender.tag) else { return }
            let mark = RichText.Mark.allCases[sender.tag]
            let words = view.text ?? ""
            let chosen = view.selectedRange
            guard chosen.location != NSNotFound else { return }
            // Whatever the bar does ends the burst typed before it.
            coalescer.close()
            parent.typing.step()
            guard chosen.length > 0 else {
                var waiting = caretStyle(view)
                mark.turn(!mark.isOn(waiting), in: &waiting)
                pending = RichText.Pending(style: waiting, from: RichText.plainCaret(chosen.location, in: words))
                pendingCaret = chosen.location
                refreshStyles(view)
                return
            }
            guard let result = RichText.toggling(mark, in: words, selection: chosen) else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            // In the design it is a step of its own, as each press is; the
            // same words stay chosen.
            parent.onStyled {
                applying = true
                view.textStorage.replaceCharacters(in: NSRange(location: 0, length: view.textStorage.length),
                                                   with: result.text)
                view.selectedRange = result.selection
                applying = false
                show(view, words: result.text, spans: painted)
                typedWords = result.text
                lastCaret = result.selection
                lastSelection = result.selection
                parent.onChange(result.text)
                parent.typing.selection(result.selection)
            }
            refreshStyles(view)
        }

        /// The style what is typed at the caret takes: the one waiting there,
        /// else the letter before's — the first letter's at the start.
        private func caretStyle(_ view: UITextView) -> RichText.Style {
            let at = view.selectedRange.location
            if let pending, pendingCaret == at { return pending.style }
            let words = view.text ?? ""
            return RichText.styleAt(max(RichText.plainCaret(at, in: words) - 1, 0), in: words)
        }

        /// Each style button lit when the words chosen all have its style —
        /// or, with nothing chosen, when what is typed at the caret will
        /// have it, or the whole box has it.
        func refreshStyles(_ view: UITextView) {
            guard !styleItems.isEmpty else { return }
            let words = view.text ?? ""
            let chosen = view.selectedRange
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
            // Link lit when the words chosen are all linked.
            if let link = wordItems.last {
                let linked = picked.map { Spans.link(of: parent.element.liveSpans, in: $0) }
                let on = linked?.shared == true && linked?.link != nil
                link.tintColor = on ? UIColor(Theme.accent) : .label
                link.accessibilityTraits = on ? [.button, .selected] : .button
            }
            let atCaret = chosen.length == 0 ? caretStyle(view) : RichText.Style()
            for (item, mark) in zip(styleItems, RichText.Mark.allCases) {
                let on: Bool
                if chosen.length > 0 {
                    on = RichText.selectionHas(mark, in: words, selection: chosen)
                } else {
                    on = mark.isOn(atCaret) || (TextToggle(mark)?.isOn(parent.element) ?? false)
                }
                item.tintColor = on ? UIColor(Theme.accent) : .label
                item.accessibilityTraits = on ? [.button, .selected] : .button
            }
        }
    }

    /// The colours, sizes, fonts and links the field shows the words in:
    /// the element's, less the colours while its letters are a gradient, as
    /// on the canvas.
    static func shownSpans(_ el: Element) -> [TextSpan] {
        let spans = el.liveSpans
        guard el.textFill?.kind == "gradient" else { return spans }
        return Spans.withoutColours(spans)
    }

    /// The face a **bold** or *italic* run of `drawn` is shown in: the box's
    /// own type at the weight a bold word is drawn at, slanted for italic,
    /// from FontLibrary.attributes as the canvas sets it.
    static func runFont(for drawn: Element) -> (_ bold: Bool, _ italic: Bool) -> UIFont? {
        { bold, slanted in
            var styled = drawn
            styled.fontWeight = FontLibrary.resolveWeight(drawn.fontWeight ?? 400, bold: bold)
            styled.italic = slanted || drawn.italic == true
            return FontLibrary.attributes(for: styled)[.font] as? UIFont
        }
    }

    /// The typed words, markers and all, in `attrs`, shown as they read:
    /// the runs in their styles — bold and italic in `runFont`'s faces —
    /// and the markers drawn as nothing (hideMarkers). Then the colours,
    /// sizes and faces of `spans` — counted in the words as they read — on
    /// the letters they belong to, a face at the box's `weight` and slant
    /// and the run's, and linked words underlined in the link colour unless
    /// coloured — or, in `gradient` letters, in the text's ink, as the
    /// canvas draws them.
    static func paint(_ storage: NSTextStorage, words: String, spans: [TextSpan],
                      attrs: [NSAttributedString.Key: Any], weight: Int = 400, italic: Bool = false,
                      gradient: Bool = false,
                      runFont: (_ bold: Bool, _ italic: Bool) -> UIFont? = { _, _ in nil }) {
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(attrs, range: whole)
        if storage.length == (words as NSString).length {
            let units = RichText.typedUnits(words)
            let runs = RichText.parse(words).runs
            styleRuns(storage, runs: runs, units: units, runFont: runFont)
            for span in spans {
                paintSpan(span, in: storage, runs: runs, units: units, attrs: attrs,
                          look: (weight: weight, italic: italic, gradient: gradient), runFont: runFont)
            }
            hideMarkers(storage, units: units)
        }
        storage.endEditing()
    }

    /// Each run's letters bold, italic, underlined or struck through.
    private static func styleRuns(_ storage: NSTextStorage, runs: [RichText.Run], units: [Int],
                                  runFont: (_ bold: Bool, _ italic: Bool) -> UIFont?) {
        for run in runs {
            let face = run.style.bold || run.style.italic ? runFont(run.style.bold, run.style.italic) : nil
            for range in RichText.typedRanges(of: run.range, units: units) {
                if let face { storage.addAttribute(.font, value: face, range: range) }
                if run.style.underline {
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
                if run.style.strike {
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
            }
        }
    }

    /// One span's colour, link, face and size on the letters it belongs to.
    private static func paintSpan(_ span: TextSpan, in storage: NSTextStorage, runs: [RichText.Run], units: [Int],
                                  attrs: [NSAttributedString.Key: Any],
                                  look: (weight: Int, italic: Bool, gradient: Bool),
                                  runFont: (_ bold: Bool, _ italic: Bool) -> UIFont?) {
        for range in RichText.typedRanges(of: span.range, units: units) {
            if let color = span.color ?? (span.link != nil && !look.gradient ? Spans.linkColour : nil) {
                storage.addAttribute(.foregroundColor, value: UIColor(hex: color), range: range)
            }
            if span.link != nil {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        guard let font = attrs[.font] as? UIFont, span.font != nil || span.scale != nil else { return }
        let scale = span.scale ?? 1
        // Cut where the runs change, so a bold word keeps its weight in a
        // face or a size of its own.
        for piece in pieces(of: span.range, runs: runs) {
            let style = piece.style
            var face = style.bold || style.italic ? runFont(style.bold, style.italic) ?? font : font
            if let family = span.font {
                face = FontLibrary.uiFont(family: family, size: Double(font.pointSize),
                                          weight: FontLibrary.resolveWeight(look.weight, bold: style.bold),
                                          italic: look.italic || style.italic)
            }
            for range in RichText.typedRanges(of: piece.range, units: units) {
                storage.addAttribute(.font, value: face.withSize(face.pointSize * scale), range: range)
                if scale > 1 { RichText.makeRoom(in: storage, for: range, scale: scale) }
            }
        }
    }

    /// `range` of the words as they read cut where the runs' styles change,
    /// each piece with its style.
    private static func pieces(of range: NSRange, runs: [RichText.Run]) -> [(range: NSRange, style: RichText.Style)] {
        var cuts: Set<Int> = [range.location, NSMaxRange(range)]
        for run in runs {
            for edge in [run.range.location, NSMaxRange(run.range)]
            where edge > range.location && edge < NSMaxRange(range) {
                cuts.insert(edge)
            }
        }
        let sorted = cuts.sorted()
        return zip(sorted, sorted.dropFirst()).map { lo, hi in
            let style = runs.first { NSLocationInRange(lo, $0.range) }?.style ?? RichText.Style()
            return (range: NSRange(location: lo, length: hi - lo), style: style)
        }
    }

    /// The face the markers are drawn in: too small to see, and clear.
    static let markerFont = UIFont.systemFont(ofSize: 0.01)

    /// Every stored character that is not one of the words as they read —
    /// a style marker — drawn as nothing: a hundredth of a point, clear,
    /// no line under or through it, and its width taken back by a kern, so
    /// the words sit exactly as the canvas sets them.
    private static func hideMarkers(_ storage: NSTextStorage, units: [Int]) {
        let shown = Set(units)
        let text = storage.string as NSString
        var at = 0
        while at < text.length {
            guard !shown.contains(at) else {
                at += 1
                continue
            }
            var end = at
            while end < text.length, !shown.contains(end) { end += 1 }
            let range = NSRange(location: at, length: end - at)
            let width = text.substring(with: range).size(withAttributes: [.font: markerFont]).width
            storage.addAttributes([.font: markerFont, .foregroundColor: UIColor.clear,
                                   .kern: -width / CGFloat(range.length)], range: range)
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            at = end
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

/// A text view that hands Escape on a hardware keyboard back as Done, and
/// its Undo to the store (TypingUndo).
final class InlineTextView: UITextView {
    var onEscape: () -> Void = {}
    let typingUndo = TypingUndo()

    override var undoManager: UndoManager? { typingUndo }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.keyCode == .keyboardEscape }) {
            onEscape()
            return
        }
        super.pressesBegan(presses, with: event)
    }
}

/// The typing field's Undo — ⌘Z, a shake, three fingers — handed to the
/// store, which takes typing back a burst at a time and keeps the typing
/// open. What the text view records for itself here is never undone, and
/// only the latest of it is kept.
final class TypingUndo: UndoManager {
    var undoing: () -> Void = {}
    var redoing: () -> Void = {}
    var canUndoing: () -> Bool = { false }
    var canRedoing: () -> Bool = { false }

    override init() {
        super.init()
        levelsOfUndo = 1
    }

    override var canUndo: Bool { canUndoing() }
    override var canRedo: Bool { canRedoing() }
    override func undo() { undoing() }
    override func redo() { redoing() }
}

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
// List turns the lines the choice covers — the caret's, with nothing chosen
// — to bullets, then numbers, then no list, and Indent and Outdent nest them
// a level at a time (TextLists); Tab and Shift-Tab on a hardware keyboard do
// as Indent and Outdent, and Return on an empty item ends the list there
// rather than starting another. Each is a step of its own. The bar scrolls
// sideways on a narrow phone, Done always in reach at its end.
//
// Typing is taken back a burst at a time (TypingCoalescer): the field tells
// the store where each burst ends, and the keyboard's own Undo — ⌘Z, a
// shake, three fingers — is the store's, so the typing stays open.
//
// What is typed reads exactly as typed: a star or an underscore is escaped
// (RichText.escapeLiteral), never a marker; only the bar's styles write
// markers. Copy and Cut put the words on the clipboard as they read, and
// beside them as Canvia keeps them (RichClipboard), so a paste into another
// box keeps their styles, colours, sizes and lists; another app gets the
// plain words. Paste is a step of its own named Paste. Typing "- ", "* ",
// "1. " or "a) " at the start of a line starts a list there, a step after
// the typing, unless Settings has turned it off; Backspace at the start of
// an item takes it a level out, then out of the list, before it ever joins
// lines (TextLists).

import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    /// The highlighter, the marker colours for the words chosen.
    var onWordHighlight: (NSRange) -> Void = { _ in }
    /// ⇧⌘K: capitals on or off for the whole box, as a step of its own
    /// (TextKeys).
    var onToggle: (TextToggle) -> Void = { _ in }
    /// ⇧⌘L, C, R and J: the whole box aligned, as a step of its own.
    var onAlign: (String) -> Void = { _ in }
    /// ⌥⌘ and an arrow, ⌥⌘C and ⌥⌘V: the whole box's line or letter
    /// spacing a step tighter or looser, or its look copied or pasted, as
    /// a step of its own (TextKeys).
    var onBoxKey: (TextKeys.Command) -> Void = { _ in }
    /// List, Indent, Outdent, Return on an empty item and Tab: the lines
    /// a range of the stored words covers changed, as a step of its own;
    /// whether anything changed.
    var onLines: (NSRange, (inout TextParagraph) -> Void) -> Bool = { _, _ in false }
    /// Paste over a range of the stored words: words copied here, or else
    /// another app's plain words. Nil leaves Paste to the text view itself,
    /// which still types the words in as they read.
    var onPaste: ((NSRange, RichClipboard.Clip?, String) -> Void)?
    /// A typed prefix started a list: the line, the prefix's length in the
    /// words as they read, and the list.
    var onAutoList: (Int, Int, String) -> Void = { _, _, _ in }
    /// For a table's cell: Tab, or the bar's arrow, goes on to the next
    /// cell, and Shift-Tab (true) back to the one before; nil anywhere else.
    var onNextCell: ((Bool) -> Void)?
    /// Whether the bar has the colour well, A- and A+, Aa and Link: not for
    /// a shape's words, which take no colours, sizes, fonts or links.
    var wordStyles = true
    /// Whether it has List, Indent and Outdent, with Return, Tab and
    /// Backspace on list items and ⇧⌘7 and ⇧⌘8 — a shape's words too.
    var lineStyles = true
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
        view.onTab = { [weak coordinator] outdent in coordinator?.tab(outdent: outdent) ?? false }
        view.onKey = { [weak coordinator] action in coordinator?.key(action) }
        view.onCopy = { [weak coordinator] cut in coordinator?.copyWords(cut: cut) ?? false }
        view.onPaste = { [weak coordinator] in coordinator?.pasteWords() ?? false }
        view.onBackspace = { [weak coordinator] in coordinator?.backspace() ?? false }
        view.typingUndo.onUndo = { [weak coordinator] in coordinator?.undo() }
        view.typingUndo.onRedo = { [weak coordinator] in coordinator?.redo() }
        view.typingUndo.canUndoing = { [weak coordinator] in coordinator?.parent.typing.canUndo() ?? false }
        view.typingUndo.canRedoing = { [weak coordinator] in coordinator?.parent.typing.canRedo() ?? false }
        view.inputAccessoryView = context.coordinator.typingAccessory()
        context.coordinator.view = view
        context.coordinator.apply(element, to: view)
        // The caret at the end of the words, as it opens on the Android twin,
        // unless the store asked for a place of its own (apply made it): a
        // tap's caret, a double tap's word, or every word of a box just
        // added — Add text here's among them — so the first key replaces them.
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
        [el.fontFamily ?? "", "\(el.fontSize ?? 42)", "\(FontLibrary.weight(of: el))", "\(FontLibrary.isItalic(el))",
         "\(el.underline == true)", el.align ?? "", "\(el.lineHeight ?? 1.25)", "\(el.letterSpacing ?? 0)",
         el.color ?? "", "\(el.paragraphSpacing ?? 0)", "\(el.indent ?? 0)", el.listStyle ?? "",
         (el.paragraphs ?? []).map { "\($0.list)\($0.level)" }.joined(separator: ",")]
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
        /// List, Outdent and Indent, for the lines the choice covers.
        private var lineItems: [UIBarButtonItem] = []
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
        /// A list a typed prefix starts once the space typed is in.
        private var autoList: (line: Int, prefix: Int, list: String)?

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
            // Each line at its own level, its list moved with the words
            // typed since the box was last given them.
            var lined = drawn
            if lined.text != words { lined.setText(words) }
            InlineTextField.paint(view.textStorage, words: words, spans: spans, attrs: attrs, drawn: drawn,
                                  gradient: el.textFill?.kind == "gradient",
                                  runFont: InlineTextField.runFont(for: drawn))
            FontLibrary.setParagraphStyles(view.textStorage, for: lined)
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
            // Return on an empty list item ends the list there, as in Canva.
            if text == "\n", range.length == 0, endsList(at: range.location, in: textView) { return false }
            autoList = text == " " && range.length == 0 ? autoStart(at: range.location, in: textView) : nil
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
            // A typed prefix starts its list as a step after the typing.
            if let auto = autoList {
                autoList = nil
                coalescer.close()
                parent.typing.step()
                parent.onAutoList(auto.line, auto.prefix, auto.list)
            }
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

        // MARK: lines

        /// The lines the choice covers changed by `change`, as a step of its
        /// own (TextLists); false when there is nothing to change — a
        /// shape's words, a composition under way.
        @discardableResult
        private func changeLines(_ range: NSRange, _ change: (inout TextParagraph) -> Void) -> Bool {
            guard let view, view.markedTextRange == nil, parent.lineStyles,
                  parent.element.text == view.text else { return false }
            coalescer.close()
            return parent.onLines(range, change)
        }

        /// What the lines the choice covers are: each line's list and level,
        /// and the lines, as the box sets them now.
        private func chosenLines(_ view: UITextView) -> (lines: [TextParagraph], covered: ClosedRange<Int>) {
            let lines = TextLists.lines(parent.element)
            let covered = TextLists.lineRange(view.text ?? "", view.selectedRange)
            return (lines, covered.clamped(to: 0...max(lines.count - 1, 0)))
        }

        /// List: the lines chosen turned to the next of no list, bullets and
        /// numbers after the first one's, all alike.
        @objc private func cycleList() {
            guard let view else { return }
            let chosen = chosenLines(view)
            let first = chosen.covered.lowerBound < chosen.lines.count ? chosen.lines[chosen.covered.lowerBound].list : "none"
            let next = TextLists.nextList(first)
            changeLines(view.selectedRange) { $0.list = next }
            refreshStyles(view)
        }

        /// Outdent (tag 0) or Indent (tag 1): the lines chosen a level
        /// shallower or deeper, each within 0 to the deepest.
        @objc private func indentLines(_ sender: UIBarButtonItem) {
            guard let view else { return }
            indent(view, by: sender.tag == 0 ? -1 : 1)
        }

        /// Tab, or Shift-Tab to `outdent`, on a hardware keyboard: as Indent
        /// and Outdent, as Canva nests its items. False where the words take
        /// no lists, and the key is typed as ever.
        func tab(outdent: Bool) -> Bool {
            // In a table's cell, Tab goes on to the next cell instead.
            if let next = parent.onNextCell {
                next(outdent)
                return true
            }
            guard let view, parent.lineStyles else { return false }
            indent(view, by: outdent ? -1 : 1)
            return true
        }

        private func indent(_ view: UITextView, by delta: Int) {
            changeLines(view.selectedRange) {
                $0.level = min(TextLists.maxLevel, max(0, $0.level + delta))
            }
            refreshStyles(view)
        }

        /// Return typed at `caret` on an empty list item: the item's list
        /// cleared instead of a new line put in. False — and Return types a
        /// line as ever — on any other line.
        private func endsList(at caret: Int, in view: UITextView) -> Bool {
            let words = view.text ?? ""
            guard parent.lineStyles, parent.element.text == words else { return false }
            let line = TextLists.lineRange(words, NSRange(location: caret, length: 0)).lowerBound
            let raw = words.components(separatedBy: "\n")
            let lines = TextLists.lines(parent.element)
            guard line < raw.count, line < lines.count, lines[line].isListed,
                  RichText.strip(raw[line]).trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            return changeLines(NSRange(location: caret, length: 0)) { $0.list = "none" }
        }

        /// The list a space typed at `caret` starts (TextLists.autoStart): on
        /// a line not listed yet, whose words before the caret are a bullet,
        /// a number or a letter and its stop. Nil anywhere else, where the
        /// words take no lists, and with the setting off.
        private func autoStart(at caret: Int, in view: UITextView) -> (line: Int, prefix: Int, list: String)? {
            let words = view.text ?? ""
            guard parent.lineStyles, parent.onNextCell == nil, TextLists.autoListsOn,
                  parent.element.text == words else { return nil }
            let plain = RichText.strip(words)
            let at = RichText.plainCaret(caret, in: words)
            let line = TextLists.lineRange(plain, NSRange(location: at, length: 0)).lowerBound
            let starts = TextLists.lineStarts(plain)
            let lines = TextLists.lines(parent.element)
            guard line < starts.count, line < lines.count, !lines[line].isListed, at >= starts[line] else { return nil }
            let typed = (plain as NSString).substring(with: NSRange(location: starts[line], length: at - starts[line])) + " "
            guard let list = TextLists.autoStart(typed, caret: (typed as NSString).length) else { return nil }
            return (line, (typed as NSString).length, list)
        }

        /// Backspace with the caret at the very start of a listed line: the
        /// item a level out, or out of its list (TextLists.backspaced) — the
        /// lines not joined. False anywhere else, and the key deletes as
        /// ever.
        func backspace() -> Bool {
            guard let view, view.markedTextRange == nil, parent.lineStyles, view.selectedRange.length == 0,
                  parent.element.text == view.text else { return false }
            let words = view.text ?? ""
            let plain = RichText.strip(words) as NSString
            let at = RichText.plainCaret(view.selectedRange.location, in: words)
            guard at == 0 || (at <= plain.length && plain.character(at: at - 1) == 0x0A) else { return false }
            let line = TextLists.lineRange(plain as String, NSRange(location: at, length: 0)).lowerBound
            guard TextLists.backspaceAtItemStart(parent.element, line: line) != nil else { return false }
            let taken = changeLines(view.selectedRange) { TextLists.backspaced(&$0) }
            refreshStyles(view)
            return taken
        }

        // MARK: the clipboard

        /// Copy, or Cut (`cut`): the words chosen on the clipboard as they
        /// read and as Canvia keeps them (RichClipboard); cut, they are then
        /// deleted as a backspace would. False with no words chosen, and
        /// the text view does as it would.
        func copyWords(cut: Bool) -> Bool {
            guard let view, let range = chosenWords(view) else { return false }
            let words = view.text ?? ""
            var el = parent.element
            if el.text != words { el.setText(words) }
            let clip = RichClipboard.copy(el, start: range.location, end: NSMaxRange(range))
            UIPasteboard.general.items = [[UTType.utf8PlainText.identifier: clip.plain,
                                           RichClipboard.type: RichClipboard.json(clip)]]
            guard cut else { return true }
            let typed = RichText.typing("", over: view.selectedRange, in: words, pending: nil)
            applying = true
            view.textStorage.replaceCharacters(in: NSRange(location: 0, length: view.textStorage.length),
                                               with: typed.text)
            view.selectedRange = NSRange(location: typed.caret, length: 0)
            applying = false
            changed(view)
            return true
        }

        /// Paste: words copied here keep their styles, colours, sizes and
        /// lists; another app's styled words — its HTML, else its RTF
        /// (ForeignText) — keep theirs while Keep formatting when pasting
        /// is on; anything else is pasted as it reads — as one step
        /// (DesignStore.pasteTyped). Paste as plain text is in the hold
        /// menu on the page, as on the Android twin. False when the store
        /// does not take pastes here, or there is nothing to paste.
        func pasteWords() -> Bool {
            guard let view, view.markedTextRange == nil, let paste = parent.onPaste else { return false }
            let board = UIPasteboard.general
            let own = RichClipboard.decode(board.data(forPasteboardType: RichClipboard.type))
            let clip = own ?? ForeignText.clip(on: board, boxSize: parent.element.fontSize ?? 42)
            guard let words = clip?.plain ?? board.string else { return false }
            coalescer.close()
            paste(view.selectedRange, clip, words)
            return true
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

        /// What sits over the keyboard: the bar (typingBar) in a strip that
        /// scrolls sideways when it is wider than the phone, and Done at its
        /// end, always in reach — the plainest way out.
        func typingAccessory() -> UIView {
            let accessory = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            accessory.autoresizingMask = .flexibleWidth
            // The bar's own look behind both, across the whole width.
            let backing = UIToolbar(frame: accessory.bounds)
            backing.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            accessory.addSubview(backing)
            let tools = typingBar()
            let width = CGFloat((tools.items ?? []).count) * 44 + 16
            tools.frame = CGRect(x: 0, y: 0, width: width, height: 44)
            let strip = UIScrollView()
            strip.showsHorizontalScrollIndicator = false
            strip.alwaysBounceHorizontal = false
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

        /// A bar over the keyboard: Bold, Italic, Underline and
        /// Strikethrough for the words chosen, their colour, A- and A+, their
        /// font and a link, and List, Outdent and Indent for the lines the
        /// choice covers.
        func typingBar() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            styleItems = RichText.Mark.allCases.enumerated().map { entry -> UIBarButtonItem in
                let face = InlineTextField.face(of: entry.element)
                let item = UIBarButtonItem(image: UIImage(systemName: face.symbol), style: .plain,
                                           target: self, action: #selector(styleItem(_:)))
                item.tag = entry.offset
                item.accessibilityLabel = face.name
                return item
            }
            let well = UIBarButtonItem(image: UIImage(systemName: "circle.fill"), style: .plain,
                                       target: self, action: #selector(colourWords))
            well.accessibilityLabel = tr("Colour of the selected words")
            let marker = UIBarButtonItem(image: UIImage(systemName: "highlighter"), style: .plain,
                                         target: self, action: #selector(highlightWords))
            marker.accessibilityLabel = tr("Highlight")
            let smaller = UIBarButtonItem(title: "A-", style: .plain, target: self, action: #selector(sizeWords(_:)))
            smaller.tag = 0
            smaller.accessibilityLabel = tr("Smaller")
            let larger = UIBarButtonItem(title: "A+", style: .plain, target: self, action: #selector(sizeWords(_:)))
            larger.tag = 1
            larger.accessibilityLabel = tr("Larger")
            let face = UIBarButtonItem(title: "Aa", style: .plain, target: self, action: #selector(fontWords))
            face.accessibilityLabel = tr("Font of the selected words")
            let link = UIBarButtonItem(image: UIImage(systemName: "link"), style: .plain,
                                       target: self, action: #selector(linkWords))
            link.accessibilityLabel = tr("Link")
            wordItems = parent.wordStyles ? [well, marker, smaller, larger, face, link] : []
            let list = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain,
                                       target: self, action: #selector(cycleList))
            list.accessibilityLabel = tr("List")
            let outdent = UIBarButtonItem(image: UIImage(systemName: "decrease.indent"), style: .plain,
                                          target: self, action: #selector(indentLines(_:)))
            outdent.tag = 0
            outdent.accessibilityLabel = tr("Outdent")
            let indent = UIBarButtonItem(image: UIImage(systemName: "increase.indent"), style: .plain,
                                         target: self, action: #selector(indentLines(_:)))
            indent.tag = 1
            indent.accessibilityLabel = tr("Indent")
            lineItems = parent.lineStyles ? [list, outdent, indent] : []
            // A table's cell: first, the arrow to the next cell.
            var cellItems: [UIBarButtonItem] = []
            if parent.onNextCell != nil {
                let next = UIBarButtonItem(image: UIImage(systemName: "arrow.right"), style: .plain,
                                           target: self, action: #selector(nextCell))
                next.accessibilityLabel = tr("Next cell")
                cellItems = [next]
            }
            bar.items = cellItems + styleItems + wordItems + lineItems
            bar.sizeToFit()
            return bar
        }

        @objc private func finish() {
            parent.onDone()
        }

        @objc private func nextCell() {
            parent.onNextCell?(false)
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

        /// The highlighter: the marker colours, for the words chosen.
        @objc private func highlightWords() {
            guard let view, let range = chosenWords(view) else { return }
            coalescer.close()
            parent.onWordHighlight(range)
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
        @objc private func styleItem(_ sender: UIBarButtonItem) {
            guard RichText.Mark.allCases.indices.contains(sender.tag) else { return }
            style(RichText.Mark.allCases[sender.tag])
        }

        private func style(_ mark: RichText.Mark) {
            guard let view, view.markedTextRange == nil else { return }
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

        /// A formatting key on a hardware keyboard (TextKeys), as the bar's
        /// button for it: the words chosen marked, the box set in capitals
        /// or aligned, the lines listed, the words chosen a step smaller or
        /// larger — with words chosen, as A- and A+ are only then; with
        /// none, the size keys do nothing. A shape's words take lists but no
        /// sizes, as its bar has none.
        func key(_ action: TextKeys.Command) {
            guard let view else { return }
            switch action {
            case .bold: style(.bold)
            case .italic: style(.italic)
            case .underline: style(.underline)
            case .strike: style(.strike)
            case .uppercase:
                coalescer.close()
                parent.onToggle(.uppercase)
            case .alignLeft, .alignCenter, .alignRight, .alignJustify:
                guard let align = TextKeys.keyAlignment(action) else { return }
                coalescer.close()
                parent.onAlign(align)
            case .numberedList, .bulletedList:
                guard let list = TextKeys.keyList(action) else { return }
                toggleList(list, in: view)
            case .smaller, .larger:
                guard parent.wordStyles, let range = chosenWords(view) else { return }
                coalescer.close()
                parent.onWordScale(range, action == .smaller ? Spans.smaller : Spans.larger)
            case .link:
                // As the bar's Link: only with words chosen, and never a
                // shape's words, which take no links.
                guard parent.wordStyles, let range = chosenWords(view) else { return }
                coalescer.close()
                parent.onWordLink(range)
            case .lineTighter, .lineLooser, .letterTighter, .letterLooser, .copyStyle, .pasteStyle:
                guard view.markedTextRange == nil else { return }
                coalescer.close()
                parent.onBoxKey(action)
            }
        }

        /// The lines chosen made `list` — or no list, when the first of
        /// them is that already — all alike, as a step of its own.
        private func toggleList(_ list: String, in view: UITextView) {
            let chosen = chosenLines(view)
            let first = chosen.covered.lowerBound < chosen.lines.count ? chosen.lines[chosen.covered.lowerBound].list : "none"
            let next = first == list ? "none" : list
            changeLines(view.selectedRange) { $0.list = next }
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
            // The highlighter in the marker the words chosen share.
            if wordItems.count > 1 {
                let marked = picked.map { Spans.highlight(of: parent.element.liveSpans, in: $0) }
                let hex = marked?.shared == true ? marked?.highlight : nil
                wordItems[1].tintColor = hex.map { UIColor(hex: $0) } ?? .label
            }
            // Link lit when the words chosen are all linked.
            if let link = wordItems.last {
                let linked = picked.map { Spans.link(of: parent.element.liveSpans, in: $0) }
                let on = linked?.shared == true && linked?.link != nil
                link.tintColor = on ? UIColor(Theme.accent) : .label
                link.accessibilityTraits = on ? [.button, .selected] : .button
            }
            refreshLines(view)
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

        /// List shows the list of the first line the choice covers — numbers
        /// for numbers or letters, bullets otherwise, lit while it is a list
        /// — and Outdent and Indent are there while the lines can go
        /// shallower or deeper.
        private func refreshLines(_ view: UITextView) {
            guard lineItems.count == 3 else { return }
            let chosen = chosenLines(view)
            let covered = chosen.lines.indices.filter { chosen.covered.contains($0) }.map { chosen.lines[$0] }
            let list = covered.first?.list ?? "none"
            let counted = list == "number" || list == "letter"
            lineItems[0].image = UIImage(systemName: counted ? "list.number" : "list.bullet")
            lineItems[0].tintColor = list != "none" ? UIColor(Theme.accent) : .label
            lineItems[0].accessibilityValue = TypeReadouts.listStyle(list)
            lineItems[0].accessibilityTraits = list != "none" ? [.button, .selected] : .button
            let levels = covered.map(\.level)
            lineItems[1].isEnabled = (levels.max() ?? 0) > 0
            lineItems[2].isEnabled = (levels.min() ?? TextLists.maxLevel) < TextLists.maxLevel
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
            styled.fontWeight = FontLibrary.resolveWeight(FontLibrary.weight(of: drawn), bold: bold)
            styled.italic = slanted || FontLibrary.isItalic(drawn)
            return FontLibrary.attributes(for: styled)[.font] as? UIFont
        }
    }

    /// The typed words, markers and all, in `attrs`, shown as they read:
    /// the runs in their styles — bold and italic in `runFont`'s faces —
    /// and the markers drawn as nothing (hideMarkers). Then the colours,
    /// sizes and faces of `spans` — counted in the words as they read — on
    /// the letters they belong to: a bold or italic word's face at the
    /// weight and slant of the box `drawn` and the run's, a plain word's at
    /// `drawn`'s weight and slant in its own font (FontLibrary.weight(of:in:)),
    /// as the canvas sets them; and linked words underlined in the link
    /// colour unless coloured — or, in `gradient` letters, in the text's
    /// ink, as the canvas draws them.
    static func paint(_ storage: NSTextStorage, words: String, spans: [TextSpan],
                      attrs: [NSAttributedString.Key: Any], drawn: Element = Element.text(""),
                      gradient: Bool = false,
                      runFont: (_ bold: Bool, _ italic: Bool) -> UIFont? = { _, _ in nil }) {
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(attrs, range: whole)
        if storage.length == (words as NSString).length {
            let units = RichText.typedUnits(words)
            let runs = RichText.parse(words).runs
            styleRuns(storage, runs: runs, units: units, runFont: runFont)
            let look = (weight: FontLibrary.weight(of: drawn), italic: FontLibrary.isItalic(drawn), gradient: gradient)
            for span in spans {
                paintSpan(span, in: storage, runs: runs, units: units, attrs: attrs,
                          look: look, drawn: drawn, runFont: runFont)
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
                                  look: (weight: Int, italic: Bool, gradient: Bool), drawn: Element,
                                  runFont: (_ bold: Bool, _ italic: Bool) -> UIFont?) {
        for range in RichText.typedRanges(of: span.range, units: units) {
            if let color = span.color ?? (span.link != nil && !look.gradient ? Spans.linkColour : nil) {
                storage.addAttribute(.foregroundColor, value: UIColor(hex: color), range: range)
            }
            if span.link != nil {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if let highlight = span.highlight {
                storage.addAttribute(.backgroundColor, value: UIColor(hex: highlight), range: range)
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
                // A plain word at the box's own weight and slant in its own
                // font — that face's, where the box has none (styledWords'
                // rule, and the Android twin's) — a bold or italic one at
                // the box's.
                var weight = look.weight
                var italic = look.italic
                if !style.bold && !style.italic {
                    weight = FontLibrary.weight(of: drawn, in: family)
                    italic = FontLibrary.isItalic(drawn, in: family)
                }
                face = FontLibrary.uiFont(family: family, size: Double(font.pointSize),
                                          weight: FontLibrary.resolveWeight(weight, bold: style.bold),
                                          italic: italic || style.italic)
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
        case .bold: return ("bold", tr("Bold"))
        case .italic: return ("italic", tr("Italic"))
        case .underline: return ("underline", tr("Underline"))
        case .strike: return ("strikethrough", tr("Strikethrough"))
        }
    }
}

/// A text view that hands Escape on a hardware keyboard back as Done, and
/// its Undo to the store (TypingUndo).
final class InlineTextView: UITextView {
    var onEscape: () -> Void = {}
    /// Tab, or Shift-Tab (true), on a hardware keyboard; whether it was
    /// taken.
    var onTab: (Bool) -> Bool = { _ in false }
    /// A formatting key (TextKeys): ⌘B and the rest.
    var onKey: (TextKeys.Command) -> Void = { _ in }
    /// Copy, or Cut (true), Paste and Backspace, each true when the field
    /// took it.
    var onCopy: (Bool) -> Bool = { _ in false }
    var onPaste: () -> Bool = { false }
    var onBackspace: () -> Bool = { false }
    let typingUndo = TypingUndo()

    override func copy(_ sender: Any?) {
        if !onCopy(false) { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        if !onCopy(true) { super.cut(sender) }
    }

    override func paste(_ sender: Any?) {
        if !onPaste() { super.paste(sender) }
    }

    override func deleteBackward() {
        if !onBackspace() { super.deleteBackward() }
    }

    override var undoManager: UndoManager? { typingUndo }

    /// The formatting keys, each named so holding ⌘ lists it. Over the
    /// system's own ⌘B, ⌘I and ⌘U, which would set attributes this field
    /// does not keep: the markers are the style.
    override var keyCommands: [UIKeyCommand]? {
        let own = TextKeys.all.map { key -> UIKeyCommand in
            let name = TextKeys.keyName(key.action)
            var flags: UIKeyModifierFlags = [.command]
            if key.shift { flags.insert(.shift) }
            if key.alt { flags.insert(.alternate) }
            let command = UIKeyCommand(title: name, action: #selector(formatKey(_:)), input: Self.input(of: key.key),
                                       modifierFlags: flags)
            command.discoverabilityTitle = name
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
        return (super.keyCommands ?? []) + own
    }

    /// The key command input for a TextKeys key: an arrow as UIKit names
    /// it, any other key as it is.
    static func input(of key: String) -> String {
        switch key {
        case TextKeys.up: return UIKeyCommand.inputUpArrow
        case TextKeys.down: return UIKeyCommand.inputDownArrow
        case TextKeys.left: return UIKeyCommand.inputLeftArrow
        case TextKeys.right: return UIKeyCommand.inputRightArrow
        default: return key
        }
    }

    /// A TextKeys key for a key command input: an arrow back to the table's.
    static func key(of input: String) -> String {
        switch input {
        case UIKeyCommand.inputUpArrow: return TextKeys.up
        case UIKeyCommand.inputDownArrow: return TextKeys.down
        case UIKeyCommand.inputLeftArrow: return TextKeys.left
        case UIKeyCommand.inputRightArrow: return TextKeys.right
        default: return input
        }
    }

    @objc private func formatKey(_ sender: UIKeyCommand) {
        guard let input = sender.input,
              let action = TextKeys.action(for: Self.key(of: input), shift: sender.modifierFlags.contains(.shift),
                                           alt: sender.modifierFlags.contains(.alternate)) else { return }
        onKey(action)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.keyCode == .keyboardEscape }) {
            onEscape()
            return
        }
        // Tab nests the lines chosen rather than typing a tab, and Shift-Tab
        // brings them back out; with Command it is the system's.
        if let key = presses.first(where: { $0.key?.keyCode == .keyboardTab })?.key,
           !key.modifierFlags.contains(.command), onTab(key.modifierFlags.contains(.shift)) {
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
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var canUndoing: () -> Bool = { false }
    var canRedoing: () -> Bool = { false }

    override init() {
        super.init()
        levelsOfUndo = 1
    }

    override var canUndo: Bool { canUndoing() }
    override var canRedo: Bool { canRedoing() }
    override func undo() { onUndo() }
    override func redo() { onRedo() }
}

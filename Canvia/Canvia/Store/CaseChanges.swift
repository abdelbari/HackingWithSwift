// Capitals on chosen words and Change case. While words are chosen in the
// box typed in, aA and ⇧⌘K set them in capitals or back as typed (a span's
// caps, Spans); with none chosen they set the whole box, as ever. Change
// case — UPPERCASE, lowercase, Title Case, Sentence case — rewrites the
// words chosen, or every selected box's words with none chosen, in the
// design's language (ChangeCase), as one step named "Change case".

import Foundation

extension DesignStore {

    /// The words chosen in the box typed in, as a range of its words as they
    /// read; nil with nothing chosen, or nothing typed in.
    var chosenTypedWords: WordRange? {
        guard let id = editingTextId, let range = typingSelection, let el = element(id), el.type == .text,
              !el.locked, let plain = RichText.plainRange(of: range, in: el.text ?? "") else { return nil }
        return WordRange(id: id, range: plain)
    }

    /// aA and ⇧⌘K: capitals on the words chosen while typing — or back as
    /// typed when they all have them — else on every selected text whole
    /// (toggleText). One step.
    func toggleCaps() {
        guard let chosen = chosenTypedWords else {
            toggleText(.uppercase)
            return
        }
        capsWords(chosen.id, range: chosen.range)
    }

    /// The words in `range` of box `id` in capitals, or as typed again when
    /// they all are, as one step.
    func capsWords(_ id: String, range: NSRange) {
        guard range.length > 0 else { return }
        updateSelected { el in
            guard el.id == id else { return }
            Self.restyleWords(&el, range) { Spans.toggledCaps($0, range: $1) }
        }
    }

    /// Whether aA shows lit: the words chosen while typing all in capitals —
    /// their own or their box's — else every selected text set in them; nil
    /// for Mixed.
    var capsShown: Bool? {
        guard let chosen = chosenTypedWords, let el = element(chosen.id) else {
            return sharedText { TextToggle.uppercase.isOn($0) }
        }
        if el.uppercase == true { return true }
        let shared = Spans.caps(of: el.liveSpans, in: chosen.range)
        return shared.shared ? shared.caps == true : nil
    }

    /// Change case: the words chosen in the box typed in, or with none
    /// chosen every selected, unlocked text's words, cased as `kind` asks in
    /// the design's language — one step, "Change case". A buzz when nothing
    /// would change.
    func changeCase(_ kind: ChangeCase.Casing) {
        let locale = ChangeCase.locale(design.language)
        let typed = editingTextId
        let selection = typingSelection
        let changed = selectedElements.contains { el in
            guard ShapeText.carriesWords(el), !el.locked, typed == nil || el.id == typed else { return false }
            return ChangeCase.changed(el, selection: el.id == typed ? selection : nil, kind, locale: locale) != nil
        }
        guard changed else {
            buzz(.reject)
            return
        }
        styleWhileTyping {
            namedStep = ChangeCase.stepName
            updateSelected { el in
                guard ShapeText.carriesWords(el), typed == nil || el.id == typed,
                      let next = ChangeCase.changed(el, selection: el.id == typed ? selection : nil, kind, locale: locale)
                else { return }
                el = next
            }
        }
        buzz(.tick)
    }
}

// Central editor state. Design is a value type, so history entries are
// plain copies. Gesture coalescing mirrors the web store: beginGesture()
// captures the pre-gesture doc, transient mutations happen freely, and one
// commit() records a single undo step.

import SwiftUI
import Observation

@Observable
final class DesignStore {
    var design: Design
    var pageIndex: Int = 0 {
        // Another page brought up puts the timeline's playhead at its start
        // (TimelineEditing), as the Android twin's playhead follows the page,
        // and lets the last page's clips' players go (ClipPlayers) — its
        // own only, so a page playing in another window plays on.
        didSet {
            if pageIndex != oldValue {
                ClipPlayers.shared.close(elements: clipElements(onPage: oldValue))
                playhead = 0
                playheadPage = design.pages.indices.contains(pageIndex) ? design.pages[pageIndex].id : nil
            }
        }
    }
    var selection: Set<String> = [] {
        // Crop mode works on one selected photo. Selecting anything else —
        // another element, the page, another page — ends it, and the crop
        // so far is kept, never dropped.
        didSet {
            if let crop = cropping, selection != [crop.id] { finishCrop() }
            if let crop = graphicCropping, selection != Set(crop.ids) { finishGraphicCrop() }
            // So does a brush's, kept as its one step.
            if let brush = brushing, selection != [brush.id] { finishBrush() }
            // And recording a motion path, which belongs to its element.
            if let recording = motionRecording, selection != [recording.id] { motionRecording = nil }
            // Typing in place ends however the box stops being the one thing
            // selected — a Layers row, a page change, a lock, its group taken
            // whole — as its own step, and an emptied box goes with it. The
            // Android twin's selection watcher.
            if let id = editingTextId, selection != [id] { endTextEdit() }
            // Dictation belongs to the box it began on: selecting anything
            // else ends it here and now, as its own step, before whatever did
            // the selecting opens one, so a drag that began with the
            // selection is never folded into the dictated words.
            if let target = dictationTarget, selection != [target] { endDictation() }
            // Apply colours to page starts its turns again on what is
            // selected now.
            if selection != oldValue { photoColourTurn = 0 }
        }
    }
    var editingTextId: String?
    /// Where the field typed in has its caret or choice now, in its stored
    /// words: what Undo while typing puts back with the words.
    @ObservationIgnored var typingSelection: NSRange?
    /// A choice the field typed in is asked to make once — where a tap put
    /// the caret, a word double tapped, a new text's words all chosen, the
    /// caret an Undo puts back — as a UTF-16 range of its stored words.
    var typingSelectionAsked: AskedSelection?
    /// Texts just added — Add text, a brand role, a font combination — and
    /// their words then: typing opened in one whose words are unchanged
    /// chooses them all, so the first key replaces them, as in Canva. View
    /// state only — never saved.
    @ObservationIgnored var freshTexts: [String: String] = [:]
    /// Where on the page the tap that opened the typing under way landed,
    /// for the line the view zooms in on (Viewport.typingZoom); nil when it
    /// opened without one. View state only — never saved.
    @ObservationIgnored var typingPoint: CGPoint?
    /// The words the colour sheet is open for, from the typing bar's colour
    /// well (see WordStyles).
    var wordColourTarget: WordRange?
    /// The words the font sheet is open for, from the typing bar's Aa.
    var wordFontTarget: WordRange?
    /// The words the marker colours are open for, from the typing bar's
    /// highlighter (see WordStyles).
    var wordHighlightTarget: WordRange?
    /// The text whose shape Edit shape has handles on — its warp's, or its
    /// path's points (TextWarping); nil when none.
    var shapeEditingId: String?
    /// Edit chart asked for from the canvas — VoiceOver's Edit data on a
    /// chart — with the chart selected; the editor opens it and clears this.
    var chartEditRequested = false
    /// The words the link prompt is open for, from the typing bar's Link.
    var wordLinkTarget: WordRange?
    /// A photo dropped on a selected text box, waiting to be asked whether
    /// it fills the letters or lands on the page (PhotoInLetters).
    var letterFillOffer: LetterFillOffer?
    /// The photo-filled text Adjust photo is open for.
    var photoAdjustTarget: String?
    /// The photo-filled text double-tapped, offered Adjust photo.
    var photoAdjustOffer: String?
    /// The text box dictation writes into while the microphone is on. Its
    /// words go there and nowhere else, whatever is selected meanwhile.
    var dictationTarget: String?
    /// True while a finger is working the canvas — a move, a band, a handle.
    /// Keeping the selection in view waits for it to lift, so the page never
    /// slides out from under a drag.
    var canvasTouchActive = false
    /// True while the view itself moves — a pan, a pinch, the glide after
    /// one — so what floats over the selection on screen waits for it.
    var canvasMoving = false
    /// True while a panel is up over the lower half of the canvas: the edge
    /// scroll's bottom edge is the panel's top.
    var panelOpen = false
    /// Mirrors the canvas scroll view's zoomScale, so selection handles can
    /// stay a constant size on screen. The scroll view owns pan entirely.
    var zoom: Double = 1

    /// What the canvas snaps to. Persisted; see SnapSettings.
    var snapping = SnapSettings.load() {
        didSet { if snapping != oldValue { snapping.save() } }
    }

    // Transient overlay state during gestures.
    var guideX: Double?
    var guideY: Double?
    /// What each snap guide lines the selection up with, for its label.
    var guideXSource: Geometry.SnapSource?
    var guideYSource: Geometry.SnapSource?
    var badge: String?
    /// The badge in parts, when some are to be picked out in the guide
    /// colour; see setBadge.
    var badgeRuns: [BadgeRun]?

    /// The badge from parts: the words as `badge`, the parts for drawing.
    func setBadge(_ runs: [BadgeRun]) {
        badgeRuns = runs
        badge = Readouts.text(runs)
    }

    /// True while a text field outside the canvas — one of the toolbar's
    /// alerts — has the keyboard, so plain keys are left to it.
    var textFieldOpen = false

    /// Check accessibility's "Show reading order": each element numbered on
    /// the canvas in the order VoiceOver reads it. View state only.
    var showsReadingOrder = false

    /// Check accessibility's "View as": the canvas as a colour vision
    /// deficiency sees it, while the sheet is open. View state only — never
    /// written to the design.
    var viewAs: ColourVision.Sight = .typical

    // The canvas's view of the page, mirrored from the scroll view: the part
    // of the page on screen, in page units, and the zoom that fits it all.
    // View state only — never saved.
    var viewport: CGRect = .zero
    var fitZoom: Double = 1
    /// A change of view asked of the canvas: fit the page, zoom about the
    /// middle of the screen, or bring a box into sight.
    var canvasRequest: CanvasRequest?

    func requestCanvas(_ kind: CanvasRequest.Kind) {
        canvasRequest = CanvasRequest(kind: kind, serial: (canvasRequest?.serial ?? 0) + 1)
    }

    /// When set, the next picked image replaces this element's source
    /// instead of inserting a new image.
    var replaceTargetId: String?

    private var clipboard: [Element] = []
    /// The page the clipboard was copied from, and the page pasted onto
    /// last: a paste somewhere new lands in place (Copies.pasteOffset).
    private var clipboardPage: String?
    /// The records of the fonts of your own the clipboard is set in, which
    /// a paste brings into a design that has none (CustomFonts.adopting).
    private var clipboardFonts: [CustomFonts.Record] = []
    private var pastedOnto: String?
    private var pasteCount = 0

    /// Select multiple: while on, a tap on an element adds it to the
    /// selection or takes it out, a tap on the empty page leaves the
    /// selection be, and a banner stands in for the toolbar. View state
    /// only — never saved — as on the Android twin.
    var selectingMultiple = false

    private struct HistoryEntry {
        var design: Design
        var pageIndex: Int
        /// The caret in the words being typed as the step began, while one
        /// was: where Undo while typing puts it back.
        var caret: NSRange?
        /// What the step did, in a word (History.label), for the system's
        /// undo to name: on a past entry, the step that took the design on
        /// from it; on a future one, the step that was taken back.
        var label: String?
    }
    private var past: [HistoryEntry] = []
    private var future: [HistoryEntry] = []
    private var pending: HistoryEntry?
    private let historyLimit = 100
    /// The shape being typed in, as it was before the typing began: what a
    /// shape left with no words goes back to, though a style pressed while
    /// typing has closed the step it began in — as on the Android twin.
    @ObservationIgnored private var typedShapeBefore: Element?
    /// Steps recorded since typing in place opened, which Undo takes back
    /// one at a time without ending it, and how many of those Redo can bring
    /// back again.
    @ObservationIgnored private var typingSteps = 0
    @ObservationIgnored private var typingRedos = 0
    /// What the next step recorded is called, when it is named for what it
    /// did rather than by History.label: "Paste", "Replace font".
    @ObservationIgnored var namedStep: String?
    /// How tall a text's words stand, for a table whose words changed in a
    /// step to be laid out again as part of it (DataGraphics.settlingTables),
    /// and for the Table controls. Tests measure in round numbers.
    @ObservationIgnored var measure: (Element) -> Double = { FontLibrary.layoutHeight(for: $0) }

    var onCommit: (() -> Void)?

    /// The first page's words, by element, as of the last step: what tells
    /// an edit to the headline from the headline becoming another text.
    @ObservationIgnored private var lastWords: [String: String] = [:]

    init(design: Design) {
        self.design = design
        self.lastWords = Self.words(of: design)
    }

    var page: Page {
        get { design.pages[min(pageIndex, design.pages.count - 1)] }
        set { design.pages[min(pageIndex, design.pages.count - 1)] = newValue }
    }

    /// The ids of the elements showing a clip on page `index` — the
    /// master's behind it too — whose players are let go when the page is
    /// left (ClipPlayers.close); none for an index out of range.
    func clipElements(onPage index: Int) -> Set<String> {
        guard design.pages.indices.contains(index) else { return [] }
        return Set(design.drawnElements(on: design.pages[index]).filter { VideoStore.isVideo($0.src) }.map(\.id))
    }

    func element(_ id: String) -> Element? {
        page.elements.first { $0.id == id }
    }

    /// The current page's size — its own, or the document's.
    var pageSize: CGSize { design.size(for: page) }
    var pageWidth: Double { page.width ?? design.width }
    var pageHeight: Double { page.height ?? design.height }

    var selectedElements: [Element] {
        page.elements.filter { selection.contains($0.id) }
    }

    var singleSelection: Element? {
        selection.count == 1 ? selection.first.flatMap(element) : nil
    }

    // MARK: history

    func beginGesture() {
        if pending == nil {
            pending = HistoryEntry(design: design, pageIndex: pageIndex,
                                   caret: editingTextId == nil ? nil : typingSelection)
        }
    }

    /// True while an open gesture holds a pre-mutation snapshot.
    var hasPendingChanges: Bool { pending != nil }

    /// The design as it stands, first, then every state Undo or Redo can
    /// return to: what still holds a photo taken out of it since it opened.
    var statesInHistory: [Design] {
        var states = [design]
        if let pending { states.append(pending.design) }
        states += past.map(\.design)
        states += future.map(\.design)
        return states
    }

    func commit() {
        // Without a beginGesture() snapshot there is no pre-mutation state to
        // record — pushing the current design would make undo a no-op.
        let named = namedStep
        namedStep = nil
        guard let entry = pending else { return }
        // A table's rows follow its words, and connectors their ends, as
        // part of the same step.
        design = DataGraphics.settlingTables(design, since: entry.design, heightFor: measure)
        // A font or colour given to a chart's words is kept for its Update.
        design = DataGraphics.styleKept(design, since: entry.design)
        Connectors.resolve(in: &design)
        // A whiteboard's bounds follow what is on it, in the same step.
        design = Whiteboards.refreshed(design)
        // A step that changed nothing — a text box opened and left as it
        // was, a crop opened and closed untouched — would be an Undo that
        // visibly does nothing, and would wipe Redo; it is closed without
        // being recorded, as on the Android twin.
        if entry.design == design && entry.pageIndex == pageIndex {
            pending = nil
            return
        }
        historyVersion += 1
        // And a design still named by the app takes its headline as its name,
        // in this same step, so one Undo takes back the words and the name.
        adoptHeadline()
        lastWords = Self.words(of: design)
        var recorded = entry
        recorded.label = named ?? History.label(before: entry.design, after: design)
        past.append(recorded)
        if past.count > historyLimit { past.removeFirst() }
        future.removeAll()
        pending = nil
        if editingTextId != nil {
            typingSteps += 1
            typingRedos = 0
        }
        design.updatedAt = Date().timeIntervalSince1970 * 1000
        onCommit?()
    }

    /// While the title is still the app's, the design is named after its
    /// headline — but only when this step changed the headline's own words:
    /// not when another text became the headline, by a delete, a resize or a
    /// reorder, when the name would come from words nobody typed. Nor when
    /// the edit was to a line of the headline the title does not come from.
    private func adoptHeadline() {
        guard design.titleAuto, let head = Titles.headlineElement(design),
              let before = lastWords[head.id], before != head.text,
              let title = Titles.title(from: head) else { return }
        var old = head
        old.text = before
        guard title != Titles.title(from: old), title != design.title else { return }
        design.title = title
    }

    /// Every text on the first page, by element.
    private static func words(of design: Design) -> [String: String] {
        var words: [String: String] = [:]
        for el in design.pages.first?.elements ?? [] {
            if let text = el.text { words[el.id] = text }
        }
        return words
    }

    /// End a gesture that changed nothing, without recording history.
    func endGesture() {
        pending = nil
    }

    /// Put the design back exactly as it was when the open gesture began,
    /// recording nothing: what Cancel does in crop mode.
    func revertGesture() {
        guard let entry = pending else { return }
        pending = nil
        historyVersion += 1
        design = entry.design
        pageIndex = min(entry.pageIndex, max(design.pages.count - 1, 0))
        let ids = Set(page.elements.map(\.id))
        selection = selection.intersection(ids)
    }

    /// Mutate + record as one undo step.
    func apply(_ mutate: (inout Design) -> Void) {
        // Words being typed or dictated are a step of their own: a command
        // while they are open — Delete, Duplicate, Bold — closes them first,
        // so one Undo takes back one or the other and the words are never
        // lost with it, as the Android twin's edit() does.
        if pending != nil && (editingTextId != nil || dictationTarget != nil) { commit() }
        beginGesture()
        mutate(&design)
        commit()
    }

    /// Mutate the current page + record one undo step. A locked page keeps
    /// what is on it and its background (PageLocks.allows): an edit that
    /// would change either is refused, and said, with Unlock.
    func applyToPage(_ mutate: (inout Page) -> Void) {
        if isPageLocked {
            var changed = page
            mutate(&changed)
            guard PageLocks.allows(page, becoming: changed) else {
                refusesLockedPage()
                return
            }
            let index = pageIndex
            apply { $0.pages[index] = changed }
            return
        }
        apply { design in
            mutate(&design.pages[self.pageIndex])
        }
    }

    /// Mutate every selected, unlocked element + record one undo step.
    /// A text whose type changed — face, weight, slant, alignment, spacing,
    /// path — is measured again, so its box keeps hugging its words, as the
    /// Android twin's text panel remeasures every style change.
    func updateSelected(_ mutate: (inout Element) -> Void) {
        guard !selection.isEmpty else { return }
        applyToPage { page in
            for i in page.elements.indices
            where self.selection.contains(page.elements[i].id) && !page.elements[i].locked {
                let before = page.elements[i]
                mutate(&page.elements[i])
                page.elements[i] = Self.remeasured(page.elements[i], was: before)
            }
        }
    }

    /// `el` with its box height measured again when it is a text whose
    /// typography changed and whose height the edit did not set itself.
    /// layoutHeight keeps fitted, aligned, vertical and path boxes at their
    /// own size, so only a plain box snaps to its words. A shape's words
    /// grow it when they no longer fit, and never shrink it.
    static func remeasured(_ el: Element, was before: Element) -> Element {
        guard ShapeText.carriesWords(el), el.h == before.h, typographyChanged(el, from: before) else { return el }
        var out = el
        ShapeText.fitWords(&out)
        return out
    }

    private static func typographyChanged(_ a: Element, from b: Element) -> Bool {
        a.fontFamily != b.fontFamily || a.fontWeight != b.fontWeight || a.italic != b.italic
            || a.underline != b.underline || a.uppercase != b.uppercase
            || a.align != b.align || a.textPath != b.textPath
            || a.letterSpacing != b.letterSpacing || a.lineHeight != b.lineHeight
            || a.paragraphSpacing != b.paragraphSpacing || a.fontSize != b.fontSize
            || a.listStyle != b.listStyle || a.indent != b.indent || a.vertical != b.vertical
            || a.dropCap != b.dropCap || a.effect != b.effect || a.text != b.text
            || a.spans != b.spans || a.paragraphs != b.paragraphs
    }

    /// Transient variant for continuous controls; call commit() on release.
    func updateSelectedTransient(_ mutate: (inout Element) -> Void) {
        beginGesture()
        for i in design.pages[pageIndex].elements.indices
        where selection.contains(design.pages[pageIndex].elements[i].id)
            && !design.pages[pageIndex].elements[i].locked {
            mutate(&design.pages[pageIndex].elements[i])
        }
        Connectors.resolve(&design.pages[pageIndex])
    }

    /// Joins the two selected elements with an arrow that follows them.
    func connectSelected() {
        let ordered = page.elements.filter { selection.contains($0.id) }
        guard ordered.count == 2 else {
            buzz(.reject)
            announce(tr("Select two things to connect"), undoable: false)
            return
        }
        var line = Element.line(w: 100)
        line.connectFrom = ordered[0].id
        line.connectTo = ordered[1].id
        line.endCap = "arrow"
        let g = Connectors.geometry(from: ordered[0].frame, to: ordered[1].frame, thickness: line.thickness ?? 4)
        line.x = g.x; line.y = g.y; line.w = g.w; line.h = g.h; line.rotation = g.rotation
        applyToPage { $0.elements.append(line) }
        selection = [line.id]
        announce(tr("Connected — the arrow follows both ends"))
    }

    /// Steps to take back — or words being typed, which are one once they
    /// change anything: typing opens a step before a key is pressed, and an
    /// Undo then would only end the typing, as on the Android twin.
    var canUndo: Bool {
        !past.isEmpty || (editingTextId != nil && pending.map { $0.design != design } == true)
    }

    /// Moves with every step recorded, undone, redone or thrown away. An
    /// Undo offered in a toast is only honest while this is what it was
    /// when the offer was made, as on the Android twin.
    private(set) var historyVersion = 0
    /// Steps to make again — none while words being typed have changed
    /// anything since the last step, which a Redo would only close (and the
    /// steps after it go with that), as on the Android twin.
    var canRedo: Bool {
        !future.isEmpty && !(editingTextId != nil && pending.map { $0.design != design } == true)
    }

    /// Undo; `reveal` false while Undo is held to rewind, which brings what
    /// it changed into view once, as the finger lifts (revealSelection).
    /// While typing in place, a burst of the typing at a time (undoTyping).
    func undo(reveal: Bool = true) {
        if undoTyping(reveal: reveal) { return }
        // Typing, with nothing before it to take back either: the typing
        // stays open, as on the Android twin.
        if editingTextId != nil && past.isEmpty { return }
        // Typing, dictation or a crop under way is kept as its own step
        // first, so Undo takes back that rather than whatever came before
        // it — and the words typed are never thrown away with that step.
        closeOpenSteps()
        guard let entry = past.popLast() else { return }
        future.append(HistoryEntry(design: design, pageIndex: pageIndex, label: entry.label))
        restore(entry, reveal: reveal)
        buzz(.undo)
    }

    func redo() {
        if redoTyping() { return }
        // Typing, with nothing to make again — words typed since the last
        // Undo close their step and clear what was to be redone: the typing
        // stays open, as on the Android twin.
        if editingTextId != nil && future.isEmpty { return }
        closeOpenSteps()
        guard let entry = future.popLast() else { return }
        past.append(HistoryEntry(design: design, pageIndex: pageIndex, label: entry.label))
        restore(entry, reveal: true)
        buzz(.redo)
    }

    /// What Undo would take back, in a word — "Move", "Delete" — for the
    /// system's undo gestures and shake to say (DesignUndo); nil with
    /// nothing to take back. And what Redo would do again.
    var undoLabel: String? { past.last?.label }
    var redoLabel: String? { future.last?.label }

    /// Whatever is still open — typing, dictation, a crop, a slider's step
    /// — closed as its own step, as the Android twin does before Undo.
    private func closeOpenSteps() {
        endTextEdit()
        endDictation()
        finishCrop()
        commit()
    }

    /// Undo while typing in place: the burst typed last (TypingCoalescer),
    /// or a style put on meanwhile, taken back with the caret where it
    /// was, the typing still open — as in Canva, as on the Android twin.
    /// False when nothing typed since it opened is left to take back, and
    /// Undo ends the typing and goes on as ever, as on the Android twin —
    /// unless there is nothing at all to take back, when it stays open.
    private func undoTyping(reveal: Bool = true) -> Bool {
        guard editingTextId != nil else { return false }
        commit()
        guard typingSteps > 0, let entry = past.popLast() else { return false }
        typingSteps -= 1
        typingRedos += 1
        future.append(HistoryEntry(design: design, pageIndex: pageIndex, caret: typingSelection, label: entry.label))
        restore(entry, reveal: reveal, typing: true)
        buzz(.undo)
        return true
    }

    /// Redo while typing in place: a step Undo took back while typing, again.
    private func redoTyping() -> Bool {
        guard editingTextId != nil else { return false }
        commit()
        guard typingRedos > 0, let entry = future.popLast() else { return false }
        typingRedos -= 1
        typingSteps += 1
        past.append(HistoryEntry(design: design, pageIndex: pageIndex, caret: typingSelection, label: entry.label))
        restore(entry, reveal: true, typing: true)
        buzz(.redo)
        return true
    }

    /// The step open while typing closed as a step of its own: a burst of
    /// typing is over (TypingCoalescer).
    func closeTypingStep() {
        guard editingTextId != nil else { return }
        commit()
    }

    /// The field typed in asked to choose `range` of its stored words.
    func askTypingSelection(_ range: NSRange) {
        typingSelectionAsked = AskedSelection(range: range, serial: (typingSelectionAsked?.serial ?? 0) + 1)
    }

    /// A choice asked of the field typed in, once: `serial` tells a new ask
    /// from one already made.
    struct AskedSelection: Equatable {
        var range: NSRange
        var serial: Int
    }

    private func restore(_ entry: HistoryEntry, reveal: Bool, typing: Bool = false) {
        let typed = typing ? editingTextId : nil
        historyVersion += 1
        let before = design
        design = entry.design
        // A post that comes back, or goes, with the step has its reminder
        // set again, or taken away, as on the Android twin.
        if design.plannedPosts != before.plannedPosts { PostReminders.reschedule(design, before: before) }
        // An undone step brings words back rather than typing them: it never
        // renames the design.
        lastWords = Self.words(of: design)
        pageIndex = min(entry.pageIndex, design.pages.count - 1)
        // Undo and Redo close any typing first, but while typing (`typing`)
        // keep it open below; this only makes sure a box being typed into is
        // not ended by the selection below as a step.
        editingTextId = nil
        pending = nil
        // What the step changed on the page now shown is selected, whole
        // sticky groups and all, so you can see what came back and go on
        // working on it, as in Canva; a step that only took things away
        // leaves nothing selected. The selection is never a step itself.
        // A page the step brought back whole — Delete page undone — is
        // compared with itself, so nothing on it is selected, as on the
        // Android twin.
        let shown = page
        let was = before.pages.first { $0.id == shown.id } ?? shown
        let ids = Set(shown.elements.map(\.id))
        // Nothing on a locked page is ever selected.
        let changed: Set<String> = PageLocks.isLocked(shown) ? []
            : History.changedIds(before: was, after: shown).intersection(ids)
        let groups = Set(shown.elements.filter { changed.contains($0.id) }.compactMap(\.group))
        selection = changed.union(shown.elements.filter { $0.group.map(groups.contains) == true }.map(\.id))
        // Undo while typing keeps the box typed in, alone even in a group,
        // its caret put back.
        if let typed, ids.contains(typed) {
            selection = [typed]
            editingTextId = typed
            let length = ((element(typed)?.text ?? "") as NSString).length
            askTypingSelection(entry.caret ?? NSRange(location: length, length: 0))
        }
        if reveal { revealSelection() }
        onCommit?()
    }

    /// The selection brought into view when any of it is off screen, by
    /// the least scroll (CanvasRequest.reveal) — after an Undo or a Redo,
    /// and as a held Undo's rewind lets go.
    func revealSelection() {
        guard let box = selectionBox else { return }
        let seen = viewport
        guard seen.width <= 0 || !seen.contains(box) else { return }
        requestCanvas(.reveal(box))
    }

    // MARK: selection

    func select(_ id: String?, additive: Bool = false) {
        endTextEdit()
        guard let id else {
            selection.removeAll()
            return
        }
        // Nothing on a locked page is selected: the tap is said, with Unlock.
        guard !refusesLockedPage() else { return }
        // Expand to sticky group.
        var ids: Set<String> = [id]
        if let group = element(id)?.group {
            ids = Set(page.elements.filter { $0.group == group }.map(\.id))
        }
        if additive {
            if ids.isSubset(of: selection) { selection.subtract(ids) }
            else { selection.formUnion(ids) }
        } else {
            selection = ids
        }
        if selection.count >= 2 { tipEvent = .multiSelected }
        // One thing small on screen: its handles are hard to take, and a
        // pinch on it resizes it (CanvasGestures.pinchesSelection).
        if let el = singleSelection, !el.holdsPlace,
           min(el.w, el.h) * max(zoom, 0.05) < Touch.moveHandleBelow { tipEvent = .smallSelected }
    }

    /// A tap on one member of a group that is already selected goes inside
    /// it, as in Canva and on the Android twin: the first tap takes the
    /// outermost group, the next the group inside it that the thing tapped
    /// is in, and so on down, and the last the thing tapped (Groups.deeper).
    /// A tap on a member already selected alone keeps it so. A drag still
    /// moves what is selected. True when the tap was taken that way.
    @discardableResult
    func selectMember(_ id: String) -> Bool {
        guard let next = Groups.deeper(page.elements, selection: selection, tapped: id) else { return false }
        endTextEdit()
        selection = next
        return true
    }

    // MARK: typing in place

    /// Typing in place is over, however it ended: the box stops being
    /// edited, a box left empty is removed, and the typing is its own undo
    /// step. Every way out comes through here, as on the Android twin. A
    /// shape left with no words stays, its words gone (ShapeText.withoutWords).
    /// A table's cell stays however empty — it is still a cell of the
    /// table — and its row grows or shrinks to the words in the typing's own
    /// step (see commit).
    func endTextEdit() {
        guard let id = editingTextId else { return }
        editingTextId = nil
        typingSteps = 0
        typingRedos = 0
        for p in design.pages.indices {
            guard let i = design.pages[p].elements.firstIndex(where: { $0.id == id }) else { continue }
            let words = design.pages[p].elements[i].text ?? ""
            if design.pages[p].elements[i].table == nil,
               words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                beginGesture()
                if design.pages[p].elements[i].type == .shape {
                    let before = typedShapeBefore?.id == id
                        ? typedShapeBefore
                        : pending?.design.pages.flatMap(\.elements).first { $0.id == id }
                    design.pages[p].elements[i] = ShapeText.withoutWords(design.pages[p].elements[i], was: before)
                } else {
                    design.pages[p].elements.remove(at: i)
                    if selection.contains(id) { selection.remove(id) }
                }
            }
        }
        typedShapeBefore = nil
        commit()
    }

    /// Typing in place begins in a text box or a shape. Any typing before
    /// is ended as its own step, and the step for this typing opens after
    /// it. Only this box is selected, even inside a group, as on the Android
    /// twin: its text controls show while it is typed, and a group corner or
    /// Delete never works the whole group. A shape given its first words
    /// takes their look in this same step (ShapeText.starting), so the
    /// first burst typed takes it back with them.
    ///
    /// The field opens with the caret where `point` — a tap, on the page —
    /// puts it (TextCaret), the word there chosen with `word`, as a double
    /// tap chooses it; or every word of a text just added chosen while they
    /// are as they were added (freshTexts), so the first key replaces them;
    /// else at the end.
    func startTyping(_ id: String, at point: CGPoint?, word: Bool = false) {
        // A caption box is not typed into (typedIn).
        guard element(id)?.captions == nil else { return }
        guard !refusesLockedPage() else { return }
        endTextEdit()
        selection = [id]
        editingTextId = id
        typingSteps = 0
        typingRedos = 0
        let length = ((element(id)?.text ?? "") as NSString).length
        typingPoint = point
        let opening = openingSelection(id, at: point, word: word) ?? NSRange(location: length, length: 0)
        typingSelection = opening
        askTypingSelection(opening)
        beginGesture()
        typedShapeBefore = design.pages[pageIndex].elements.first { $0.id == id && $0.type == .shape }
        guard let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == id }),
              ShapeText.takesText(design.pages[pageIndex].elements[i]),
              (design.pages[pageIndex].elements[i].text ?? "").isEmpty else { return }
        design.pages[pageIndex].elements[i] = ShapeText.starting(design.pages[pageIndex].elements[i])
    }

    /// Typing in place in `id`, the caret at the end, or its words all
    /// chosen when just added.
    func startTyping(_ id: String) {
        startTyping(id, at: nil)
    }

    /// Where the field typed in opens its caret or choice in `id`'s stored
    /// words; nil for the end.
    private func openingSelection(_ id: String, at point: CGPoint?, word: Bool) -> NSRange? {
        guard let el = element(id) else { return nil }
        let words = el.text ?? ""
        if let added = freshTexts.removeValue(forKey: id), added == words, !words.isEmpty {
            return NSRange(location: 0, length: (words as NSString).length)
        }
        guard let point, let caret = TextCaret.caret(in: el, onPage: point) else { return nil }
        return word ? TextCaret.word(at: caret, in: words) : NSRange(location: caret, length: 0)
    }

    /// A text added from Add text or a brand role, as `add` adds it, and
    /// remembered as just added (freshTexts).
    func addText(_ el: Element) {
        add(el)
        markFresh([el])
    }

    /// `elements`' text boxes, just added, as the only freshTexts: an add
    /// forgets those added before it, so only the latest add opens with its
    /// words chosen, as on the Android twin.
    private func markFresh(_ elements: [Element]) {
        freshTexts.removeAll()
        for el in elements where el.type == .text { freshTexts[el.id] = el.text ?? "" }
    }

    /// The words typed in place, into the open step: a text box measured
    /// to them, a shape grown down when they need more room than it has.
    func typeWords(_ words: String, into id: String) {
        beginGesture()
        guard let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == id }),
              design.pages[pageIndex].elements[i].text != words else { return }
        design.pages[pageIndex].elements[i].setText(words)
        ShapeText.fitWords(&design.pages[pageIndex].elements[i])
    }

    // MARK: dictation

    /// Dictated words for the dictation's own text box: written there, and
    /// only while it is still an unlocked text on this page. False when they
    /// had nowhere to go.
    @discardableResult
    func dictate(_ words: String) -> Bool {
        guard let id = dictationTarget,
              let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == id }),
              design.pages[pageIndex].elements[i].type == .text,
              !design.pages[pageIndex].elements[i].locked else { return false }
        beginGesture()
        design.pages[pageIndex].elements[i].setText(words)
        design.pages[pageIndex].elements[i].h = FontLibrary.layoutHeight(for: design.pages[pageIndex].elements[i])
        return true
    }

    /// The microphone stopped, and what it wrote kept as one step.
    func endDictation() {
        guard dictationTarget != nil else { return }
        if Dictation.shared.isListening { Dictation.shared.stop() }
        finishDictation()
    }

    /// Dictation is over: what it wrote is one undo step.
    func finishDictation() {
        guard dictationTarget != nil else { return }
        dictationTarget = nil
        commit()
    }

    // MARK: element commands

    /// `element` added and selected, as one step; false when it went
    /// nowhere — every page from here on locked — so Add's Recently used
    /// keeps only what went on, as on the Android twin.
    @discardableResult
    func add(_ element: Element, centered: Bool = true) -> Bool {
        // Onto the next unlocked page when this one is locked, or not at all.
        guard landsOnUnlockedPage() else { return false }
        defer {
            let count = page.elements.count
            tipEvent = count == 1 ? .firstElementAdded
                : element.type == .text ? .textAdded
                : element.type == .image ? .photoAdded
                : count >= 6 ? .manyElements : nil
        }
        var el = element
        if centered && el.x == 0 && el.y == 0 {
            el.x = (pageWidth - el.w) / 2
            el.y = (pageHeight - el.h) / 2
        }
        applyToPage { $0.elements.append(el) }
        selection = [el.id]
        promptAltText(el)
        return true
    }

    /// Settings ▸ Accessibility's Ask for alt text: the element just added
    /// whose alt text is asked for (AltTextPrompt); nil for none.
    var altTextPrompt: String?

    /// Asks for `el`'s alt text when the setting is on and it is a photo,
    /// a graphic or a chart (AccessibilityPrefs.prompts).
    func promptAltText(_ el: Element) {
        guard UserDefaults.standard.bool(forKey: AccessibilityPrefs.altTextPromptKey),
              AccessibilityPrefs.prompts(el) else { return }
        altTextPrompt = el.id
    }

    /// The alt text typed for `altTextPrompt`, as one step; blank asks
    /// nothing more of it.
    func answerAltTextPrompt(_ text: String) {
        guard let id = altTextPrompt else { return }
        altTextPrompt = nil
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        apply { d in
            for p in d.pages.indices {
                guard let i = d.pages[p].elements.firstIndex(where: { $0.id == id }) else { continue }
                d.pages[p].elements[i].altText = words
            }
        }
    }

    /// A graphic brought in from an SVG file (see SvgImport): every part on
    /// the page as one step, the whole graphic selected, and a word when
    /// some of the file could not come with it.
    func addGraphic(_ graphic: SvgImport.Graphic) {
        guard !graphic.elements.isEmpty, landsOnUnlockedPage() else { return }
        applyToPage { $0.elements += graphic.elements }
        selection = Set(graphic.elements.map(\.id))
        if let first = graphic.elements.first { promptAltText(first) }
        if graphic.skipped {
            buzz(.reject)
            announce(SvgImport.partialNote, undoable: false)
        } else {
            buzz(.confirm)
        }
    }

    /// Delete asked for with something locked in position selected: the
    /// editor asks first, and its Delete is deleteSelected(confirmed: true)
    /// — the Android twin's confirmingDelete.
    var askingDelete = false

    func deleteSelected(confirmed: Bool = false) {
        // Only unlocked elements go; committing when nothing can be removed
        // would push a history entry identical to the previous one. A
        // refusal is felt, as on the Android twin, rather than silent.
        let ids = Set(selectedElements.filter { !$0.locked }.map(\.id))
        guard !ids.isEmpty else {
            if !selection.isEmpty { buzz(.reject) }
            return
        }
        // The one exception to never asking: a position lock was set on
        // purpose, by someone, often a template's author.
        if !confirmed && selectedElements.contains(where: { ElementLock.mode(of: $0) == .position }) {
            askingDelete = true
            return
        }
        askingDelete = false
        // What is left of a cropped group keeps its crop where it shows.
        applyToPage { page in
            page.elements = GraphicClip.regrouped(before: page.elements, after: page.elements.filter { !ids.contains($0.id) })
        }
        selection.subtract(ids)   // anything locked stays selected, visibly
        // The Android twin's words, so both phones say the same.
        announce(ids.count == 1 ? tr("Deleted") : trn("Deleted %d thing|Deleted %d things", ids.count))
    }

    func duplicateSelected() {
        // Part of a cropped group crops as it showed: its crop put on the
        // frame of the part copied (GraphicClip.copied).
        let copies = Copies.of(GraphicClip.copied(page.elements, selectedElements.filter { !$0.locked }), offset: 24)
        guard !copies.isEmpty else { return }
        applyToPage { $0.elements.append(contentsOf: copies) }
        selection = Set(copies.map(\.id))
    }


    // MARK: clipboard

    var hasClipboard: Bool { !clipboard.isEmpty || ElementClipboard.hasContent() }

    /// Whether the hold menu offers Paste: elements copied here or in
    /// another design, or a picture another app left — as on the Android
    /// twin, words from another app are not offered there.
    var canPasteAtFinger: Bool {
        !clipboard.isEmpty || UIPasteboard.general.contains(pasteboardTypes: [ElementClipboard.type])
            || UIPasteboard.general.hasImages
    }

    /// Commands that move elements ignore locked ones, so the UI must gate on
    /// the unlocked subset or it offers controls that quietly do nothing.
    var unlockedSelectionCount: Int { selectedElements.filter { !$0.locked }.count }
    /// The same for what moves, sizes and turns: a position lock counts as
    /// locked here (see ElementLock), so align, distribute, tidy, nudge and
    /// the Position numbers are offered only for what they would move.
    var movableSelectionCount: Int { selectedElements.filter { !$0.holdsPlace }.count }
    /// Grouping moves nothing, so a position lock groups, as on the Android
    /// twin; only a whole lock keeps an element out.
    var canGroup: Bool { unlockedSelectionCount >= 2 }

    // MARK: colour for a multi-selection

    /// Whether anything selected takes a colour: an unlocked text, line or
    /// shape. Photos and stickers keep their own.
    var selectionTakesColour: Bool {
        selectedElements.contains { !$0.locked && [.text, .line, .shape].contains($0.type) }
    }

    /// Whether anything selected takes a gradient: text, or a shape that is
    /// not a drawn stroke. A line is one colour only.
    var selectionTakesGradient: Bool {
        selectedElements.contains { !$0.locked && Self.takesGradient($0) }
    }

    private static func takesGradient(_ el: Element) -> Bool {
        el.type == .text || (el.type == .shape && !Freehand.isStroke(el))
    }

    /// One colour for everything selected, as the Android twin recolours a
    /// multi-selection: text takes it as its colour (a gradient on its
    /// letters cleared), a line as its colour, a drawn stroke as its ink,
    /// any other shape as a solid fill. One step — and none when nothing
    /// would change.
    func recolourSelection(_ hex: String) {
        let targets = selectedElements.filter { !$0.locked }
        guard targets.contains(where: { Self.recoloured($0, to: hex) != $0 }) else { return }
        updateSelected { $0 = Self.recoloured($0, to: hex) }
    }

    /// A brand colour tapped in the Add sheet's Brand tab — the rule both
    /// phones keep (the Android twin's DesignStore.paintBrandColour): what
    /// is selected recoloured, as one step (recolourSelection); with
    /// nothing selected, the page's background (setBackground, which a
    /// locked page refuses). Nothing is recorded when nothing would change.
    func paintBrandColour(_ hex: String) {
        if selection.isEmpty {
            setBackground(.color(hex))
        } else {
            recolourSelection(hex)
        }
    }

    /// The same, live, for the colour wheel; the sheet commits when it closes.
    func recolourSelectionTransient(_ hex: String) {
        updateSelectedTransient { $0 = Self.recoloured($0, to: hex) }
    }

    /// A gradient for everything selected that takes one: a shape's fill,
    /// a text's letters. One step, or none when nothing would change.
    func recolourSelection(gradient paint: Paint) {
        let targets = selectedElements.filter { !$0.locked }
        guard targets.contains(where: { Self.withGradient($0, paint) != $0 }) else { return }
        updateSelected { $0 = Self.withGradient($0, paint) }
    }

    /// One colour of the selection painted `to`, wherever the selection
    /// uses it (see ColourSwap), as one step.
    func swapSelectionColour(from: String, to: String) {
        swapSelectionColourTransient(from: from, to: to)
        commit()
    }

    /// The same, live, for the colour wheel: each tick swaps from the
    /// selection as it was when the step opened, so a drag that passes
    /// through another of its colours never takes that one along. The sheet
    /// commits when the target changes or it closes.
    func swapSelectionColourTransient(from: String, to: String) {
        beginGesture()
        guard let snapshot = pending?.design, snapshot.pages.indices.contains(pageIndex) else { return }
        let before = snapshot.pages[pageIndex]
        for i in design.pages[pageIndex].elements.indices {
            let el = design.pages[pageIndex].elements[i]
            guard selection.contains(el.id), ColourSwap.takesSwap(el),
                  let was = before.elements.first(where: { $0.id == el.id }) else { continue }
            design.pages[pageIndex].elements[i] = ColourSwap.swapped([was], from: from, to: to)[0]
        }
    }

    /// Change all: `from` painted `to` on every element of every page that
    /// uses it and is not locked, as one step with an Undo. Returns how many
    /// elements changed.
    @discardableResult
    func swapColourEverywhere(from: String, to: String) -> Int {
        commit()
        let total = ColourSwap.count(design, from: from)
        guard total > 0 else { return 0 }
        apply { design in
            for p in design.pages.indices {
                for i in design.pages[p].elements.indices where ColourSwap.takesChangeAll(design.pages[p].elements[i]) {
                    design.pages[p].elements[i] = ColourSwap.swapped([design.pages[p].elements[i]], from: from, to: to)[0]
                }
            }
        }
        buzz(.confirm)
        announce(Self.changedAllNote(total))
        return total
    }

    /// What Change all says it did.
    static func changedAllNote(_ count: Int) -> String {
        trn("Changed the colour of %d element|Changed the colour of %d elements", count)
    }

    /// `el` in colour `hex`, by what it is; unchanged when it already is —
    /// compared ignoring case — or takes no colour.
    static func recoloured(_ el: Element, to hex: String) -> Element {
        func same(_ colour: String?) -> Bool { colour?.lowercased() == hex.lowercased() }
        var e = el
        switch el.type {
        case .text:
            if !(same(el.color) && el.textFill == nil) { e.color = hex; e.textFill = nil }
        case .line:
            if !same(el.color) { e.color = hex }
        case .shape where Freehand.inksOnly(el):
            // A drawing's ink, or an SVG's line or outline part's.
            if !same(el.stroke) { e.stroke = hex }
        case .shape:
            if !(el.fill?.kind == "solid" && same(el.fill?.color)) { e.fill = .solid(hex) }
        default:
            break
        }
        return e
    }

    /// `el` with gradient `paint` where it takes one.
    static func withGradient(_ el: Element, _ paint: Paint) -> Element {
        guard takesGradient(el) else { return el }
        var e = el
        if el.type == .text {
            // Letters draw a gradient or a photo and nothing else: a pattern
            // picked for a mixed selection is the shapes', and on the text
            // would be saved and never shown.
            guard paint.kind == "gradient" || paint.isPhoto else { return el }
            e.textFill = paint
        } else {
            e.fill = paint
        }
        return e
    }
    var canDistribute: Bool { movableSelectionCount >= 3 }

    func copySelected() {
        // Part of a cropped group goes with its crop put on the frame of the
        // part copied (GraphicClip.copied), so it pastes showing the same.
        let selected = GraphicClip.copied(page.elements, selectedElements)
        guard !selected.isEmpty else { return }
        clipboard = selected
        clipboardPage = page.id
        clipboardFonts = CustomFonts.carried(selected, from: design)
        pastedOnto = nil
        pasteCount = 0
        ElementClipboard.write(selected, sourcePage: page.id, fonts: clipboardFonts)
        buzz(.tick)
        announce(selected.count == 1 ? tr("Copied") : trn("Copied %d thing|Copied %d things", selected.count), undoable: false)
    }

    func cutSelected() {
        // Cut takes exactly what it removes, so a locked element is never
        // both left behind and on the clipboard. A cut is a move by way of
        // the clipboard, so, as with Move to page, a position lock stays
        // too, as on the Android twin (its DesignStore.cutSelected).
        let taken = selectedElements.filter { !$0.holdsPlace }
        guard !taken.isEmpty else {
            if !selection.isEmpty { buzz(.reject) }
            return
        }
        // Part of a cropped group that showed nothing goes with no copy
        // (GraphicClip.copied); with nothing to copy, the clipboard is kept.
        let removable = GraphicClip.copied(page.elements, taken)
        if !removable.isEmpty {
            clipboard = removable
            clipboardPage = page.id
            clipboardFonts = CustomFonts.carried(removable, from: design)
            pastedOnto = nil
            pasteCount = 0
            ElementClipboard.write(removable, sourcePage: page.id, fonts: clipboardFonts)
        }
        let ids = Set(taken.map(\.id))
        // What stays of a cropped group keeps showing what it showed, as
        // with Delete.
        applyToPage { page in
            page.elements = GraphicClip.regrouped(before: page.elements, after: page.elements.filter { !ids.contains($0.id) })
        }
        selection.subtract(ids)
        announce(ids.count == 1 ? tr("Cut") : trn("Cut %d thing|Cut %d things", ids.count))
    }

    /// Paste; with `point`, on the page in page units — the menu a hold on
    /// the empty page brings up — what was copied is put down centred there
    /// and kept on the page (HoldMenu.placed), in the paste's one step.
    /// `plain`, Paste as plain text: the words on the pasteboard as they
    /// read, a text box, whatever else came with them.
    func paste(at point: CGPoint? = nil, plain: Bool = false) {
        // Nothing is pasted onto a locked page.
        guard !refusesLockedPage() else { return }
        if plain {
            guard var words = ElementClipboard.foreign(designWidth: pageWidth, plain: true) else {
                buzz(.reject)
                announce(tr("Nothing to paste"), undoable: false)
                return
            }
            if let point {
                let box = Geometry.aabb(words)
                let at = HoldMenu.placed(box.size, at: point, page: pageSize)
                words.x += Double(at.x - box.minX)
                words.y += Double(at.y - box.minY)
            }
            add(words)
            return
        }
        // Our own copy first; otherwise whatever another app left: a
        // picture, or some text.
        if clipboard.isEmpty {
            if let mine = ElementClipboard.read() {
                clipboard = mine
                clipboardPage = ElementClipboard.sourcePage()
                clipboardFonts = ElementClipboard.fonts()
                pastedOnto = nil
                pasteCount = 0
            } else if var stranger = ElementClipboard.foreign(designWidth: pageWidth) {
                // A picture over a frame, or a photo, selected goes into it.
                if pasteIntoFrame([stranger], foreign: true, at: point) { return }
                if let point {
                    let at = HoldMenu.placed(Geometry.aabb(stranger).size, at: point, page: pageSize)
                    let box = Geometry.aabb(stranger)
                    stranger.x += Double(at.x - box.minX)
                    stranger.y += Double(at.y - box.minY)
                }
                add(stranger)
                return
            }
        }
        guard !clipboard.isEmpty else {
            // Said, as the Android twin says it: from the keyboard there is
            // no greyed-out menu item to tell you.
            buzz(.reject)
            announce(UIPasteboard.general.hasImages ? tr("Couldn't paste that picture") : tr("Nothing to paste"),
                     undoable: false)
            return
        }
        // One copied photo, with a frame selected, fills the frame.
        if pasteIntoFrame(clipboard, foreign: false, at: point) { return }
        // Each page counts its own pastes: the first onto a page other than
        // the copy's lands in place, and only a repeat there steps.
        if pastedOnto != page.id {
            pastedOnto = page.id
            pasteCount = 0
        }
        pasteCount += 1
        // Copies arrive unlocked: locked is a property of the original, and a
        // pasted element the user cannot move, edit or delete is a dead end.
        let offset = Copies.pasteOffset(nth: pasteCount, sourcePage: clipboardPage, onto: page,
                                        copied: clipboard.map(\.id))
        var copies = Copies.of(clipboard, offset: offset)
        if let point, !copies.isEmpty {
            let box = Geometry.union(copies.map(Geometry.aabb))
            let at = HoldMenu.placed(box.size, at: point, page: pageSize)
            let dx = Double(at.x - box.minX), dy = Double(at.y - box.minY)
            copies = copies.map { el in
                var moved = el
                moved.x += dx
                moved.y += dy
                return moved
            }
        }
        let fonts = clipboardFonts
        // The fonts of your own they brought recorded with them, one step.
        apply { design in
            design.pages[self.pageIndex].elements.append(contentsOf: copies)
            design = CustomFonts.adopting(fonts, into: design)
        }
        selection = Set(copies.map(\.id))
    }

    /// A paste of `payload` that goes into a frame rather than onto the page
    /// (Copies.pasteTarget): into the one frame or grid cell selected — or,
    /// from the hold menu at `point`, the frame under the finger — or in
    /// place of the picture of the one photo selected, for a picture from
    /// another app. One undo step, said with Undo; the frame stays
    /// selected. False when the paste is to be added as ever.
    private func pasteIntoFrame(_ payload: [Element], foreign: Bool, at point: CGPoint?) -> Bool {
        let under = point.flatMap { PhotoFrames.target(at: $0, in: page.elements, excluding: nil) }
        let chosen = under.map { [$0] } ?? selectedElements
        let target = Copies.pasteTarget(chosen, among: page.elements, payload: payload, foreign: foreign)
        guard let photo = payload.first else { return false }
        switch target {
        case .add:
            return false
        case .fill(let id):
            applyToPage { page in
                if let i = page.elements.firstIndex(where: { $0.id == id }) {
                    page.elements[i] = Copies.filled(page.elements[i], with: photo, foreign: foreign)
                }
            }
            selection = [id]
            announce(tr("Pasted into the frame"))
        case .replace(let id):
            guard let src = photo.src, replacePicture(id, with: src) else { return false }
            selection = [id]
        }
        buzz(.confirm)
        return true
    }

    /// Where a still hold on the empty page brought up its menu, in page
    /// units on the page being worked; nil when the menu is not up. View
    /// state only.
    var holdMenuAt: CGPoint?

    /// The hold menu's Add text here: the default text box — "Your text
    /// here" (HoldMenu.words), 6% of the page's width in type, 72% of it
    /// wide — centred on `point` and kept on the page, typed into at once
    /// with its words chosen, so the first key replaces them, as on the
    /// Android twin. Putting it there is a step of its own, as Add text's
    /// is, so Undo while typing takes back what was typed and leaves the box
    /// open with its words; left as it is, it stays, as that one step.
    func addText(at point: CGPoint) {
        guard !refusesLockedPage() else { return }
        // Typing, or a step left open, is closed first, as its own.
        endTextEdit()
        commit()
        var el = Element.text(HoldMenu.words, fontSize: (pageWidth * 0.06).rounded(), w: (pageWidth * 0.72).rounded())
        el.fontWeight = 400
        el.h = FontLibrary.layoutHeight(for: el)
        let at = HoldMenu.placed(CGSize(width: el.w, height: el.h), at: point, page: pageSize)
        el.x = Double(at.x)
        el.y = Double(at.y)
        beginGesture()
        design.pages[pageIndex].elements.append(el)
        commit()
        // Just added (freshTexts): the field opens with its words chosen.
        markFresh([el])
        startTyping(el.id)
    }

    /// The T key's text box: Add text's — "Your text here", 6% of the
    /// page's width in type, 72% of it wide — centred and selected, not
    /// typed into, and onto the next unlocked page when this one is locked,
    /// as Add text puts it. The Android twin's T is the same.
    func addTextBox() {
        guard landsOnUnlockedPage() else { return }
        var el = Element.text(HoldMenu.words, fontSize: (pageWidth * 0.06).rounded(), w: (pageWidth * 0.72).rounded())
        el.fontWeight = 400
        el.h = FontLibrary.layoutHeight(for: el)
        addText(el)
    }

    /// Everything on this page that can be selected; nothing on a locked
    /// page, which is said instead.
    func selectAll() {
        endTextEdit()
        guard !refusesLockedPage() else { return }
        selection = Set(page.elements.filter { !$0.locked && !$0.isHidden }.map(\.id))
    }

    /// Tab and Shift-Tab: the next shown thing in front of the selection,
    /// or the one behind it, a group as one (Layers.neighbour), brought
    /// into view. Nothing on a locked page is selected: the key is said,
    /// with Unlock.
    func selectNeighbour(forward: Bool) {
        endTextEdit()
        guard !refusesLockedPage() else { return }
        let next = Layers.neighbour(of: selection, in: page.elements, forward: forward)
        guard !next.isEmpty else { return }
        selection = next
        revealSelection()
    }

    /// Rubber-band selection: everything the rectangle touches but what is
    /// locked, with sticky groups expanded so a band across one member takes
    /// the whole group.
    func select(within rect: CGRect) {
        select(within: rect, startedOn: nil)
    }

    /// The same for a band drawn from the backdrop `startedOn`, which it
    /// leaves out unless nothing else is caught (CanvasGestures.bandCaught).
    func select(within rect: CGRect, startedOn: String?) {
        endTextEdit()
        guard !isPageLocked else { return }
        selection = CanvasGestures.bandCaught(page.elements, rect: rect, startedOn: startedOn)
    }

    /// Write back a set of elements mid-gesture, matched by id. Used by the
    /// group transforms, which compute every member from the grab-time
    /// originals rather than mutating in place.
    func replaceTransient(_ updated: [Element]) {
        beginGesture()
        defer { Connectors.resolve(&design.pages[pageIndex]) }
        let byId = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        for i in design.pages[pageIndex].elements.indices {
            if let e = byId[design.pages[pageIndex].elements[i].id] {
                design.pages[pageIndex].elements[i] = e
            }
        }
    }

    // MARK: grouping
    // Sticky multi-selection rather than nested transforms: selecting any
    // member selects its whole outermost group (see select(_:additive:)),
    // and a tap on it again goes a level in (selectMember).

    /// True when every selected element already shares one group.
    var selectionIsGrouped: Bool {
        let selected = selectedElements
        guard selected.count > 1, let group = selected.first?.group else { return false }
        return selected.allSatisfy { $0.group == group }
    }

    func groupSelected() {
        guard unlockedSelectionCount >= 2 else { return }
        buzz(.grouped)
        let gid = UID.make("grp")
        let ids = Set(selectedElements.filter { !$0.locked }.map(\.id))
        // A group among them is kept inside the new one (Groups.grouped).
        applyToPage { page in
            page.elements = Groups.grouped(page.elements, ids: ids, into: gid)
        }
    }

    /// One level at a time: each selected element leaves its outermost
    /// group, and a group inside it comes back as it was (Groups.ungrouped).
    func ungroupSelected() {
        guard selectedElements.contains(where: { $0.group != nil }) else { return }
        buzz(.grouped)
        let ids = selection
        applyToPage { page in
            page.elements = Groups.ungrouped(page.elements, ids: ids)
        }
    }

    enum ZMove { case front, forward, backward, back }

    /// Forward and Backward step past the next thing the selection
    /// overlaps, a group one layer (Layers.stepped); To front and To back
    /// keep a group's run whole too. One step — or, already at the front or
    /// the back, nothing, felt and said.
    func reorderSelected(_ move: ZMove) {
        let ids = selection
        guard !ids.isEmpty else { return }
        let forward = move == .front || move == .forward
        let before = page.elements
        let after: [Element]
        switch move {
        case .front, .back: after = Layers.sentToEnd(before, ids: ids, front: forward)
        case .forward, .backward: after = Layers.stepped(before, ids: ids, forward: forward)
        }
        guard after.map(\.id) != before.map(\.id) else {
            buzz(.reject)
            announce(forward ? tr("Already at the front") : tr("Already at the back"), undoable: false)
            return
        }
        applyToPage { $0.elements = after }
    }

    enum AlignMode { case left, centerX, right, top, centerY, bottom }

    /// Whether Position's align buttons line the selection up with the page
    /// rather than with each other: one thing on its own, or one sticky
    /// group, which lines up as a single box.
    var alignsToPage: Bool { movableSelectionCount <= 1 || selectionIsGrouped }

    func alignSelected(_ mode: AlignMode) {
        let selected = selectedElements.filter { !$0.holdsPlace }
        guard !selected.isEmpty else { return }
        let pageBox = CGRect(origin: .zero, size: pageSize)
        // One sticky group lines up with the page as one box, every member
        // moved by the same offset: aligned one by one, a grid's cells would
        // all pile up against the same edge.
        if selectionIsGrouped {
            let shift = Self.alignShift(Geometry.union(selected.map(Geometry.aabb)), to: pageBox, mode)
            let ids = Set(selected.map(\.id))
            applyToPage { page in
                for i in page.elements.indices where ids.contains(page.elements[i].id) {
                    page.elements[i].x += shift.x
                    page.elements[i].y += shift.y
                }
            }
            return
        }
        let bounds: CGRect = selected.count == 1 ? pageBox : Geometry.union(selected.map(Geometry.aabb))
        applyToPage { page in
            for i in page.elements.indices where self.selection.contains(page.elements[i].id) && !page.elements[i].holdsPlace {
                let shift = Self.alignShift(Geometry.aabb(page.elements[i]), to: bounds, mode)
                page.elements[i].x += shift.x
                page.elements[i].y += shift.y
            }
        }
    }

    /// How far `box` moves to line up with `bounds` by `mode`.
    private static func alignShift(_ box: CGRect, to bounds: CGRect, _ mode: AlignMode) -> CGPoint {
        switch mode {
        case .left: return CGPoint(x: bounds.minX - box.minX, y: 0)
        case .centerX: return CGPoint(x: bounds.midX - box.midX, y: 0)
        case .right: return CGPoint(x: bounds.maxX - box.maxX, y: 0)
        case .top: return CGPoint(x: 0, y: bounds.minY - box.minY)
        case .centerY: return CGPoint(x: 0, y: bounds.midY - box.midY)
        case .bottom: return CGPoint(x: 0, y: bounds.maxY - box.maxY)
        }
    }

    /// The selection's unlocked things centred on the page, as one step: one
    /// thing by its own turned bounds, several by the box round them, so they
    /// keep their places relative to each other — the Android twin's
    /// centreOnPage.
    func centreOnPage() {
        let members = selectedElements.filter { !$0.holdsPlace }
        guard !members.isEmpty else { return }
        let box = Geometry.union(members.map(Geometry.aabb))
        let dx = (pageWidth - box.width) / 2 - box.minX
        let dy = (pageHeight - box.height) / 2 - box.minY
        let ids = Set(members.map(\.id))
        applyToPage { page in
            for i in page.elements.indices where ids.contains(page.elements[i].id) {
                page.elements[i].x += dx
                page.elements[i].y += dy
            }
        }
    }

    /// Tidy the unlocked selection into a row, column or grid, one undo step.
    /// The gap is `gap`, or with none a fiftieth of the page's shorter side
    /// (Geometry.defaultTidyGap): visible, not loose.
    func tidySelected(_ mode: Geometry.TidyMode, gap: Double? = .none) {
        let members = selectedElements.filter { !$0.holdsPlace }
        guard members.count >= 2 else { return }
        let gap = max(0, gap ?? Geometry.defaultTidyGap(page: pageSize))
        let tidied = Geometry.tidy(members, mode: mode, gap: gap)
        applyToPage { page in
            let byId = Dictionary(uniqueKeysWithValues: tidied.map { ($0.id, $0) })
            for i in page.elements.indices {
                if let e = byId[page.elements[i].id] { page.elements[i] = e }
            }
        }
    }

    /// Move the unlocked selection by a step, as one undo step. Arrow keys,
    /// VoiceOver actions and the numeric fields all come through here.
    func nudgeSelected(dx: Double, dy: Double) {
        guard dx != 0 || dy != 0, movableSelectionCount > 0 else { return }
        updateSelectedPlacement { $0.x += dx; $0.y += dy }
    }

    /// A step of a held nudge arrow, into the step the hold opened: the
    /// arrow's whole hold is one undo step, closed by commit() as it lifts.
    func nudgeSelectedTransient(dx: Double, dy: Double) {
        guard dx != 0 || dy != 0, movableSelectionCount > 0 else { return }
        beginGesture()
        for i in design.pages[pageIndex].elements.indices
        where selection.contains(design.pages[pageIndex].elements[i].id)
            && !design.pages[pageIndex].elements[i].holdsPlace {
            design.pages[pageIndex].elements[i].x += dx
            design.pages[pageIndex].elements[i].y += dy
        }
        Connectors.resolve(&design.pages[pageIndex])
    }

    /// Mutate where every selected element free to move sits, its size or
    /// its turn, as one undo step: what the Position numbers and a nudge
    /// change. A position lock keeps them, as a whole lock does.
    func updateSelectedPlacement(_ mutate: (inout Element) -> Void) {
        guard movableSelectionCount > 0 else { return }
        applyToPage { page in
            for i in page.elements.indices
            where self.selection.contains(page.elements[i].id) && !page.elements[i].holdsPlace {
                mutate(&page.elements[i])
            }
        }
    }

    /// The selection's box, for the numeric fields; nil when nothing is
    /// selected.
    var selectionBox: CGRect? {
        let members = selectedElements
        return members.isEmpty ? nil : Geometry.union(members.map(Geometry.aabb))
    }

    /// Resize the whole selection so its box becomes `to`, one undo step.
    func setSelectionBox(_ to: CGRect) {
        let members = selectedElements.filter { !$0.holdsPlace }
        guard let from = selectionBox, !members.isEmpty, to.width >= 1, to.height >= 1 else { return }
        let scaled = from.size == to.size
            ? members.map { el in var e = el; e.x += to.minX - from.minX; e.y += to.minY - from.minY; return e }
            : Geometry.scale(members, from: from, to: to)
        applyToPage { page in
            let byId = Dictionary(uniqueKeysWithValues: scaled.map { ($0.id, $0) })
            for i in page.elements.indices {
                if let e = byId[page.elements[i].id] { page.elements[i] = e }
            }
        }
    }

    /// The outermost group the selection is the whole of, when every member
    /// can move; nil for anything else. A group with something locked or
    /// held in place keeps the upright box and is never turned as one, so
    /// no groupTurn is written for it — the Android twin's
    /// DesignStore.groupFrame keeps the same rule.
    private var movableWholeGroup: String? {
        guard let group = Groups.whole(page.elements, selection: selection),
              !selectedElements.contains(where: \.holdsPlace) else { return nil }
        return group
    }

    /// The selection's frame when it is a whole group turned as one
    /// (Groups.turn): turned with it, tight round it (Geometry.groupFrame).
    /// Nil for anything else, which keeps the upright box.
    var turnedGroupFrame: Geometry.GroupFrame? {
        guard movableWholeGroup != nil else { return nil }
        let turn = Groups.turn(page.elements, selection: selection)
        guard turn != 0 else { return nil }
        return Geometry.groupFrame(selectedElements, angle: turn)
    }

    /// How far the selected group is turned as a whole (groupTurn), 0 when
    /// upright; nil when the selection is not one whole group whose members
    /// can all move.
    var selectedGroupTurn: Double? {
        guard movableWholeGroup != nil else { return nil }
        return Groups.turn(page.elements, selection: selection)
    }

    /// Position's Turn for a selected group: the group turned about its
    /// frame's middle until it stands at `degrees`, which its members keep
    /// as their groupTurn — so Turn to 0 straightens it. One undo step.
    func setGroupTurn(_ degrees: Double) {
        guard let group = movableWholeGroup else { return }
        let current = Groups.turn(page.elements, selection: selection)
        let target = Groups.normalisedTurn(degrees)
        let members = selectedElements
        guard !members.isEmpty, target != current else { return }
        let middle = Geometry.groupFrame(members, angle: current).center
        let turned = Geometry.rotate(members, around: middle, by: target - current)
        let byId = Dictionary(uniqueKeysWithValues: turned.map { ($0.id, $0) })
        applyToPage { page in
            for i in page.elements.indices {
                if let e = byId[page.elements[i].id] { page.elements[i] = e }
            }
            page.elements = Groups.turned(page.elements, group: group, to: target)
        }
    }

    /// A whole group scaled evenly by `factor` about its frame's middle, in
    /// the frame's own axes — Position's Width and Height for it, turned or
    /// upright — one undo step. The Android twin's DesignStore.scaleGroup.
    func scaleGroup(by factor: Double) {
        guard let turn = selectedGroupTurn, factor > 0, factor.isFinite, factor != 1 else { return }
        let members = selectedElements
        let frame = Geometry.groupFrame(members, angle: turn)
        let size = CGSize(width: frame.size.width * factor, height: frame.size.height * factor)
        let to = CGRect(x: frame.center.x - size.width / 2, y: frame.center.y - size.height / 2,
                        width: size.width, height: size.height)
        let scaled = Geometry.scale(members, frame: frame, to: to)
        let byId = Dictionary(uniqueKeysWithValues: scaled.map { ($0.id, $0) })
        applyToPage { page in
            for i in page.elements.indices {
                if let e = byId[page.elements[i].id] { page.elements[i] = e }
            }
        }
    }

    /// Turn the whole selection about its centre by `degrees`, one undo step;
    /// a whole group, about its frame's middle, its turn kept (setGroupTurn).
    func rotateSelection(by degrees: Double) {
        if let turn = selectedGroupTurn {
            setGroupTurn(turn + degrees)
            return
        }
        let members = selectedElements.filter { !$0.holdsPlace }
        guard let box = selectionBox, !members.isEmpty, degrees != 0 else { return }
        let turned = Geometry.rotate(members, around: CGPoint(x: box.midX, y: box.midY), by: degrees)
        applyToPage { page in
            let byId = Dictionary(uniqueKeysWithValues: turned.map { ($0.id, $0) })
            for i in page.elements.indices {
                if let e = byId[page.elements[i].id] { page.elements[i] = e }
            }
        }
    }

    /// Close a text box onto its text: no slack below, no slack beside.
    func shrinkWrapText() {
        updateSelected { el in
            guard el.type == .text else { return }
            if el.fitText == true { el.fontSize = FontLibrary.fittingFontSize(for: el) }
            el.fitText = nil
            el.vAlign = nil
            el.w = max(8, min(el.w, FontLibrary.lineWidth(for: el) + 2))
            el.h = FontLibrary.measuredHeight(for: el)
        }
    }

    enum DistributeAxis { case horizontal, vertical }

    /// Even spacing between the outermost two elements (needs 3+).
    func distributeSelected(_ axis: DistributeAxis) {
        let selected = selectedElements.filter { !$0.holdsPlace }
        guard selected.count >= 3 else { return }
        let horizontal = axis == .horizontal
        var boxes = selected.map { (id: $0.id, box: Geometry.aabb($0)) }
        boxes.sort { horizontal ? $0.box.minX < $1.box.minX : $0.box.minY < $1.box.minY }

        // Span must come from the selection's true outer bounds. Sorting by
        // leading edge does not put the element with the greatest *trailing*
        // edge last, so last.maxX can fall short of the real extent and drag
        // the outermost element inward.
        let bounds = Geometry.union(selected.map(Geometry.aabb))
        let span = horizontal ? bounds.width : bounds.height
        let total = boxes.reduce(0.0) { $0 + (horizontal ? $1.box.width : $1.box.height) }
        // A negative gap (parts summing wider than their bounds) evenly
        // overlaps them, which is what Figma and Illustrator do; clamping to
        // zero would instead push the run past the bounds it must preserve.
        let gap = (span - total) / Double(boxes.count - 1)

        applyToPage { page in
            var cursor: Double = horizontal ? bounds.minX : bounds.minY
            for entry in boxes {
                if let i = page.elements.firstIndex(where: { $0.id == entry.id }) {
                    let start = horizontal ? entry.box.minX : entry.box.minY
                    if horizontal { page.elements[i].x += cursor - start }
                    else { page.elements[i].y += cursor - start }
                }
                cursor += (horizontal ? entry.box.width : entry.box.height) + gap
            }
        }
    }

    // MARK: announcements

    /// A one-line description of something just done that undo can reverse,
    /// for the toast to show. Cleared by the view once shown.
    var announcement: String?
    /// Whether that toast offers Undo. Not for a refusal, or for something
    /// still under way: there Undo would take back whatever was done last,
    /// which has nothing to do with the message.
    var announcementUndoes = true
    /// The locked page that toast offers to unlock (refusesLockedPage);
    /// nil for any other toast.
    var announcementUnlocks: String?

    /// Something just happened that a first-timer might want a word about.
    /// The editor hands it to TipEngine, which decides whether to say it.
    var tipEvent: TipEvent?

    /// How far Apply colours to page has turned the selected photo's
    /// palette (PhotoColours.turned): one more each tap, back to 0 when the
    /// selection changes. Editor state only — never saved.
    @ObservationIgnored var photoColourTurn = 0
    /// A change worth feeling; the editor turns it into haptics.
    var haptic = HapticEvent(kind: .undo, serial: 0)
    /// True while a rotation drag sits on a 45° snap.
    var rotationSnapped = false
    /// True while a move sits at an equal gap — between two neighbours, or
    /// matching a gap already there — or a resize at another's size: what
    /// the snap haptic is felt for.
    var spacingSnapped = false
    /// The equal gaps a move has landed on, bracketed with their widths
    /// (Geometry.equalGapPairs), and the boxes a resize has matched the size
    /// of, marked "=" (Geometry.matchingSize). Nothing of the design.
    var gapMarks: [Geometry.GapPair] = []
    var sizeMarks: [Geometry.SizeMark] = []
    /// The pen, while drawing mode is on: strokes become shape elements.
    var drawing: Freehand.Tool? {
        didSet {
            if let drawing { lastPen = drawing }
            // Put down — Done, the pencil, another tool taken up — the
            // session's strokes become one drawing.
            if oldValue != nil && drawing == nil { groupDrawnStrokes() }
            if oldValue == nil && drawing != nil { sessionStrokes = [] }
        }
    }
    /// The last pen used, so the next drawing session picks it up again.
    @ObservationIgnored private var lastPen = Freehand.Tool()
    /// The strokes drawn since the pen was taken up, and the pieces left of
    /// them by the eraser: what is grouped when it is put down.
    @ObservationIgnored private var sessionStrokes: [String] = []
    /// The history version just after the session's last stroke or erase:
    /// while it is still the newest step, the grouping is folded into it.
    @ObservationIgnored private var sessionStepAt = -1
    /// The photo in crop mode, and the size of its picture — see
    /// CropMode.swift. Crop mode is one open step: everything done in it is
    /// live, Done keeps it as a single Undo, and Cancel throws it away.
    var cropping: CropSession?
    /// True while the crop bar's straighten dial is held: the thirds stay
    /// up on the frame, as they do under a finger. View state only.
    var cropDialHeld = false
    /// A graphic or a group being cropped — see GraphicCropMode.swift. One
    /// open step, as a photo's crop is.
    var graphicCropping: GraphicCropSession?
    /// The image being erased from, while the eraser is out, and the
    /// strokes painted over it so far, in page units.
    var erasing: String?
    var eraserStrokes: [[CGPoint]] = []
    var eraserWidth: Double = 40
    var eraserBusy = false
    /// The photo being brushed — erased and restored, or blurred or
    /// pixelated in part — and how (see BrushMode.swift).
    var brushing: BrushSession?
    /// The element whose motion path Animate's Create is recording, and
    /// whether a path has been recorded yet (see MotionEditing.swift).
    var motionRecording: MotionRecording?
    /// The hold menu's Animate, asking the editor for Page animations.
    var asksPageAnimation = false

    func beginErasing(_ id: String) {
        if element(id)?.locked == true {
            buzz(.reject)
            announce(tr("This photo is locked. Tap Unlock to edit it."), undoable: false)
            return
        }
        finishBrush()
        drawing = nil
        endTextEdit()
        selection = [id]
        erasing = id
        eraserStrokes = []
    }

    /// The selected strokes read as handwriting: one text element takes
    /// their place, at their size, with what the recogniser made of them.
    func strokesToText() {
        let strokes = selectedElements.filter(Freehand.isStroke)
        guard let rendered = Freehand.bitmap(of: strokes) else { return }
        let ids = Set(strokes.map(\.id))
        let index = pageIndex
        Task.detached(priority: .userInitiated) { [weak self] in
            let lines = TextRecognizer.lines(in: rendered.image)
            await MainActor.run {
                guard let self else { return }
                let text = lines.map(\.text).joined(separator: "\n")
                guard !text.isEmpty else { self.announce(tr("No words were recognised in the strokes"), undoable: false); return }
                let frame = rendered.frame
                let size = max(12, (frame.height / Double(max(lines.count, 1)) * 0.6).rounded())
                // The recognised words as they read, stars literal.
                var el = Element.text(RichText.escapeLiteral(text), fontSize: size, w: max(60, frame.width.rounded()))
                el.align = "left"
                el.x = frame.minX.rounded(); el.y = frame.minY.rounded()
                el.h = FontLibrary.layoutHeight(for: el)
                self.apply { d in
                    d.pages[index].elements.removeAll { ids.contains($0.id) }
                    d.pages[index].elements.append(el)
                }
                self.selection = [el.id]
                self.announce(tr("Handwriting became text — Undo keeps the strokes"))
            }
        }
    }

    func cancelErasing() {
        erasing = nil
        eraserStrokes = []
    }

    /// Fills the painted region from its surroundings, stores the result as
    /// a new picture and points the element at it — one undo step.
    func applyEraser() {
        guard let id = erasing, let el = element(id), !eraserStrokes.isEmpty,
              let image = PhotoLibrary.resolve(el.src) else { cancelErasing(); return }
        let strokes = eraserStrokes.map { stroke in
            stroke.map { ObjectEraser.imagePoint($0, element: el, imageSize: image.size) }
        }
        // The brush in image pixels: the page-unit width through the same
        // scale the picture is shown at.
        let width = ObjectEraser.brushPixels(eraserWidth, element: el, imageSize: image.size)
        eraserBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = ObjectEraser.erase(image, strokes: strokes, width: width)
            let hasAlpha = image.cgImage.map { $0.alphaInfo != .none && $0.alphaInfo != .noneSkipLast && $0.alphaInfo != .noneSkipFirst } ?? false
            let src = result.flatMap { hasAlpha ? MediaStore.storeTransparent($0) : MediaStore.storeOpaque($0) }
            await MainActor.run {
                guard let self else { return }
                self.eraserBusy = false
                // Cancelled, or another photo taken up, while it worked:
                // the result is dropped rather than written over the choice.
                guard self.erasing == id else { return }
                defer { self.cancelErasing() }
                guard let now = self.element(id) else {
                    self.buzz(.reject)
                    self.announce(tr("The photo is no longer on this page"), undoable: false)
                    return
                }
                // Locked meanwhile: kept as it is, and nothing said to have
                // been erased.
                guard !now.locked else { return }
                guard let src else {
                    self.buzz(.reject)
                    self.announce(tr("Nothing to erase there"), undoable: false)
                    return
                }
                self.selection = [id]
                // The inpainted copy is no longer the Cut out its mask's base
                // was the original of, so the base goes with the old picture;
                // the strokes, painted over the same picture, stay.
                self.updateSelected {
                    $0.src = src
                    $0.mask = ImageMask.withoutBase($0.mask)
                }
                self.buzz(.confirm)
                self.announce(tr("Erased — Undo brings it back"))
            }
        }
    }

    func buzz(_ kind: HapticEvent.Kind) {
        haptic = HapticEvent(kind: kind, serial: haptic.serial + 1)
    }

    func toggleDrawing() {
        if drawing == nil {
            // Nothing is drawn onto a locked page.
            guard !refusesLockedPage() else { return }
            finishBrush()
            endTextEdit()
            selection.removeAll()
            // The pen as it was last put away — ink, width and kind — for
            // as long as the editor is open, as on the Android twin.
            drawing = lastPen
        } else {
            drawing = nil
        }
    }

    /// A finished stroke in page units becomes one shape and one undo step;
    /// nothing is selected, so the next stroke starts clean.
    func finishStroke(_ points: [CGPoint]) {
        // The page under the pen may have been locked since it was taken up.
        guard !refusesLockedPage() else { return }
        if let tool = drawing, tool.pen == .eraser {
            if tool.eraseWhole {
                eraseStrokes(points, radius: Freehand.eraserRadius(tool))
            } else {
                eraseStrokesPartially(points, radius: Freehand.eraserRadius(tool))
            }
            return
        }
        guard let tool = drawing, let el = Freehand.element(points: points, tool: tool) else { return }
        add(el, centered: false)
        sessionStrokes.append(el.id)
        sessionStepAt = historyVersion
        selection.removeAll()
        if tipEvent == nil { tipEvent = .drewStroke }
        buzz(.stroke)
    }

    /// A stroke shape assist read as a shape (ShapeAssist): the clean line or
    /// shape in its place, one undo step, and part of the drawing the
    /// session's strokes are grouped into, as a stroke is.
    func finishSnappedStroke(_ snap: ShapeAssist.Snap) {
        guard !refusesLockedPage() else { return }
        guard let tool = drawing, let el = ShapeAssist.element(snap, tool: tool) else { return }
        add(el, centered: false)
        sessionStrokes.append(el.id)
        sessionStepAt = historyVersion
        selection.removeAll()
        buzz(.stroke)
    }

    /// The strokes an eraser swept over go, all of them one undo step.
    func eraseStrokes(_ points: [CGPoint], radius: Double) {
        let gone = Freehand.erased(page.elements, path: points, radius: radius)
        guard !gone.isEmpty else { return }
        applyToPage { $0.elements.removeAll { gone.contains($0.id) } }
        sessionStepAt = historyVersion
        selection.removeAll()
        buzz(.stroke)
        announce(gone.count == 1 ? tr("Erased a stroke") : trn("Erased %d stroke|Erased %d strokes", gone.count))
    }

    /// The part of each stroke an eraser swept over goes, what is left of
    /// it staying where it was in the stack: one undo step per drag.
    func eraseStrokesPartially(_ points: [CGPoint], radius: Double) {
        let cuts = Freehand.erasedPartially(page.elements, path: points, radius: radius)
        guard !cuts.isEmpty else { return }
        var piecesOf: [String: [Element]] = [:]
        for cut in cuts { piecesOf[cut.id] = cut.pieces }
        applyToPage { page in
            page.elements = page.elements.flatMap { el -> [Element] in piecesOf[el.id] ?? [el] }
        }
        // What is left of this session's strokes is still this session's.
        sessionStrokes = sessionStrokes.flatMap { id -> [String] in piecesOf[id].map { $0.map(\.id) } ?? [id] }
        sessionStepAt = historyVersion
        selection.removeAll()
        buzz(.stroke)
        // Said, as the Android twin says it, for anyone not watching the page.
        announce(cuts.count == 1 ? tr("Erased part of a stroke")
                 : trn("Erased part of %d stroke|Erased part of %d strokes", cuts.count))
    }

    /// The strokes drawn since the pen was taken up, when two or more are
    /// still on the page, as one drawing: one group, named Drawing. Part of
    /// the last stroke's step while that is still the newest step, so one
    /// Undo still takes back only that stroke; after an Undo, or anything
    /// else since, a step of its own, so the grouping is never lost to a
    /// Redo — as the Android twin keeps a session together.
    private func groupDrawnStrokes() {
        let ids = Set(sessionStrokes)
        sessionStrokes = []
        guard design.pages.indices.contains(pageIndex),
              design.pages[pageIndex].elements.filter({ ids.contains($0.id) }).count >= 2 else { return }
        let group = UID.make("grp")
        func grouped(_ page: inout Page) {
            for i in page.elements.indices where ids.contains(page.elements[i].id) {
                page.elements[i].group = group
                page.elements[i].layerName = Freehand.drawingName
            }
        }
        if historyVersion == sessionStepAt && pending == nil {
            grouped(&design.pages[pageIndex])
            onCommit?()
        } else {
            applyToPage(grouped)
        }
    }

    func announce(_ text: String, undoable: Bool = true) {
        announcementUnlocks = nil
        announcementUndoes = undoable
        announcement = text
    }

    /// Replace the whole document with a saved version, as one undo step —
    /// restoring is itself an edit, and one you might want to take back.
    /// The star belongs to the design, not the version, so it stays as it is.
    func restore(_ version: Design) {
        var restored = version
        restored.id = design.id
        restored.starred = design.starred
        restored.updatedAt = Date().timeIntervalSince1970 * 1000
        apply { $0 = restored }
        pageIndex = min(pageIndex, max(design.pages.count - 1, 0))
        selection.removeAll()
        announce(tr("Restored an earlier version"))
    }

    // MARK: find and replace

    /// Where one match lives, so a caller can jump to it.
    struct TextMatch: Equatable, Identifiable {
        var id: String { "\(kind.rawValue)|\(pageIndex)|\(elementId)|\(range.location)" }
        var pageIndex: Int
        /// The box it is in; empty for the page's notes.
        var elementId: String
        /// Where it is stored, its style markers taken in
        /// (RichText.storedRange).
        var range: NSRange
        /// Where it is in the words as they read.
        var plain: NSRange
        /// The line the match sits on, as it reads, for showing it in a list.
        var preview: String
        /// In a box, or in the page's speaker notes — whose words are plain,
        /// `range` and `plain` alike.
        var kind: FindReplace.Kind = .element
    }

    /// The match Find and replace is showing, its letters marked on the
    /// canvas while it is. View state only — never saved.
    var findHighlight: TextMatch?
    /// A match in a page's notes being shown: the sheet that showed it
    /// opens the page's notes. View state only — never saved.
    var notesAsked: TextMatch?

    /// Every occurrence of `needle` across every page, in reading order:
    /// in text boxes, and in the words shapes carry — not in a hidden or
    /// locked one (FindReplace.searches), nor on a locked page — as the
    /// words read, style markers left out (FindReplace.matches); then in
    /// each page's speaker notes, after its boxes, as plain text. With
    /// `wholeWord`, only where no letter or digit touches it
    /// (FindReplace.ranges).
    ///
    /// Pure and non-mutating, so the sheet can show a live count while typing
    /// without touching the document or the undo stack.
    func matches(for needle: String, caseSensitive: Bool = false, wholeWord: Bool = false) -> [TextMatch] {
        Self.matches(in: design, for: needle, caseSensitive: caseSensitive, wholeWord: wholeWord)
    }

    static func matches(in design: Design, for needle: String, caseSensitive: Bool,
                        wholeWord: Bool) -> [TextMatch] {
        guard !needle.isEmpty else { return [] }
        var found: [TextMatch] = []
        for (index, page) in design.pages.enumerated() where !PageLocks.isLocked(page) {
            for element in page.elements where FindReplace.searches(element) {
                let body = element.text ?? ""
                let plain = RichText.strip(body)
                for hit in FindReplace.matches(of: needle, in: body, caseSensitive: caseSensitive, wholeWord: wholeWord) {
                    found.append(TextMatch(pageIndex: index, elementId: element.id, range: hit.stored,
                                           plain: hit.plain, preview: line(of: plain, containing: hit.plain)))
                }
            }
            let notes = page.notes ?? ""
            for hit in FindReplace.ranges(of: needle, in: notes, caseSensitive: caseSensitive, wholeWord: wholeWord) {
                found.append(TextMatch(pageIndex: index, elementId: "", range: hit, plain: hit,
                                       preview: line(of: notes, containing: hit), kind: .notes))
            }
        }
        return found
    }

    private static func line(of body: String, containing hit: NSRange) -> String {
        let ns = body as NSString
        let lineRange = ns.lineRange(for: NSRange(location: hit.location, length: 0))
        return ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replace every occurrence across every page, as one undo step.
    ///
    /// One step on purpose: a replace-all that took forty steps to undo would
    /// be worse than no undo at all. Returns how many were replaced.
    @discardableResult
    func replaceAll(_ needle: String, with replacement: String,
                    caseSensitive: Bool = false, wholeWord: Bool = false) -> Int {
        // A chart's value labels and axis numbers are found, never replaced.
        let total = matches(for: needle, caseSensitive: caseSensitive, wholeWord: wholeWord).filter { match in
            Self.replaceable(design, match)
        }.count
        guard total > 0 else { return 0 }
        apply { design in
            for p in design.pages.indices where !PageLocks.isLocked(design.pages[p]) {
                for i in design.pages[p].elements.indices
                where FindReplace.replaces(design.pages[p].elements[i]) {
                    guard let body = design.pages[p].elements[i].text, !body.isEmpty else { continue }
                    let found = FindReplace.ranges(of: needle, in: RichText.strip(body),
                                                   caseSensitive: caseSensitive, wholeWord: wholeWord)
                    guard !found.isEmpty else { continue }
                    // One occurrence at a time, the last first, so the
                    // colours, sizes, fonts and links on the words between
                    // them stay on those words, and the words as they read
                    // before each are still where they were found.
                    let before = design.pages[p].elements[i]
                    for hit in found.reversed() {
                        Self.replaceWords(hit, with: replacement, in: &design.pages[p].elements[i])
                    }
                    let after = design.pages[p].elements[i]
                    DataGraphics.keepingLabel(&design.pages[p], was: before, now: after)
                }
                // The notes, as plain text.
                guard let notes = design.pages[p].notes else { continue }
                var words = notes as NSString
                for hit in FindReplace.ranges(of: needle, in: notes, caseSensitive: caseSensitive,
                                              wholeWord: wholeWord).reversed() {
                    words = words.replacingCharacters(in: hit, with: replacement) as NSString
                }
                design.pages[p].notes = words.length == 0 ? nil : words as String
            }
        }
        findHighlight = nil
        announce(trn("Replaced %d occurrence|Replaced %d occurrences", total))
        return total
    }

    /// Whether Replace can change `match`: words in a page's notes, or in
    /// a box FindReplace.replaces — never a chart's value label or axis
    /// number, which are found all the same.
    static func replaceable(_ design: Design, _ match: TextMatch) -> Bool {
        if match.kind == .notes { return true }
        guard design.pages.indices.contains(match.pageIndex),
              let el = design.pages[match.pageIndex].elements.first(where: { $0.id == match.elementId }) else { return false }
        return FindReplace.replaces(el)
    }

    /// The design with only `match` replaced — the words around it, their
    /// markers and the colours, sizes, fonts and links on them as they were
    /// (FindReplace.replacing; Element.setText moves them along) — or nil
    /// when the match is no longer in the design to replace, or its page
    /// has been locked since.
    static func replacingOne(_ design: Design, _ match: TextMatch, with replacement: String) -> Design? {
        guard design.pages.indices.contains(match.pageIndex),
              !PageLocks.isLocked(design.pages[match.pageIndex]) else { return nil }
        if match.kind == .notes {
            let notes = (design.pages[match.pageIndex].notes ?? "") as NSString
            guard match.range.length > 0, NSMaxRange(match.range) <= notes.length else { return nil }
            var out = design
            let now = notes.replacingCharacters(in: match.range, with: replacement)
            out.pages[match.pageIndex].notes = now.isEmpty ? nil : now
            return out
        }
        guard let i = design.pages[match.pageIndex].elements.firstIndex(where: { $0.id == match.elementId }),
              FindReplace.replaces(design.pages[match.pageIndex].elements[i]) else { return nil }
        let body = design.pages[match.pageIndex].elements[i].text ?? ""
        let length = (RichText.strip(body) as NSString).length
        guard match.plain.length > 0, NSMaxRange(match.plain) <= length,
              RichText.storedRange(of: match.plain, in: body) == match.range else { return nil }
        var out = design
        let before = out.pages[match.pageIndex].elements[i]
        replaceWords(match.plain, with: replacement, in: &out.pages[match.pageIndex].elements[i])
        DataGraphics.keepingLabel(&out.pages[match.pageIndex], was: before,
                                  now: out.pages[match.pageIndex].elements[i])
        return out
    }

    /// Replace: the one match, as one undo step. False when it is no longer
    /// there.
    @discardableResult
    func replaceOne(_ match: TextMatch, with replacement: String) -> Bool {
        guard let next = Self.replacingOne(design, match, with: replacement) else { return false }
        apply { $0 = next }
        return true
    }

    /// The words in `range` of `el` — of the words as they read — replaced
    /// (FindReplace.replacing), everything on the words moved along, and
    /// the box grown or shrunk to its words.
    private static func replaceWords(_ range: NSRange, with replacement: String, in el: inout Element) {
        el.setText(FindReplace.replacing(range, in: el.text ?? "", with: replacement))
        ShapeText.fitWords(&el)
    }

    /// After Replace, the match the sheet moves on to in `matches`, the
    /// design's matches now: the one that took the replaced one's place in
    /// reading order, past any the replacement itself holds — round to the
    /// first after the last.
    static func matchAfter(replacing replaced: TextMatch, at current: Int, length: Int,
                           in matches: [TextMatch]) -> Int {
        guard !matches.isEmpty else { return 0 }
        let end = replaced.plain.location + length
        var i = min(max(current, 0), matches.count)
        while i < matches.count, matches[i].pageIndex == replaced.pageIndex,
              matches[i].elementId == replaced.elementId, matches[i].plain.location < end {
            i += 1
        }
        return i < matches.count ? i : 0
    }

    /// Show a match: switch to its page, select its element and mark its
    /// letters there (findHighlight); the editor keeps it in sight. A match
    /// in the notes opens the page's notes instead (notesAsked).
    func reveal(_ match: TextMatch) {
        if match.kind == .notes {
            reveal(elementId: nil, onPage: match.pageIndex)
            findHighlight = nil
            notesAsked = match
            return
        }
        reveal(elementId: match.elementId, onPage: match.pageIndex)
        findHighlight = match
    }

    /// Switch to page `index` and select `elementId` there — or only the
    /// page, for a finding about the page as a whole. The editor keeps the
    /// selection in sight under the sheet.
    func reveal(elementId: String?, onPage index: Int) {
        guard design.pages.indices.contains(index) else { return }
        pageIndex = index
        selection = elementId.map { Set([$0]) } ?? []
    }

    // MARK: style

    /// The look of an element, without its identity, position or content.
    ///
    /// Copying a style is a different operation from copying an element, and
    /// conflating them is why "make this heading look like that one" usually
    /// ends in retyping the text.
    struct Style: Equatable, Codable {
        var fill: Paint?
        var stroke: String?
        var strokeWidth: Double?
        var radius: Double?
        var corners: [Double]?
        var dropCap: Bool?
        var color: String?
        var fontFamily: String?
        var fontSize: Double?
        var fontWeight: Int?
        var italic: Bool?
        var underline: Bool?
        var uppercase: Bool?
        var align: String?
        var lineHeight: Double?
        var letterSpacing: Double?
        var listStyle: String?
        var indent: Int?
        var textFill: Paint?
        var vAlign: String?
        var paragraphSpacing: Double?
        var effect: TextEffectSpec?
        var curve: Double?
        var filter: String?
        var adjustments: Adjustments?
        var maskShapeId: String?
        var duotone: Duotone?
        /// How much of `filter` shows, which goes with it.
        var filterStrength: Double?
        var opacity: Double
        var shadow: Shadow?
        var blendMode: String?
        var thickness: Double?
        var dash: String?
        var startCap: String?
        var endCap: String?
    }

    private(set) var copiedStyle: Style?
    var hasCopiedStyle: Bool { copiedStyle != nil }

    /// The look of `el`. Copied for pasting (`wholeBoxList`), a box with its
    /// own lines gives its list as one for the whole box; a saved text
    /// style keeps only the box-wide keys, as they are.
    static func style(of el: Element, wholeBoxList: Bool = true) -> Style {
        var style = Style(fill: el.fill, stroke: el.stroke, strokeWidth: el.strokeWidth, radius: el.radius,
                          corners: el.corners, dropCap: el.dropCap,
                          color: el.color, fontFamily: el.fontFamily, fontSize: el.fontSize,
                          fontWeight: el.fontWeight, italic: el.italic, underline: el.underline,
                          uppercase: el.uppercase, align: el.align,
                          lineHeight: el.lineHeight, letterSpacing: el.letterSpacing,
                          listStyle: el.listStyle, indent: el.indent, textFill: el.textFill,
                          vAlign: el.vAlign, paragraphSpacing: el.paragraphSpacing,
                          effect: el.effect, curve: el.curve, filter: el.filter,
                          adjustments: el.adjustments, maskShapeId: el.maskShapeId, duotone: el.duotone,
                          filterStrength: el.filterStrength, opacity: el.opacity, shadow: el.shadow, blendMode: el.blendMode,
                          thickness: el.thickness, dash: el.dash,
                          startCap: el.startCap, endCap: el.endCap)
        // A box with its own paragraphs gives its style the list and indent
        // of its first listed line (its first, with none listed) as the
        // box-wide keys, so a heading-and-bullets look pastes as bullets.
        if wholeBoxList, let lines = TextLists.paragraphsOf(el),
           let line = lines.first(where: { $0.isListed }) ?? lines.first {
            style.listStyle = line.isListed ? line.list : nil
            style.indent = line.level > 0 ? line.level : nil
        }
        return style
    }

    /// Apply a style, keeping everything that makes the element itself.
    ///
    /// Fields that belong to another kind of element are left alone rather
    /// than copied across: pasting a text style onto a rectangle should change
    /// nothing about the rectangle, not give it a font. A pasted style's
    /// list is the whole box's, so a text box's own lines go; a linked text
    /// style (`keepingLines`) leaves them, so updating it keeps each
    /// follower's lines.
    static func apply(_ style: Style, to el: inout Element, keepingLines: Bool = false) {
        el.opacity = style.opacity
        el.shadow = style.shadow
        el.blendMode = style.blendMode
        switch el.type {
        case .shape:
            el.fill = style.fill
            el.stroke = style.stroke
            el.strokeWidth = style.strokeWidth
            el.radius = style.radius
            el.corners = style.corners
            // A border's dash goes with it; a line's "solid" is no key.
            el.dash = BorderDash.kept(style.dash)
        case .text:
            el.dropCap = style.dropCap
            el.color = style.color
            el.fontFamily = style.fontFamily
            el.fontSize = style.fontSize
            el.fontWeight = style.fontWeight
            el.italic = style.italic
            el.underline = style.underline
            el.uppercase = style.uppercase
            el.align = style.align
            el.lineHeight = style.lineHeight
            el.letterSpacing = style.letterSpacing
            // A pasted style's list and indent are the whole box's: its
            // own paragraphs, which would set every line over them, go.
            if !keepingLines { el.dropParagraphs() }
            el.listStyle = style.listStyle
            el.indent = style.indent
            el.textFill = style.textFill
            el.vAlign = style.vAlign
            el.paragraphSpacing = style.paragraphSpacing
            el.effect = style.effect
            el.curve = style.curve
            el.h = FontLibrary.layoutHeight(for: el)
        case .image:
            el.filter = style.filter
            el.adjustments = style.adjustments
            el.maskShapeId = style.maskShapeId
            el.duotone = style.duotone
            el.filterStrength = style.filterStrength
            el.radius = style.radius
            el.stroke = style.stroke
            el.strokeWidth = style.strokeWidth
            el.dash = BorderDash.kept(style.dash)
        case .line:
            el.color = style.color
            el.dash = style.dash
            el.startCap = style.startCap
            el.endCap = style.endCap
            // An elbow's or a curve's box is its ends padded by its weight:
            // laid round the same ends again.
            el = LineRoutes.withThickness(el, style.thickness)
        case .sticker:
            break
        }
    }

    /// The kind of element the copied style came from, which says what of
    /// it another kind takes (StylePaint).
    private(set) var copiedStyleKind: ElementType?

    /// Paint mode: Copy style is armed, and a tap on any unlocked element
    /// pastes the style onto it (paintStyle) — on until Done, Escape, the
    /// button again, or a tap on the empty page. View state only.
    var stylePainting = false

    func copyStyle() {
        guard let el = singleSelection else { return }
        copiedStyle = Self.style(of: el)
        copiedStyleKind = el.type
        buzz(.tick)
    }

    /// The toolbar's Copy style: copies the selection's style and arms paint
    /// mode — or, while it is armed, puts it away.
    func toggleStylePainting() {
        if stylePainting {
            stylePainting = false
            return
        }
        guard singleSelection != nil else { return }
        copyStyle()
        stylePainting = true
    }

    /// Paste the copied style onto everything selected, locked things left
    /// as they are: one undo step.
    func pasteStyle() {
        guard let style = copiedStyle else { return }
        let kind = copiedStyleKind
        updateSelected { $0 = StylePaint.pasted(style, from: kind ?? $0.type, onto: $0) }
    }

    /// Paint mode's tap on element `id`: it — or its whole sticky group —
    /// is selected and takes the copied style, as one undo step, felt as it
    /// lands. A locked one is left as it is.
    func paintStyle(onto id: String) {
        guard copiedStyle != nil, let el = element(id), !refusesLockedPage() else { return }
        guard !el.locked else {
            buzz(.reject)
            return
        }
        select(id)
        pasteStyle()
        buzz(.confirm)
    }

    /// ⇧⌘L: everything selected locked whole while anything of it is not,
    /// else all of it unlocked.
    func toggleLockSelected() {
        let anyUnlocked = selectedElements.contains { !$0.locked }
        setLock(selection, anyUnlocked ? .full : .unlocked)
    }

    /// The Lock menu's Lock, Lock position or Unlock, for everything
    /// selected, as one undo step.
    func lockSelected(_ mode: ElementLock.Mode) {
        setLock(selection, mode)
    }

    /// How the selection is locked, for the Lock menu: one way when all of
    /// it is, else nil.
    var selectionLock: ElementLock.Mode? {
        let modes = Set(selectedElements.map { ElementLock.mode(of: $0) })
        return modes.count == 1 ? modes.first : nil
    }

    // MARK: layers

    /// Lock or unlock the elements `ids` on this page, from their Layers row,
    /// as one undo step.
    func setLocked(_ ids: Set<String>, locked: Bool) {
        setLock(ids, locked ? .full : .unlocked)
    }

    /// Lock the elements `ids` on this page by `mode` — whole, in position
    /// only, or not at all — as one undo step; none when nothing changes.
    func setLock(_ ids: Set<String>, _ mode: ElementLock.Mode) {
        guard page.elements.contains(where: { ids.contains($0.id) && ElementLock.mode(of: $0) != mode }) else { return }
        // A box being typed in cannot be locked mid-word.
        if let typing = editingTextId, ids.contains(typing) { endTextEdit() }
        applyToPage { page in
            for i in page.elements.indices where ids.contains(page.elements[i].id) {
                page.elements[i] = ElementLock.with(page.elements[i], mode)
            }
        }
    }

    /// Hide the elements `ids` on this page, or show them again, as one undo
    /// step. A hidden element stays where it is, listed in Layers and
    /// selectable from there; shown is nil, never false.
    func setHidden(_ ids: Set<String>, hidden: Bool) {
        guard page.elements.contains(where: { ids.contains($0.id) && $0.isHidden != hidden }) else { return }
        // A box being typed in is finished before it goes.
        if let typing = editingTextId, ids.contains(typing) { endTextEdit() }
        applyToPage { page in
            for i in page.elements.indices where ids.contains(page.elements[i].id) {
                page.elements[i].hidden = hidden ? true : nil
            }
        }
    }

    /// Give element `id` a name of its own — trimmed, cut to
    /// LayerNames.maxLength — or, when `typed` is blank, take its own name
    /// away; one undo step, none when nothing changes.
    func renameLayer(_ id: String, to typed: String) {
        let name = LayerNames.cleaned(typed)
        guard let el = element(id), el.layerName != name else { return }
        applyToPage { page in
            if let i = page.elements.firstIndex(where: { $0.id == id }) { page.elements[i].layerName = name }
        }
    }

    /// The Layers rows at `source` dragged to before row `destination`, as
    /// one undo step; a group's row takes its whole group (see
    /// LayerRows.moved). One element's row dropped among an opened group's
    /// rows joins it, and a member's dropped past them leaves it
    /// (LayerRows.drop).
    func moveLayers(_ rows: [LayerRows.Row], from source: IndexSet, to destination: Int) {
        let dragged = Set(source.filter { rows.indices.contains($0) }.flatMap { rows[$0].elements.map(\.id) })
        switch LayerRows.drop(rows, from: source, to: destination) {
        case .join(let group): return addToGroup(dragged, group: group)
        case .leave: return removeFromGroup(dragged)
        case .reorder: break
        }
        let reordered = LayerRows.moved(page.elements, rows: rows, from: source, to: destination)
        guard reordered.map(\.id) != page.elements.map(\.id) else { return }
        applyToPage { $0.elements = reordered }
    }

    /// Take the element `id` alone, from its Layers row — a group's member
    /// without the rest of the group.
    func selectLayer(_ id: String) {
        selectLayers([id])
    }

    /// Take the elements `ids`, just these, from Layers — a group inside an
    /// opened group, or the rows ticked in Select (Layers.toggled), hidden
    /// and locked ones too. Nothing on a locked page.
    func selectLayers(_ ids: Set<String>) {
        endTextEdit()
        guard !refusesLockedPage() else { return }
        selection = ids
        if selection.count >= 2 { tipEvent = .multiSelected }
    }

    /// Flip what is selected: one thing in place, a group or several as one
    /// unit, mirrored about their box (Geometry.flipAll). What is locked in
    /// place stays, and is not part of the box — the box of those free to
    /// move, as on the Android twin. One undo step.
    func flipSelected(horizontal: Bool) {
        guard unlockedSelectionCount > 0 else { return }
        buzz(.tick)
        let members = selectedElements.filter { !$0.holdsPlace }
        guard selectedElements.count > 1, !members.isEmpty else {
            updateSelected { el in el = LineRoutes.flippedAlone(el, horizontal: horizontal) }
            return
        }
        let box = Geometry.union(members.map(Geometry.aabb))
        let flipped = Geometry.flipAll(members, box: box, horizontal: horizontal)
        applyToPage { page in
            let byId = Dictionary(uniqueKeysWithValues: flipped.map { ($0.id, $0) })
            for i in page.elements.indices {
                if let e = byId[page.elements[i].id] { page.elements[i] = e }
            }
        }
    }

    // MARK: pages

    func addPage() {
        let bg = page.background
        apply { $0.pages.insert(Page(background: bg), at: pageIndex + 1) }
        pageIndex += 1
        selection.removeAll()
        buzz(.pageAdded)
        tipEvent = .pageAdded
    }

    /// One page of a template of your own, fitted to this page, in its
    /// place — its background and everything on it — as one undo step:
    /// "Use this page", or a template of one page. Every page of one is
    /// applyTemplateSet's, as a built-in set's are.
    func applyTemplatePage(_ page: Page, name: String) {
        guard !refusesLockedPage() else { return }
        let at = pageIndex
        apply { $0 = Self.appliedTemplate($0, pages: [page], at: at) }
        selection.removeAll()
        buzz(.confirm)
        announce(tr("Started over from \u{201C}%@\u{201D}", name))
    }

    /// "Add as new page": one page of a template, fitted to this page,
    /// put in after it and shown, as one undo step — its background and
    /// everything on it, overwriting nothing, so a locked page does not stop
    /// it (insertedTemplatePage). As the Android twin's addTemplatePage.
    func addTemplatePage(_ page: Page, name: String) {
        let at = pageIndex + 1
        apply { $0 = Self.insertedTemplatePage($0, page: page, at: at) }
        pageIndex = at
        selection.removeAll()
        buzz(.confirm)
        announce(tr("Added a page from \u{201C}%@\u{201D}", name))
    }

    /// What a tap on a template does in the editor: on a page with nothing
    /// on it, it replaces the page, as ever; on one with something on it —
    /// or a locked one, which nothing may replace — it goes on a new page
    /// after it, so a filled page is never overwritten by mistake. A hold
    /// offers both. As the Android twin's templateAddsPage.
    var templateAddsPage: Bool { isPageLocked || !page.elements.isEmpty }

    /// One page of a template, the way templateAddsPage says.
    func useTemplatePage(_ page: Page, name: String) {
        if templateAddsPage { addTemplatePage(page, name: name) } else { applyTemplatePage(page, name: name) }
    }

    /// The design with a template's `page` put in at `index`, kept to the
    /// design's ends. It takes the size of the page it follows (the first
    /// page's, at 0) — its width and height kept, its own or none — as
    /// Apply all fits each page. Nothing else changes. The Android twin's
    /// Templates.insertedTemplatePage. Pure.
    static func insertedTemplatePage(_ design: Design, page: Page, at index: Int) -> Design {
        let at = min(max(index, 0), design.pages.count)
        let beside = design.pages.indices.contains(at - 1) ? design.pages[at - 1] : design.pages.first
        var sized = page
        sized.width = beside?.width
        sized.height = beside?.height
        var out = design
        out.pages.insert(sized, at: at)
        return out
    }

    /// The design with `pages` applied at page `index`: the first in its
    /// place, any more after it at its size. Pure.
    static func appliedTemplate(_ design: Design, pages: [Page], at index: Int) -> Design {
        guard let first = pages.first, design.pages.indices.contains(index) else { return design }
        var out = design
        out.pages[index].background = first.background
        out.pages[index].elements = first.elements
        let rest = pages.dropFirst().map { page -> Page in
            var sized = page
            sized.width = design.pages[index].width
            sized.height = design.pages[index].height
            return sized
        }
        out.pages.insert(contentsOf: rest, at: index + 1)
        return out
    }

    /// "Apply all N pages" of a template set — built in or your own —
    /// fitted to this page, as one undo step (appliedTemplateSet), on the
    /// first of them.
    func applyTemplateSet(_ pages: [Page], name: String) {
        guard !pages.isEmpty, !refusesLockedPage() else { return }
        let applied = Self.appliedTemplateSet(design, pages: pages, at: pageIndex)
        apply { $0 = applied.design }
        pageIndex = applied.first
        selection.removeAll()
        buzz(.confirm)
        announce(trn("Applied all %d page of \u{201C}%@\u{201D}|Applied all %d pages of \u{201C}%@\u{201D}", pages.count, name))
    }

    /// The design with a template set's `pages` applied from page `index`,
    /// and where the first of them landed. A design with nothing on it —
    /// no element on any page, none locked; a background alone is not
    /// something — is replaced by them, every page; any other gets them after page
    /// `index`, in order, keeping all it had. Each takes page `index`'s size.
    /// The simplest rule, kept on both phones. Pure.
    static func appliedTemplateSet(_ design: Design, pages: [Page], at index: Int) -> (design: Design, first: Int) {
        guard !pages.isEmpty, design.pages.indices.contains(index) else { return (design, index) }
        let sized = pages.map { page -> Page in
            var out = page
            out.width = design.pages[index].width
            out.height = design.pages[index].height
            return out
        }
        var out = design
        if isEmptyForTemplates(design) {
            out.pages = sized
            // A master page that went with the old pages goes too.
            out.masterPageId = nil
            return (out, 0)
        }
        out.pages.insert(contentsOf: sized, at: index + 1)
        return (out, index + 1)
    }

    /// Whether a design has nothing on it for a template set to keep: no
    /// element on any page, and no locked page, which nothing may take away.
    static func isEmptyForTemplates(_ design: Design) -> Bool {
        design.pages.allSatisfy { $0.elements.isEmpty } && !design.pages.contains(where: PageLocks.isLocked)
    }

    func duplicatePage() {
        let copy = Copies.of(page)
        apply { $0.pages.insert(copy, at: pageIndex + 1) }
        pageIndex += 1
        selection.removeAll()
    }

    func deletePage() {
        guard design.pages.count > 1 else { return }
        let number = pageIndex + 1
        apply { $0.pages.remove(at: pageIndex) }
        pageIndex = min(pageIndex, design.pages.count - 1)
        selection.removeAll()
        announce(tr("Deleted page %d", number))
    }

    func movePage(by delta: Int) {
        let target = pageIndex + delta
        guard target >= 0 && target < design.pages.count else { return }
        apply { $0.pages.swapAt(pageIndex, target) }
        pageIndex = target
    }

    /// List-style reorder, as the organizer's drag hands it over. The
    /// current page stays current wherever it ends up.
    func movePages(from source: IndexSet, to destination: Int) {
        let currentId = page.id
        apply { $0.pages.move(fromOffsets: source, toOffset: destination) }
        if let i = design.pages.firstIndex(where: { $0.id == currentId }) { pageIndex = i }
    }

    /// The pages `ids` put down together in the gap `gap` (PageOrder.moved)
    /// — dragged in the organiser's grid or along the pages bar, or moved
    /// by VoiceOver — as one undo step; none when the order is as it was.
    /// The current page stays current wherever it ends up.
    func movePages(_ ids: Set<String>, to gap: Int) {
        let reordered = PageOrder.moved(design.pages, ids: ids, toIndex: gap)
        guard reordered.map(\.id) != design.pages.map(\.id) else { return }
        let currentId = page.id
        apply { $0.pages = reordered }
        if let i = design.pages.firstIndex(where: { $0.id == currentId }) { pageIndex = i }
        buzz(.tick)
    }

    /// A blank page put in at `index` — the organiser's + between two
    /// thumbnails — with the background of the page to its left
    /// (PageOrder.blank), as one undo step, and shown: like Add page, and
    /// like Android's insertBlankPage.
    func insertPage(at index: Int) {
        let at = min(max(index, 0), design.pages.count)
        let blank = PageOrder.blank(at: at, in: design.pages)
        apply { $0.pages.insert(blank, at: at) }
        pageIndex = at
        selection.removeAll()
        buzz(.pageAdded)
    }

    /// Delete several pages in one undo step, never the last one. A locked
    /// page among them stays, and the note says how many did
    /// (PageLocks.deletedNote).
    func deletePages(_ ids: Set<String>) {
        let victims = Set(design.pages.filter { ids.contains($0.id) && !PageLocks.isLocked($0) }.map(\.id))
        let skipped = design.pages.filter { ids.contains($0.id) && PageLocks.isLocked($0) }.count
        guard victims.count < design.pages.count else { return }
        guard !victims.isEmpty else {
            if skipped > 0 {
                buzz(.reject)
                announce(PageLocks.deletedNote(deleted: 0, skipped: skipped), undoable: false)
            }
            return
        }
        let currentId = page.id
        apply { $0.pages.removeAll { victims.contains($0.id) } }
        pageIndex = design.pages.firstIndex { $0.id == currentId } ?? min(pageIndex, design.pages.count - 1)
        selection.removeAll()
        announce(PageLocks.deletedNote(deleted: victims.count, skipped: skipped))
    }

    /// Duplicate several pages, each copy landing right after its source.
    func duplicatePages(_ ids: Set<String>) {
        guard design.pages.contains(where: { ids.contains($0.id) }) else { return }
        // The page on screen stays on screen, wherever the copies land.
        let currentId = page.id
        defer { if let i = design.pages.firstIndex(where: { $0.id == currentId }) { pageIndex = i } }
        apply { d in
            var out: [Page] = []
            for p in d.pages {
                out.append(p)
                if ids.contains(p.id) {
                    out.append(Copies.of(p))
                }
            }
            d.pages = out
        }
    }

    /// Hide the page on screen from Present and from "All pages" in an
    /// export, or show it again, as one undo step. It stays where it is, to
    /// be edited like any other.
    func setPageHidden(_ hidden: Bool) {
        applyToPage { $0.hidden = hidden ? true : nil }
    }

    /// This page's transition, as written, and its length, kept to the
    /// range, given to every page, hidden ones too, as one undo step — a
    /// length out of range lands clamped, as on the Android twin.
    func applyTransitionToAllPages() {
        let transition = page.transition, seconds = PageTransitions.seconds(page.transitionSeconds)
        apply { d in
            for i in d.pages.indices {
                d.pages[i].transition = transition
                d.pages[i].transitionSeconds = seconds
            }
        }
    }

    /// Hide or show several pages in one undo step, as the organizer picks
    /// them.
    func setPagesHidden(_ ids: Set<String>, hidden: Bool) {
        guard design.pages.contains(where: { ids.contains($0.id) }) else { return }
        apply { d in
            for i in d.pages.indices where ids.contains(d.pages[i].id) {
                d.pages[i].hidden = hidden ? true : nil
            }
        }
    }

    // MARK: document theme

    /// Text at or above this size is a heading and takes the pairing's
    /// heading face; the rest takes the body face.
    static let headingSize = 32.0

    /// The design with a palette and a type pairing applied to every page:
    /// colours remapped by luminance rank onto the palette, headings and body
    /// text given the pairing's faces at their own sizes; a locked page left
    /// as it is. Pure, so the sheet can preview it before anyone commits.
    ///
    /// With `brandFonts` setting any ranked role, the brand kit's text roles
    /// are applied by size rank in place of a pairing (see brandFaces).
    static func themed(_ design: Design, palette: [String]?, pairing: FontPairing?,
                       brandFonts: BrandFonts = BrandFonts()) -> Design {
        var out = design
        if let palette, !palette.isEmpty {
            // Faint colours — a chart's clear plot, a table's hairlines — keep
            // their place: made opaque, a clear fill turned solid.
            let colors = ColorTools.documentColors(design, limit: 24).filter { !ContrastAudit.isFaint($0) }
            if !colors.isEmpty {
                for p in out.pages.indices {
                    ColorTools.shuffle(page: &out.pages[p], docColors: colors, palette: palette)
                }
            }
        }
        if !brandFonts.rankedRoles.isEmpty {
            let faces = brandFaces(sizes: out.pages.flatMap(\.elements).filter { $0.type == .text }
                .map { $0.fontSize ?? 42 }, fonts: brandFonts)
            for p in out.pages.indices {
                for i in out.pages[p].elements.indices where out.pages[p].elements[i].type == .text {
                    guard let face = faces[out.pages[p].elements[i].fontSize ?? 42] else { continue }
                    // The role's face is the box's whole face: the words' own go.
                    out.pages[p].elements[i].setFontFamily(face.family)
                    out.pages[p].elements[i].fontWeight = face.weight
                    out.pages[p].elements[i].h = FontLibrary.layoutHeight(for: out.pages[p].elements[i])
                }
            }
        } else if let pairing {
            for p in out.pages.indices {
                for i in out.pages[p].elements.indices where out.pages[p].elements[i].type == .text {
                    let spec = (out.pages[p].elements[i].fontSize ?? 42) >= headingSize
                        ? pairing.heading : pairing.body
                    out.pages[p].elements[i].setFontFamily(spec.fontFamily)
                    out.pages[p].elements[i].fontWeight = spec.fontWeight
                    if let spacing = spec.letterSpacing { out.pages[p].elements[i].letterSpacing = spacing }
                    out.pages[p].elements[i].h = FontLibrary.layoutHeight(for: out.pages[p].elements[i])
                }
            }
        }
        // A locked page is kept as it was, its background and words alike.
        for p in out.pages.indices where PageLocks.isLocked(design.pages[p]) {
            out.pages[p] = design.pages[p]
        }
        return out
    }

    /// The brand face for each text size, by rank: the sizes, once each and
    /// largest first, take the kit's ranked roles in turn — title, subtitle,
    /// heading, subheading, section header, body, those it sets
    /// (BrandFonts.rankedRoles) — and every size past the last role
    /// takes the last. Family and weight only: the sizes stay as they are.
    /// Empty when the kit sets none of those roles.
    static func brandFaces(sizes: [Double], fonts: BrandFonts) -> [Double: BrandFont] {
        let roles = fonts.rankedRoles
        guard !roles.isEmpty else { return [:] }
        var faces: [Double: BrandFont] = [:]
        for (rank, size) in Set(sizes).sorted(by: >).enumerated() {
            faces[size] = fonts[roles[min(rank, roles.count - 1)]]
        }
        return faces
    }

    /// Apply a theme to the whole document as one undo step.
    func applyTheme(palette: [String]?, pairing: FontPairing?, brandFonts: BrandFonts = BrandFonts()) {
        let next = Self.themed(design, palette: palette, pairing: pairing, brandFonts: brandFonts)
        guard next != design else { return }
        apply { $0 = next }
        announce(design.pages.count == 1 ? tr("Applied theme to the page")
                 : trn("Applied theme to all %d page|Applied theme to all %d pages", design.pages.count))
    }

    /// The design in the brand kit's look, as Document theme gives it: the
    /// kit's first palette of two colours or more mapped on by lightness,
    /// its text roles given by size rank. Unchanged by a kit with neither.
    static func branded(_ design: Design, kit: BrandKit) -> Design {
        themed(design, palette: kit.themePalettes.first?.colors, pairing: nil, brandFonts: kit.fonts)
    }

    /// "Start with my brand": the kit's look as one step, which Undo takes
    /// back, and said.
    func applyBrandKit(_ kit: BrandKit) {
        let next = Self.branded(design, kit: kit)
        guard next != design else { return }
        apply { $0 = next }
        announce(tr("Brand kit applied"))
    }

    // MARK: components

    /// Save the selection as a component, keeping nothing locked in it.
    @discardableResult
    func saveSelectionAsComponent(named name: String) -> Component? {
        let saved = Components.add(named: name, from: selectedElements)
        if let saved {
            buzz(.confirm)
            announce(tr("Saved \u{201C}%@\u{201D} to Components", saved.name), undoable: false)
        }
        return saved
    }

    /// Drop a component onto the page at half its width, centred.
    func insertComponent(_ component: Component) {
        guard landsOnUnlockedPage() else { return }
        let width = (pageWidth * 0.5).rounded()
        let height = width * component.height / max(component.width, 1)
        let origin = CGPoint(x: ((pageWidth - width) / 2).rounded(), y: ((pageHeight - height) / 2).rounded())
        let elements = Components.instance(of: component, width: width, at: origin)
        guard !elements.isEmpty else { return }
        applyToPage { $0.elements.append(contentsOf: elements) }
        selection = Set(elements.map(\.id))
    }

    /// A font combination (TextCombos), 72% of this page's width — the page
    /// may have a size of its own — and centred on it, each text then
    /// measured with the real faces from its top: on top of the page, one
    /// group, selected, as one Undo, as the Android twin inserts one. Brand
    /// colours are left to the theme sheet, as Canva leaves them.
    func addTextCombo(_ combo: TextCombos.Combo) {
        guard landsOnUnlockedPage() else { return }
        let made = TextCombos.measured(TextCombos.placed(combo, pageWidth: pageWidth, pageHeight: pageHeight))
        guard !made.isEmpty else { return }
        applyToPage { $0.elements.append(contentsOf: made) }
        selection = Set(made.map(\.id))
        markFresh(made)
        buzz(.confirm)
    }

    // MARK: text styles

    /// Apply a saved style to the selected text elements, one undo step.
    func applyTextStyle(_ style: TextStyle) {
        updateSelected { el in TextStyles.apply(style, to: &el) }
    }

    /// The selected text in a brand role's face — at the kit's size for
    /// it, scaled to this page, when it sets one — one undo step, each box
    /// measured again, as the Android twin's Text panel sets it.
    /// The face's colour, spacing, capitals and slant too, as a role sets
    /// them (BrandFonts.typeSettings).
    func applyBrandFace(_ face: BrandFont, role: BrandFonts.Role? = nil) {
        let width = pageWidth
        let palettes = BrandKit.load().palettes
        updateSelected { el in BrandFonts.apply(face, to: &el, pageWidth: width, role: role, palettes: palettes) }
    }

    /// Re-read the style from `element` and re-apply it to every element on
    /// every page that follows it — the linked half of a linked style.
    func updateTextStyle(_ id: String, from element: Element) {
        TextStyles.update(id, from: element)
        guard let style = TextStyles.load().first(where: { $0.id == id }) else { return }
        apply { design in
            for p in design.pages.indices {
                for i in design.pages[p].elements.indices
                where design.pages[p].elements[i].textStyleId == id && design.pages[p].elements[i].id != element.id {
                    TextStyles.apply(style, to: &design.pages[p].elements[i])
                }
            }
        }
    }

    // MARK: animation preview

    /// Seconds into the current page while a preview plays; nil at rest.
    var previewTime: Double?
    /// Whether the page's clock is running — Play, or a play through the
    /// film — rather than standing where a scrub of the timeline put
    /// previewTime: only then does a clip play on in a player of its own.
    private(set) var previewRuns = false
    /// A clip's trim handle being dragged in the Clip sheet: the canvas
    /// shows that element at the handle's moment. View state only, never
    /// saved.
    var clipScrub: Trimming.Scrub?
    /// Whether Hold to compare is held: the canvas draws the selected photo
    /// as it was before its looks (PhotoEdits.original). View state only,
    /// nothing written.
    var comparing = false
    /// Where the timeline's playhead stands, in seconds into the page
    /// `playheadPage` — so a page before it held longer or shorter leaves
    /// it where it is (see TimelineEditing). View state only, never saved.
    var playhead: Double = 0
    /// The page the playhead stands on; nil for the page on screen.
    var playheadPage: String?
    private var previewTask: Task<Void, Never>?
    /// What waits on a play through the film — a voice-over's take — to
    /// end with it, however it ends: the film's end, another page brought
    /// up, Play, or stopPreview, as the Android twin's take ends.
    @ObservationIgnored private var previewEnded: (@MainActor () -> Void)?
    /// What is heard while the preview plays: the page's clips, and the
    /// audio tracks from where the page comes in the video.
    private let previewSound = PageSound(presenting: false)

    var pageHold: Double {
        page.holdSeconds ?? design.motion?.secondsPerPage ?? MotionSettings().secondsPerPage
    }

    /// Whether the page has anything to play — the master's elements behind
    /// it included, as the video, Present and the Android twin count them,
    /// so a page whose only motion is the master's still offers Play.
    var pageIsAnimated: Bool {
        MovieExporter.isAnimated(page, in: design)
    }

    /// Where a preview of the page's exits starts: half a second before the
    /// first of them begins, never before the page does.
    var exitPreviewStart: Double {
        let span = ElementAnimation.exitSpan(design.masterElements(behind: page) + PageAnimation.playing(page).elements)
        return max(0, pageHold - span - 0.5)
    }

    /// Play the page's entrances, exits and drifts once, at 30 frames a
    /// second, from `offset` seconds in, then settle. Scrub by setting
    /// previewTime directly. Its clips are heard, and the audio tracks from
    /// where the page comes in the video, for the page's hold.
    func playPreview(from offset: Double = 0) {
        endThrough()
        previewTask?.cancel()
        let hold = pageHold
        let offset = min(max(offset, 0), hold)
        // The page being played. Once another is on screen — picked in the
        // pages bar, or put there by a delete, an undo or a restored version
        // — the preview is over: that page was never played, and drawing it
        // at this one's clock would show its entrances already done.
        let playing = page.id
        // The moment the page's clock reads 0, so its sound is where its
        // picture is.
        let since = Date().addingTimeInterval(-offset)
        previewSound.stop()
        previewSound.page(AudioMix.clips(design: design, page: page), since: since, length: hold)
        previewSound.tracks(design: design, offset: AudioMix.pageStart(design: design, index: pageIndex), since: since,
                            film: AudioMix.filmLength(design: design))
        previewRuns = true
        previewTask = Task { @MainActor in
            // Timed by the clock rather than by counting passes: a pass that
            // runs long — a busy page, a clip's frame being decoded — would
            // otherwise play the page in slow motion and past its hold,
            // where Present and the Android twin keep to real time.
            let start = ContinuousClock.now
            while page.id == playing {
                let elapsed = ContinuousClock.now - start
                let seconds = Double(elapsed.components.seconds)
                let fraction = Double(elapsed.components.attoseconds) / 1e18
                let t = offset + seconds + fraction
                if t > hold { break }
                previewTime = t
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else { return }
            }
            previewTime = nil
            previewRuns = false
            previewSound.stop()
        }
    }

    /// The selected clip's trim, speed, loop, volume, mute and fades, as
    /// one undo step. A clip at all the defaults keeps none, so its file has no
    /// `clip` key.
    func setClip(_ clip: ClipPlayback) {
        // The clip's captions move with its trim and speed, so the words
        // stay on the frames they were heard in (Captions.retimed).
        var retimed: [String: ClipPlayback] = [:]
        for el in selectedElements where VideoStore.isVideo(el.src) && !el.locked && (el.clip ?? ClipPlayback()) != clip {
            if let id = el.src.flatMap({ VideoStore.split($0)?.id }) { retimed[VideoStore.src(id, at: nil)] = el.clip ?? ClipPlayback() }
        }
        applyToPage { page in
            for i in page.elements.indices {
                let el = page.elements[i]
                if self.selection.contains(el.id), VideoStore.isVideo(el.src), !el.locked {
                    page.elements[i].clip = clip.isDefault ? nil : clip
                } else if let c = el.captions, let source = c.source, let was = retimed[source] {
                    page.elements[i] = Captions.on(el, Captions(source: source, cues: Captions.retimed(c.cues, from: was, to: clip),
                                                               style: c.style))
                }
            }
        }
    }

    /// The page's own hold set to play the selected clip through once, as
    /// one undo step; nothing for a clip whose length cannot be read.
    func fitPageToClip() {
        guard let el = singleSelection, let id = el.src.flatMap({ VideoStore.split($0)?.id }),
              let length = VideoStore.duration(of: id), length > 0.01 else { return }
        applyToPage { $0.holdSeconds = VideoStore.fitHold(el.clip ?? ClipPlayback(), duration: length) }
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewTime = nil
        previewRuns = false
        previewSound.stop()
        endThrough()
    }

    /// A play through the film over: what waited on it ends now, once.
    private func endThrough() {
        guard let ended = previewEnded else { return }
        previewEnded = nil
        MainActor.assumeIsolated { ended() }
    }

    /// The design played from the start of the page on screen to the end of
    /// the film, each shown page after it in turn, as Play plays one — in
    /// silence, as a voice-over is recorded over it and the microphone
    /// would hear the speaker — then `onEnd`: at the film's end, when
    /// another page is brought up meanwhile, or when it is stopped.
    func playThrough(onEnd: @escaping @MainActor () -> Void) {
        stopPreview()
        // Followed by id: an undo meanwhile may move or take away a page.
        let ids = AudioMix.playedThrough(design: design, index: pageIndex)
            .filter { design.pages.indices.contains($0) }
            .map { design.pages[$0].id }
        previewEnded = onEnd
        previewRuns = true
        previewTask = Task { @MainActor in
            for id in ids {
                guard let index = design.pages.firstIndex(where: { $0.id == id }) else { break }
                setPage(index)
                guard await playOnce() else { break }
            }
            guard !Task.isCancelled else { return }
            previewTime = nil
            previewRuns = false
            endThrough()
        }
    }

    /// The page on screen played through once, on the clock as Play plays
    /// it; false when it was cut short — stopped, or another page brought
    /// up.
    @MainActor
    private func playOnce() async -> Bool {
        let playing = page.id
        let hold = pageHold
        let start = ContinuousClock.now
        while page.id == playing {
            let elapsed = ContinuousClock.now - start
            let t = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if t > hold { return true }
            previewTime = t
            try? await Task.sleep(for: .milliseconds(33))
            guard !Task.isCancelled else { return false }
        }
        return false
    }

    /// Give every selected element an entrance, staggered in layer order so
    /// a list builds itself rather than arriving as a block — a chart's
    /// parts given Grow sharing one delay and duration (ElementAnimation
    /// .applied).
    func animateSelected(_ kind: String?) {
        guard !selection.isEmpty else { return }
        applyToPage { page in
            let chosen = page.elements.indices.filter { self.selection.contains(page.elements[$0].id) }
            let animated = ElementAnimation.applied(chosen.map { page.elements[$0] }, kind: kind)
            for (i, el) in zip(chosen, animated) { page.elements[i] = el }
        }
    }

    /// Animate by: what the selected texts' text animations move as one —
    /// "letter", "word" or "line" — as one undo step, written as `by` even
    /// when it is the kind's own, as the Android twin writes it. Their exits
    /// of a unit kind go by it too.
    func animateSelected(by unit: String) {
        guard ElementAnimation.unitChoices.contains(unit) else { return }
        updateSelected { el in
            guard el.type == .text else { return }
            if var entrance = el.animation, ElementAnimation.textKinds.contains(entrance.kind) {
                entrance.by = unit
                el.animation = entrance
            }
            if var exit = el.exitAnimation, ElementAnimation.unitKinds.contains(exit.kind) {
                exit.by = unit
                el.exitAnimation = exit
            }
        }
    }

    /// Give every unlocked selected element a way out as the page ends, as
    /// one undo step, staggered in layer order so the first in is the last
    /// out; nil takes the exits away. A text's own way out (a unit kind)
    /// leaves anything but text as it is, and keeps what a text's exit
    /// moved by — as the Android twin's ElementAnimation.exited.
    func exitSelected(_ kind: String?) {
        guard unlockedSelectionCount > 0 else { return }
        applyToPage { page in
            var n = 0
            for i in page.elements.indices
            where self.selection.contains(page.elements[i].id) && !page.elements[i].locked {
                defer { n += 1 }
                let unitKind = kind.map { ElementAnimation.unitKinds.contains($0) } ?? false
                if unitKind && page.elements[i].type != .text { continue }
                let by = unitKind ? page.elements[i].exitAnimation?.by : nil
                page.elements[i].exitAnimation = kind.map {
                    ElementAnimation(kind: $0, delay: Double(n) * ElementAnimation.exitStagger,
                                     duration: ElementAnimation.exitDuration, by: by)
                }
            }
        }
    }

    // MARK: print bleed

    /// "Show print bleed" turned `on` — 3 mm at the design's dpi (Bleed) —
    /// or off, the key gone: a property of the design, so one step; nothing
    /// when it already is.
    func setBleed(_ on: Bool) {
        guard Bleed.shown(design) != on else { return }
        apply { $0 = Bleed.withBleed($0, on: on) }
    }

    // MARK: master page and guides

    /// Make the current page the master (or clear it), one undo step.
    func toggleMasterPage() {
        let id = page.id
        apply { $0.masterPageId = $0.masterPageId == id ? nil : id }
    }

    var isOnMasterPage: Bool { design.masterPageId == page.id }

    func toggleUsesMaster() {
        applyToPage { $0.usesMaster = $0.usesMaster == false ? nil : false }
    }

    /// A guide across the middle of the page, to be dragged from there.
    func addGuide(vertical: Bool) {
        addGuide(vertical: vertical, at: (vertical ? pageWidth / 2 : pageHeight / 2).rounded())
    }

    func addGuide(vertical: Bool, at position: Double) {
        apply { $0.guides.append(Guide(vertical: vertical, position: position)) }
        buzz(.confirm)
    }

    /// Slide a guide while dragging; commit() when the finger lifts.
    func moveGuideTransient(_ id: String, to position: Double) {
        beginGesture()
        if let i = design.guides.firstIndex(where: { $0.id == id }) {
            let limit = design.guides[i].vertical ? pageWidth : pageHeight
            design.guides[i].position = min(max(position, 0), limit).rounded()
        }
    }

    /// Put guide `id` at a typed `position`, kept on the page and on a half
    /// pixel as Android keeps it, as one undo step.
    func setGuidePosition(_ id: String, to position: Double) {
        guard let guide = design.guides.first(where: { $0.id == id }) else { return }
        let limit = max(guide.vertical ? pageWidth : pageHeight, 0)
        let kept = min(max(Guides.halfPixel(min(max(position, 0), limit)), 0), limit)
        guard kept != guide.position else { return }
        apply { d in
            if let i = d.guides.firstIndex(where: { $0.id == id }) { d.guides[i].position = kept }
        }
    }

    /// Columns and rows laid out as guides on this page (see Guides.layout),
    /// added to the guides there — or in their place, with `replace` — as
    /// one undo step. How many were added; none at all is no step.
    @discardableResult
    func addGuideLayout(columns: Int, rows: Int, gutter: Double, margin: Double, replace: Bool) -> Int {
        let kept = replace ? [] : design.guides
        let made = Guides.layout(size: pageSize, columns: columns, rows: rows,
                                 gutter: gutter, margin: margin, existing: kept)
        guard kept + made != design.guides else { return 0 }
        apply { $0.guides = kept + made }
        buzz(.confirm)
        return made.count
    }

    func removeGuide(_ id: String) {
        guard design.guides.contains(where: { $0.id == id }) else { return }
        apply { $0.guides.removeAll { $0.id == id } }
        buzz(.tick)
    }

    func clearGuides() {
        guard !design.guides.isEmpty else { return }
        apply { $0.guides.removeAll() }
    }

    // MARK: page clipboard

    /// Copying changes nothing on screen, so it is said and felt — as on
    /// the Android twin — rather than the menu closing on nothing.
    func copyPage() {
        copyPages([page.id])
    }

    /// The organiser's Copy: the pages `ids`, in the design's order, each
    /// with its own size, onto the pasteboard as one (PageClipboard.Pages)
    /// — hidden, locked, titled and noted as they are — and the fonts of
    /// your own on any of them.
    func copyPages(_ ids: Set<String>) {
        let picked = design.pages.filter { ids.contains($0.id) }
        guard !picked.isEmpty else { return }
        let entries = picked.map { page -> PageClipboard.CopiedPage in
            let size = design.size(for: page)
            return PageClipboard.CopiedPage(page: page, width: Double(size.width), height: Double(size.height))
        }
        let fonts = CustomFonts.carried(picked.flatMap(\.elements), from: design)
        PageClipboard.copy(PageClipboard.Pages(pages: entries, fonts: fonts))
        announce(picked.count == 1 ? tr("Page copied") : trn("%d page copied|%d pages copied", picked.count),
                 undoable: false)
        buzz(.confirm)
    }

    var hasPageOnClipboard: Bool { PageClipboard.hasPage() }

    /// Paste page, or — several copied as one — Paste pages.
    var pastePageTitle: String {
        (PageClipboard.copiedCount() ?? 1) > 1 ? tr("Paste pages") : tr("Paste page")
    }

    /// Paste the copied pages after the current one, in order, each scaled
    /// to this design (PageClipboard.landed), as one undo step; the first
    /// of them shown.
    func pastePage() {
        guard let copied = PageClipboard.pastePages() else { return }
        let landed = PageClipboard.landed(copied, width: design.width, height: design.height)
        guard !landed.isEmpty else { return }
        let at = pageIndex + 1
        // The fonts of your own they brought recorded with them, one step.
        apply { design in
            design.pages.insert(contentsOf: landed, at: at)
            design = CustomFonts.adopting(copied.fonts, into: design)
        }
        pageIndex = at
        selection.removeAll()
        buzz(.confirm)
    }

    func setPage(_ index: Int) {
        guard index >= 0 && index < design.pages.count && index != pageIndex else { return }
        endTextEdit()
        pageIndex = index
        selection.removeAll()
    }

    /// One page reflowed from one size to another: every element keeps its
    /// position on each axis as the split of the room around it — flush
    /// stays flush, centred stays centred — while sizes scale by the smaller
    /// ratio and keep their shape; text may widen to use a wider page.
    static func reflowedPage(_ page: Page, from old: CGSize, to new: CGSize) -> Page {
        let rx = new.width / max(old.width, 1), ry = new.height / max(old.height, 1)
        let s = min(rx, ry)
        /// Where on the new axis an element goes: the same share of the free
        /// room on either side as before; the centre's fraction when the
        /// element filled the axis and there was no room to share.
        func place(_ pos: Double, _ size: Double, _ oldAxis: Double, _ newSize: Double, _ newAxis: Double) -> Double {
            let room = oldAxis - size
            if room > 0.5 { return (newAxis - newSize) * (pos / room) }
            return (pos + size / 2) / max(oldAxis, 1) * newAxis - newSize / 2
        }
        var out = page
        for i in out.elements.indices {
            let el = out.elements[i]
            var e = el
            e.w = el.w * s
            e.h = el.h * s
            if let fs = el.fontSize { e.fontSize = fs * s }
            if let t = el.thickness { e.thickness = max(1, t * s) }
            // Everything else measured in page units, so a resized design
            // keeps its proportions — and before the text below is measured,
            // which the spacing changes. The Android twin does the same.
            if let ls = el.letterSpacing { e.letterSpacing = ls * s }
            if let r = el.radius { e.radius = r * s }
            if let c = el.corners { e.corners = c.map { $0 * s } }
            if let sw = el.strokeWidth { e.strokeWidth = sw * s }
            e.table = TableCell.scaledPad(el.table, by: s)
            if el.type == .text, rx > s {
                e.w = min(el.w * rx, new.width)
                e.h = FontLibrary.layoutHeight(for: e)
            }
            e.x = place(el.x, el.w, old.width, e.w, new.width)
            e.y = place(el.y, el.h, old.height, e.h, new.height)
            // Never off the page.
            e.x = min(max(e.x, 0), max(new.width - e.w, 0))
            e.y = min(max(e.y, 0), max(new.height - e.h, 0))
            out.elements[i] = e
        }
        return out
    }

    /// One page scaled uniformly to fit a new size and centred, so a change
    /// of shape leaves margins rather than pushing content off the page.
    static func scaledPage(_ page: Page, from old: CGSize, to new: CGSize) -> Page {
        let scale = min(new.width / max(old.width, 1), new.height / max(old.height, 1))
        let dx = (new.width - old.width * scale) / 2
        let dy = (new.height - old.height * scale) / 2
        var out = page
        for i in out.elements.indices {
            let el = out.elements[i]
            out.elements[i] = el.scaledSizes(by: scale)
            out.elements[i].x = el.x * scale + dx
            out.elements[i].y = el.y * scale + dy
        }
        return out
    }

    /// Reflow the whole design to a new canvas rather than scaling the old
    /// one onto it (see `reflowedPage`); pages with a size of their own are
    /// brought to the new size too. Pure; `magicResize` commits it.
    static func reflowed(_ design: Design, width: Double, height: Double) -> Design {
        guard width > 0, height > 0 else { return design }
        let new = CGSize(width: width, height: height)
        var out = design
        out.width = width
        out.height = height
        for p in out.pages.indices {
            out.pages[p] = reflowedPage(design.pages[p], from: design.size(for: design.pages[p]), to: new)
            out.pages[p].width = nil
            out.pages[p].height = nil
        }
        let rx = width / max(design.width, 1), ry = height / max(design.height, 1)
        out.guides = out.guides.map { g in
            var g2 = g
            g2.position = g.vertical ? g.position * rx : g.position * ry
            return g2
        }
        return out
    }

    func magicResize(width: Double, height: Double) {
        reflowWhole(width: width, height: height, units: nil)
    }

    /// Reflowed in place, and the design takes that unit and dpi in the same
    /// step — an A4 size chosen makes it an A4 page.
    func magicResize(width: Double, height: Double, units: UnitChoice) {
        reflowWhole(width: width, height: height, units: units)
    }

    private func reflowWhole(width: Double, height: Double, units: UnitChoice?) {
        guard width != design.width || height != design.height || design.hasMixedPageSizes
                || changesUnits(units) else { return }
        var next = Self.reflowed(design, width: width, height: height)
        if let units {
            next.unit = units.unit
            next.dpi = units.dpi
        }
        apply { $0 = next }
        announce(tr("Reflowed to %@", "\(Int(width)) × \(Int(height))"))
        buzz(.confirm)
    }

    /// Whether `units` would change the design's unit or dpi.
    private func changesUnits(_ units: UnitChoice?) -> Bool {
        guard let units else { return false }
        return units.unit != design.unit || units.dpi != design.dpi
    }

    /// Uniformly rescale all content to a new canvas size. Scaling to *fit*
    /// (and centring on both axes) keeps content on the page when the aspect
    /// ratio changes; scaling by width alone would push it off the bottom.
    func resizeDesign(width: Double, height: Double) {
        scaleWhole(width: width, height: height, units: nil)
    }

    /// The same, the design taking that unit and dpi in the same step.
    func resizeDesign(width: Double, height: Double, units: UnitChoice) {
        scaleWhole(width: width, height: height, units: units)
    }

    private func scaleWhole(width: Double, height: Double, units: UnitChoice?) {
        guard width != design.width || height != design.height || design.hasMixedPageSizes
                || changesUnits(units) else { return }
        let new = CGSize(width: width, height: height)
        apply { d in
            if let units {
                d.unit = units.unit
                d.dpi = units.dpi
            }
            // Guides go where the content they line up goes: scaled with the
            // page and centred with it. Left where they were, they sat on
            // empty space after a change of shape.
            let s = min(width / max(d.width, 1), height / max(d.height, 1))
            let dx = (width - d.width * s) / 2, dy = (height - d.height * s) / 2
            d.guides = d.guides.map { g in
                var g2 = g
                g2.position = g.position * s + (g.vertical ? dx : dy)
                return g2
            }
            for p in d.pages.indices {
                d.pages[p] = Self.scaledPage(d.pages[p], from: d.size(for: d.pages[p]), to: new)
                d.pages[p].width = nil
                d.pages[p].height = nil
            }
            d.width = width
            d.height = height
        }
        // Said with its Undo, as Reflow and a one-page resize are: every
        // page of the design just changed at once.
        announce(tr("Resized to %@", "\(Int(width)) × \(Int(height))"))
        buzz(.confirm)
    }

    /// This page alone takes a new size — a story after a square post — with
    /// its content reflowed or scaled onto it. The document's own size is
    /// what the other pages keep; choosing it again clears the override.
    func resizePage(width: Double, height: Double, reflow: Bool) {
        let old = pageSize
        let new = CGSize(width: width, height: height)
        guard new != old, width > 0, height > 0 else { return }
        let index = pageIndex
        apply { d in
            var pg = reflow ? Self.reflowedPage(d.pages[index], from: old, to: new)
                            : Self.scaledPage(d.pages[index], from: old, to: new)
            let isDocument = width == d.width && height == d.height
            pg.width = isDocument ? nil : width
            pg.height = isDocument ? nil : height
            d.pages[index] = pg
        }
        announce(tr("This page is now %@", "\(Int(width)) × \(Int(height))"))
        buzz(.confirm)
    }
}

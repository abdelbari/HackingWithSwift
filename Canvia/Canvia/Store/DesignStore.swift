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
        // (TimelineEditing), as the Android twin's playhead follows the page.
        didSet {
            if pageIndex != oldValue {
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
        }
    }
    var editingTextId: String?
    /// The words the colour sheet is open for, from the typing bar's colour
    /// well (see WordStyles).
    var wordColourTarget: WordRange?
    /// The words the font sheet is open for, from the typing bar's Aa.
    var wordFontTarget: WordRange?
    /// The words the link prompt is open for, from the typing bar's Link.
    var wordLinkTarget: WordRange?
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
    }
    private var past: [HistoryEntry] = []
    private var future: [HistoryEntry] = []
    private var pending: HistoryEntry?
    private let historyLimit = 100
    /// The shape being typed in, as it was before the typing began: what a
    /// shape left with no words goes back to, though a style pressed while
    /// typing has closed the step it began in — as on the Android twin.
    @ObservationIgnored private var typedShapeBefore: Element?
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
            pending = HistoryEntry(design: design, pageIndex: pageIndex)
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
        guard let entry = pending else { return }
        // A table's rows follow its words, and connectors their ends, as
        // part of the same step.
        design = DataGraphics.settlingTables(design, since: entry.design, heightFor: measure)
        Connectors.resolve(in: &design)
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
        past.append(entry)
        if past.count > historyLimit { past.removeFirst() }
        future.removeAll()
        pending = nil
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

    /// Mutate the current page + record one undo step.
    func applyToPage(_ mutate: (inout Page) -> Void) {
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
        out.h = ShapeText.heightForWords(el)
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
            || a.spans != b.spans
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
            announce("Select two things to connect", undoable: false)
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
        announce("Connected — the arrow follows both ends")
    }

    var canUndo: Bool { !past.isEmpty }

    /// Moves with every step recorded, undone, redone or thrown away. An
    /// Undo offered in a toast is only honest while this is what it was
    /// when the offer was made, as on the Android twin.
    private(set) var historyVersion = 0
    var canRedo: Bool { !future.isEmpty }

    func undo() {
        // Typing, dictation or a crop under way is kept as its own step
        // first, so Undo takes back that rather than whatever came before
        // it — and the words typed are never thrown away with that step.
        closeOpenSteps()
        guard let entry = past.popLast() else { return }
        future.append(HistoryEntry(design: design, pageIndex: pageIndex))
        restore(entry)
        buzz(.undo)
    }

    func redo() {
        closeOpenSteps()
        guard let entry = future.popLast() else { return }
        past.append(HistoryEntry(design: design, pageIndex: pageIndex))
        restore(entry)
        buzz(.redo)
    }

    /// Whatever is still open — typing, dictation, a crop, a slider's step
    /// — closed as its own step, as the Android twin does before Undo.
    private func closeOpenSteps() {
        endTextEdit()
        endDictation()
        finishCrop()
        commit()
    }

    private func restore(_ entry: HistoryEntry) {
        historyVersion += 1
        design = entry.design
        // An undone step brings words back rather than typing them: it never
        // renames the design.
        lastWords = Self.words(of: design)
        pageIndex = min(entry.pageIndex, design.pages.count - 1)
        // Undo and Redo close any typing first; this only makes sure a box
        // being typed into is not ended by the selection below as a step.
        editingTextId = nil
        pending = nil
        let ids = Set(page.elements.map(\.id))
        selection = selection.intersection(ids)
        onCommit?()
    }

    // MARK: selection

    func select(_ id: String?, additive: Bool = false) {
        endTextEdit()
        guard let id else {
            selection.removeAll()
            return
        }
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
    }

    /// A tap on one member of a group that is already selected goes inside
    /// it, as in Canva and on the Android twin: the first tap takes the
    /// group, the next the thing tapped. A drag still moves the whole group.
    /// True when the tap was taken that way.
    @discardableResult
    func selectMember(_ id: String) -> Bool {
        guard selection.count > 1, selection.contains(id), element(id)?.group != nil else { return false }
        endTextEdit()
        selection = [id]
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
    /// takes their look in this same step (ShapeText.starting), so starting,
    /// typing and leaving are one Undo.
    func startTyping(_ id: String) {
        endTextEdit()
        selection = [id]
        beginGesture()
        editingTextId = id
        typedShapeBefore = design.pages[pageIndex].elements.first { $0.id == id && $0.type == .shape }
        guard let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == id }),
              ShapeText.takesText(design.pages[pageIndex].elements[i]),
              (design.pages[pageIndex].elements[i].text ?? "").isEmpty else { return }
        design.pages[pageIndex].elements[i] = ShapeText.starting(design.pages[pageIndex].elements[i])
    }

    /// The words typed in place, into the open step: a text box measured
    /// to them, a shape grown down when they need more room than it has.
    func typeWords(_ words: String, into id: String) {
        beginGesture()
        guard let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == id }),
              design.pages[pageIndex].elements[i].text != words else { return }
        design.pages[pageIndex].elements[i].setText(words)
        design.pages[pageIndex].elements[i].h = ShapeText.heightForWords(design.pages[pageIndex].elements[i])
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

    func add(_ element: Element, centered: Bool = true) {
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
        applyToPage { page in
            page.elements.removeAll { ids.contains($0.id) }
        }
        selection.subtract(ids)   // anything locked stays selected, visibly
        // The Android twin's words, so both phones say the same.
        announce(ids.count == 1 ? "Deleted" : "Deleted \(ids.count) things")
    }

    func duplicateSelected() {
        let copies = Copies.of(selectedElements.filter { !$0.locked }, offset: 24)
        guard !copies.isEmpty else { return }
        applyToPage { $0.elements.append(contentsOf: copies) }
        selection = Set(copies.map(\.id))
    }


    // MARK: clipboard

    var hasClipboard: Bool { !clipboard.isEmpty || ElementClipboard.hasContent() }

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
        case .shape where Freehand.isStroke(el):
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
            // Letters draw a gradient and nothing else: a pattern or a photo
            // fill picked for a mixed selection is the shapes', and on the
            // text would be saved and never shown.
            guard paint.kind == "gradient" else { return el }
            e.textFill = paint
        } else {
            e.fill = paint
        }
        return e
    }
    var canDistribute: Bool { movableSelectionCount >= 3 }

    func copySelected() {
        let selected = selectedElements
        guard !selected.isEmpty else { return }
        clipboard = selected
        clipboardPage = page.id
        clipboardFonts = CustomFonts.carried(selected, from: design)
        pastedOnto = nil
        pasteCount = 0
        ElementClipboard.write(selected, sourcePage: page.id, fonts: clipboardFonts)
        buzz(.tick)
        announce(selected.count == 1 ? "Copied" : "Copied \(selected.count) things", undoable: false)
    }

    func cutSelected() {
        // Cut takes exactly what it removes, so a locked element is never
        // both left behind and on the clipboard. A cut is a move by way of
        // the clipboard, so, as with Move to page, a position lock stays
        // too, as on the Android twin (its DesignStore.cutSelected).
        let removable = selectedElements.filter { !$0.holdsPlace }
        guard !removable.isEmpty else {
            if !selection.isEmpty { buzz(.reject) }
            return
        }
        clipboard = removable
        clipboardPage = page.id
        clipboardFonts = CustomFonts.carried(removable, from: design)
        pastedOnto = nil
        pasteCount = 0
        ElementClipboard.write(removable, sourcePage: page.id, fonts: clipboardFonts)
        let ids = Set(removable.map(\.id))
        applyToPage { page in
            page.elements.removeAll { ids.contains($0.id) }
        }
        selection.subtract(ids)
        announce(ids.count == 1 ? "Cut" : "Cut \(ids.count) things")
    }

    func paste() {
        // Our own copy first; otherwise whatever another app left: a
        // picture, or some text.
        if clipboard.isEmpty {
            if let mine = ElementClipboard.read() {
                clipboard = mine
                clipboardPage = ElementClipboard.sourcePage()
                clipboardFonts = ElementClipboard.fonts()
                pastedOnto = nil
                pasteCount = 0
            } else if let stranger = ElementClipboard.foreign(designWidth: pageWidth) {
                add(stranger)
                return
            }
        }
        guard !clipboard.isEmpty else {
            // Said, as the Android twin says it: from the keyboard there is
            // no greyed-out menu item to tell you.
            buzz(.reject)
            announce(UIPasteboard.general.hasImages ? "Couldn't paste that picture" : "Nothing to paste",
                     undoable: false)
            return
        }
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
        let copies = Copies.of(clipboard, offset: offset)
        let fonts = clipboardFonts
        // The fonts of your own they brought recorded with them, one step.
        apply { design in
            design.pages[self.pageIndex].elements.append(contentsOf: copies)
            design = CustomFonts.adopting(fonts, into: design)
        }
        selection = Set(copies.map(\.id))
    }

    func selectAll() {
        endTextEdit()
        selection = Set(page.elements.filter { !$0.locked && !$0.isHidden }.map(\.id))
    }

    /// Rubber-band selection: everything the rectangle touches, with sticky
    /// groups expanded so a band across one member takes the whole group.
    func select(within rect: CGRect) {
        endTextEdit()
        var ids = Set(Geometry.intersecting(page.elements, rect).map(\.id))
        let groups = Set(page.elements.filter { ids.contains($0.id) }.compactMap(\.group))
        for el in page.elements where el.group.map(groups.contains) == true {
            ids.insert(el.id)
        }
        selection = ids
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
    // member selects the whole group (see select(_:additive:)).

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
        applyToPage { page in
            for i in page.elements.indices
            where self.selection.contains(page.elements[i].id) && !page.elements[i].locked {
                page.elements[i].group = gid
            }
        }
    }

    func ungroupSelected() {
        guard selectedElements.contains(where: { $0.group != nil }) else { return }
        buzz(.grouped)
        applyToPage { page in
            for i in page.elements.indices where self.selection.contains(page.elements[i].id) {
                page.elements[i].group = nil
            }
        }
    }

    enum ZMove { case front, forward, backward, back }

    func reorderSelected(_ move: ZMove) {
        let ids = selection
        guard !ids.isEmpty else { return }
        applyToPage { page in
            switch move {
            case .front:
                let moved = page.elements.filter { ids.contains($0.id) }
                page.elements.removeAll { ids.contains($0.id) }
                page.elements.append(contentsOf: moved)
            case .back:
                let moved = page.elements.filter { ids.contains($0.id) }
                page.elements.removeAll { ids.contains($0.id) }
                page.elements.insert(contentsOf: moved, at: 0)
            case .forward:
                var i = page.elements.count - 2
                while i >= 0 {
                    if ids.contains(page.elements[i].id) && !ids.contains(page.elements[i + 1].id) {
                        page.elements.swapAt(i, i + 1)
                    }
                    i -= 1
                }
            case .backward:
                for i in 1..<max(1, page.elements.count) {
                    if ids.contains(page.elements[i].id) && !ids.contains(page.elements[i - 1].id) {
                        page.elements.swapAt(i, i - 1)
                    }
                }
            }
        }
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
    /// The gap is a fiftieth of the page's shorter side: visible, not loose.
    func tidySelected(_ mode: Geometry.TidyMode) {
        let members = selectedElements.filter { !$0.holdsPlace }
        guard members.count >= 2 else { return }
        let gap = (min(pageWidth, pageHeight) / 50).rounded()
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

    /// Turn the whole selection about its centre by `degrees`, one undo step.
    func rotateSelection(by degrees: Double) {
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

    /// Something just happened that a first-timer might want a word about.
    /// The editor hands it to TipEngine, which decides whether to say it.
    var tipEvent: TipEvent?
    /// A change worth feeling; the editor turns it into haptics.
    var haptic = HapticEvent(kind: .undo, serial: 0)
    /// True while a rotation drag sits on a 45° snap.
    var rotationSnapped = false
    /// True while a move sits at an equal gap between two neighbours.
    var spacingSnapped = false
    /// The pen, while drawing mode is on: strokes become shape elements.
    var drawing: Freehand.Tool? {
        didSet { if let drawing { lastPen = drawing } }
    }
    /// The last pen used, so the next drawing session picks it up again.
    @ObservationIgnored private var lastPen = Freehand.Tool()
    /// The photo in crop mode, and the size of its picture — see
    /// CropMode.swift. Crop mode is one open step: everything done in it is
    /// live, Done keeps it as a single Undo, and Cancel throws it away.
    var cropping: CropSession?
    /// The image being erased from, while the eraser is out, and the
    /// strokes painted over it so far, in page units.
    var erasing: String?
    var eraserStrokes: [[CGPoint]] = []
    var eraserWidth: Double = 40
    var eraserBusy = false

    func beginErasing(_ id: String) {
        if element(id)?.locked == true {
            buzz(.reject)
            announce("This photo is locked. Tap Unlock to edit it.", undoable: false)
            return
        }
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
                guard !text.isEmpty else { self.announce("No words were recognised in the strokes", undoable: false); return }
                let frame = rendered.frame
                let size = max(12, (frame.height / Double(max(lines.count, 1)) * 0.6).rounded())
                var el = Element.text(text, fontSize: size, w: max(60, frame.width.rounded()))
                el.align = "left"
                el.x = frame.minX.rounded(); el.y = frame.minY.rounded()
                el.h = FontLibrary.layoutHeight(for: el)
                self.apply { d in
                    d.pages[index].elements.removeAll { ids.contains($0.id) }
                    d.pages[index].elements.append(el)
                }
                self.selection = [el.id]
                self.announce("Handwriting became text — Undo keeps the strokes")
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
                    self.announce("The photo is no longer on this page", undoable: false)
                    return
                }
                // Locked meanwhile: kept as it is, and nothing said to have
                // been erased.
                guard !now.locked else { return }
                guard let src else {
                    self.buzz(.reject)
                    self.announce("Nothing to erase there", undoable: false)
                    return
                }
                self.selection = [id]
                self.updateSelected { $0.src = src }
                self.buzz(.confirm)
                self.announce("Erased — Undo brings it back")
            }
        }
    }

    func buzz(_ kind: HapticEvent.Kind) {
        haptic = HapticEvent(kind: kind, serial: haptic.serial + 1)
    }

    func toggleDrawing() {
        if drawing == nil {
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
        if let tool = drawing, tool.pen == .eraser {
            eraseStrokes(points, radius: Freehand.eraserRadius(tool))
            return
        }
        guard let tool = drawing, let el = Freehand.element(points: points, tool: tool) else { return }
        add(el, centered: false)
        selection.removeAll()
        if tipEvent == nil { tipEvent = .drewStroke }
        buzz(.stroke)
    }

    /// The strokes an eraser swept over go, all of them one undo step.
    func eraseStrokes(_ points: [CGPoint], radius: Double) {
        let gone = Freehand.erased(page.elements, path: points, radius: radius)
        guard !gone.isEmpty else { return }
        applyToPage { $0.elements.removeAll { gone.contains($0.id) } }
        selection.removeAll()
        buzz(.stroke)
        announce(gone.count == 1 ? "Erased a stroke" : "Erased \(gone.count) strokes")
    }

    func announce(_ text: String, undoable: Bool = true) {
        announcementUndoes = undoable
        announcement = text
    }

    /// Replace the whole document with a saved version, as one undo step —
    /// restoring is itself an edit, and one you might want to take back.
    func restore(_ version: Design) {
        var restored = version
        restored.id = design.id
        restored.updatedAt = Date().timeIntervalSince1970 * 1000
        apply { $0 = restored }
        pageIndex = min(pageIndex, max(design.pages.count - 1, 0))
        selection.removeAll()
        announce("Restored an earlier version")
    }

    // MARK: find and replace

    /// Where one match lives, so a caller can jump to it.
    struct TextMatch: Equatable, Identifiable {
        var id: String { "\(pageIndex)|\(elementId)|\(range.location)" }
        var pageIndex: Int
        var elementId: String
        /// Where it is stored, its style markers taken in
        /// (RichText.storedRange).
        var range: NSRange
        /// Where it is in the words as they read.
        var plain: NSRange
        /// The line the match sits on, as it reads, for showing it in a list.
        var preview: String
    }

    /// The match Find and replace is showing, its letters marked on the
    /// canvas while it is. View state only — never saved.
    var findHighlight: TextMatch?

    /// Every occurrence of `needle` across every page, in reading order:
    /// in text boxes, and in the words shapes carry — not in a hidden or
    /// locked one (FindReplace.searches) — as the words read, style markers
    /// left out (FindReplace.matches). With `wholeWord`, only where no
    /// letter or digit touches it (FindReplace.ranges).
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
        for (index, page) in design.pages.enumerated() {
            for element in page.elements where FindReplace.searches(element) {
                let body = element.text ?? ""
                let plain = RichText.strip(body)
                for hit in FindReplace.matches(of: needle, in: body, caseSensitive: caseSensitive, wholeWord: wholeWord) {
                    found.append(TextMatch(pageIndex: index, elementId: element.id, range: hit.stored,
                                           plain: hit.plain, preview: line(of: plain, containing: hit.plain)))
                }
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
        let total = matches(for: needle, caseSensitive: caseSensitive, wholeWord: wholeWord).count
        guard total > 0 else { return 0 }
        apply { design in
            for p in design.pages.indices {
                for i in design.pages[p].elements.indices
                where FindReplace.searches(design.pages[p].elements[i]) {
                    guard let body = design.pages[p].elements[i].text, !body.isEmpty else { continue }
                    let found = FindReplace.ranges(of: needle, in: RichText.strip(body),
                                                   caseSensitive: caseSensitive, wholeWord: wholeWord)
                    guard !found.isEmpty else { continue }
                    // One occurrence at a time, the last first, so the
                    // colours, sizes, fonts and links on the words between
                    // them stay on those words, and the words as they read
                    // before each are still where they were found.
                    for hit in found.reversed() {
                        Self.replaceWords(hit, with: replacement, in: &design.pages[p].elements[i])
                    }
                }
            }
        }
        findHighlight = nil
        announce(total == 1 ? "Replaced 1 occurrence" : "Replaced \(total) occurrences")
        return total
    }

    /// The design with only `match` replaced — the words around it, their
    /// markers and the colours, sizes, fonts and links on them as they were
    /// (FindReplace.replacing; Element.setText moves them along) — or nil
    /// when the match is no longer in the design to replace.
    static func replacingOne(_ design: Design, _ match: TextMatch, with replacement: String) -> Design? {
        guard design.pages.indices.contains(match.pageIndex),
              let i = design.pages[match.pageIndex].elements.firstIndex(where: { $0.id == match.elementId }),
              FindReplace.searches(design.pages[match.pageIndex].elements[i]) else { return nil }
        let body = design.pages[match.pageIndex].elements[i].text ?? ""
        let length = (RichText.strip(body) as NSString).length
        guard match.plain.length > 0, NSMaxRange(match.plain) <= length,
              RichText.storedRange(of: match.plain, in: body) == match.range else { return nil }
        var out = design
        replaceWords(match.plain, with: replacement, in: &out.pages[match.pageIndex].elements[i])
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
        el.h = ShapeText.heightForWords(el)
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
    /// letters there (findHighlight); the editor keeps it in sight.
    func reveal(_ match: TextMatch) {
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

    static func style(of el: Element) -> Style {
        Style(fill: el.fill, stroke: el.stroke, strokeWidth: el.strokeWidth, radius: el.radius,
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
    }

    /// Apply a style, keeping everything that makes the element itself.
    ///
    /// Fields that belong to another kind of element are left alone rather
    /// than copied across: pasting a text style onto a rectangle should change
    /// nothing about the rectangle, not give it a font.
    static func apply(_ style: Style, to el: inout Element) {
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
        case .line:
            el.color = style.color
            el.thickness = style.thickness
            el.dash = style.dash
            el.startCap = style.startCap
            el.endCap = style.endCap
            if let thickness = style.thickness { el.h = max(8, thickness) }
        case .sticker:
            break
        }
    }

    func copyStyle() {
        guard let el = singleSelection else { return }
        copiedStyle = Self.style(of: el)
        buzz(.tick)
    }

    func pasteStyle() {
        guard let style = copiedStyle else { return }
        updateSelected { Self.apply(style, to: &$0) }
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
    /// LayerRows.moved).
    func moveLayers(_ rows: [LayerRows.Row], from source: IndexSet, to destination: Int) {
        let reordered = LayerRows.moved(page.elements, rows: rows, from: source, to: destination)
        guard reordered.map(\.id) != page.elements.map(\.id) else { return }
        applyToPage { $0.elements = reordered }
    }

    /// Take the element `id` alone, from its Layers row — a group's member
    /// without the rest of the group.
    func selectLayer(_ id: String) {
        endTextEdit()
        selection = [id]
    }

    func flipSelected(horizontal: Bool) {
        guard unlockedSelectionCount > 0 else { return }
        buzz(.tick)
        updateSelected { el in
            if horizontal { el.flipH.toggle() } else { el.flipV.toggle() }
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

    /// A template's pages, fitted to this page, applied as one undo step:
    /// the first takes this page's place — its background and everything on
    /// it — and the rest are added after it, in order, each at this page's
    /// size.
    func applyTemplatePages(_ pages: [Page], name: String) {
        guard !pages.isEmpty else { return }
        let at = pageIndex
        apply { $0 = Self.appliedTemplate($0, pages: pages, at: at) }
        selection.removeAll()
        buzz(.confirm)
        announce(pages.count == 1 ? "Started over from \u{201C}\(name)\u{201D}"
                 : "Applied all \(pages.count) pages of \u{201C}\(name)\u{201D}")
    }

    /// The design with `pages` applied at page `index`, as above. Pure.
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
        announce("Deleted page \(number)")
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

    /// Delete several pages in one undo step, never the last one.
    func deletePages(_ ids: Set<String>) {
        let victims = design.pages.filter { ids.contains($0.id) }
        guard !victims.isEmpty, victims.count < design.pages.count else { return }
        let currentId = page.id
        apply { $0.pages.removeAll { ids.contains($0.id) } }
        pageIndex = design.pages.firstIndex { $0.id == currentId } ?? min(pageIndex, design.pages.count - 1)
        selection.removeAll()
        announce(victims.count == 1 ? "Deleted 1 page" : "Deleted \(victims.count) pages")
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
    /// text given the pairing's faces at their own sizes. Pure, so the sheet
    /// can preview it before anyone commits.
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
        return out
    }

    /// The brand face for each text size, by rank: the sizes, once each and
    /// largest first, take the kit's ranked roles in turn — title, heading,
    /// subheading, body, those it sets — and every size past the last role
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
        announce("Applied theme to \(design.pages.count == 1 ? "the page" : "all \(design.pages.count) pages")")
    }

    // MARK: components

    /// Save the selection as a component, keeping nothing locked in it.
    @discardableResult
    func saveSelectionAsComponent(named name: String) -> Component? {
        let saved = Components.add(named: name, from: selectedElements)
        if let saved {
            buzz(.confirm)
            announce("Saved \u{201C}\(saved.name)\u{201D} to Components", undoable: false)
        }
        return saved
    }

    /// Drop a component onto the page at half its width, centred.
    func insertComponent(_ component: Component) {
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
        let made = TextCombos.measured(TextCombos.placed(combo, pageWidth: pageWidth, pageHeight: pageHeight))
        guard !made.isEmpty else { return }
        applyToPage { $0.elements.append(contentsOf: made) }
        selection = Set(made.map(\.id))
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
    func applyBrandFace(_ face: BrandFont) {
        let width = pageWidth
        updateSelected { el in BrandFonts.apply(face, to: &el, pageWidth: width) }
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
        let span = ElementAnimation.exitSpan(design.masterElements(behind: page) + page.elements)
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
        previewSound.page(AudioMix.clips(design: design, page: page), since: since)
        previewSound.tracks(design: design, offset: AudioMix.pageStart(design: design, index: pageIndex), since: since,
                            film: AudioMix.filmLength(design: design))
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
            previewSound.stop()
        }
    }

    /// The selected clip's trim, speed, loop, volume and mute, as one undo
    /// step. A clip at all the defaults keeps none, so its file has no
    /// `clip` key.
    func setClip(_ clip: ClipPlayback) {
        updateSelected { el in
            guard VideoStore.isVideo(el.src) else { return }
            el.clip = clip.isDefault ? nil : clip
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
        previewTask = Task { @MainActor in
            for id in ids {
                guard let index = design.pages.firstIndex(where: { $0.id == id }) else { break }
                setPage(index)
                guard await playOnce() else { break }
            }
            guard !Task.isCancelled else { return }
            previewTime = nil
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
    /// a list builds itself rather than arriving as a block.
    func animateSelected(_ kind: String?) {
        guard !selection.isEmpty else { return }
        applyToPage { page in
            var n = 0
            for i in page.elements.indices where self.selection.contains(page.elements[i].id) {
                if let kind {
                    let textOnly = ElementAnimation.textKinds.contains(kind)
                    if textOnly && page.elements[i].type != .text { continue }
                    page.elements[i].animation = ElementAnimation(kind: kind, delay: Double(n) * 0.15, duration: 0.6)
                    n += 1
                } else {
                    page.elements[i].animation = nil
                }
            }
        }
    }

    /// Give every unlocked selected element a way out as the page ends, as
    /// one undo step, staggered in layer order so the first in is the last
    /// out; nil takes the exits away.
    func exitSelected(_ kind: String?) {
        guard unlockedSelectionCount > 0 else { return }
        applyToPage { page in
            var n = 0
            for i in page.elements.indices
            where self.selection.contains(page.elements[i].id) && !page.elements[i].locked {
                page.elements[i].exitAnimation = kind.map {
                    ElementAnimation(kind: $0, delay: Double(n) * ElementAnimation.exitStagger,
                                     duration: ElementAnimation.exitDuration)
                }
                n += 1
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
        PageClipboard.copy(page, width: pageWidth, height: pageHeight,
                           fonts: CustomFonts.carried(page.elements, from: design))
        announce("Page copied", undoable: false)
        buzz(.confirm)
    }

    var hasPageOnClipboard: Bool { PageClipboard.hasPage() }

    /// Paste the copied page after the current one, scaled to this design.
    func pastePage() {
        guard let payload = PageClipboard.paste() else { return }
        let landed = PageClipboard.fitted(payload, width: pageWidth, height: pageHeight)
        let at = pageIndex + 1
        // The fonts of your own it brought recorded with it, one step.
        apply { design in
            design.pages.insert(landed, at: at)
            design = CustomFonts.adopting(payload.fonts ?? [], into: design)
        }
        pageIndex += 1
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
        announce("Reflowed to \(Int(width)) × \(Int(height))")
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
        announce("Resized to \(Int(width)) × \(Int(height))")
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
        announce("This page is now \(Int(width)) × \(Int(height))")
        buzz(.confirm)
    }
}

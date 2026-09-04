// Central editor state. Design is a value type, so history entries are
// plain copies. Gesture coalescing mirrors the web store: beginGesture()
// captures the pre-gesture doc, transient mutations happen freely, and one
// commit() records a single undo step.

import SwiftUI
import Observation

@Observable
final class DesignStore {
    var design: Design
    var pageIndex: Int = 0
    var selection: Set<String> = []
    var editingTextId: String?
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
    var badge: String?

    /// When set, the next picked image replaces this element's source
    /// instead of inserting a new image.
    var replaceTargetId: String?

    private var clipboard: [Element] = []
    private var pasteCount = 0

    private struct HistoryEntry {
        var design: Design
        var pageIndex: Int
    }
    private var past: [HistoryEntry] = []
    private var future: [HistoryEntry] = []
    private var pending: HistoryEntry?
    private let historyLimit = 100

    var onCommit: (() -> Void)?

    init(design: Design) {
        self.design = design
    }

    var page: Page {
        get { design.pages[min(pageIndex, design.pages.count - 1)] }
        set { design.pages[min(pageIndex, design.pages.count - 1)] = newValue }
    }

    func element(_ id: String) -> Element? {
        page.elements.first { $0.id == id }
    }

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

    func commit() {
        // Without a beginGesture() snapshot there is no pre-mutation state to
        // record — pushing the current design would make undo a no-op.
        guard let entry = pending else { return }
        past.append(entry)
        if past.count > historyLimit { past.removeFirst() }
        future.removeAll()
        pending = nil
        design.updatedAt = Date().timeIntervalSince1970 * 1000
        onCommit?()
    }

    /// End a gesture that changed nothing, without recording history.
    func endGesture() {
        pending = nil
    }

    /// Mutate + record as one undo step.
    func apply(_ mutate: (inout Design) -> Void) {
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
    func updateSelected(_ mutate: (inout Element) -> Void) {
        guard !selection.isEmpty else { return }
        applyToPage { page in
            for i in page.elements.indices
            where self.selection.contains(page.elements[i].id) && !page.elements[i].locked {
                mutate(&page.elements[i])
            }
        }
    }

    /// Transient variant for continuous controls; call commit() on release.
    func updateSelectedTransient(_ mutate: (inout Element) -> Void) {
        beginGesture()
        for i in design.pages[pageIndex].elements.indices
        where selection.contains(design.pages[pageIndex].elements[i].id)
            && !design.pages[pageIndex].elements[i].locked {
            mutate(&design.pages[pageIndex].elements[i])
        }
    }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    func undo() {
        guard let entry = past.popLast() else { return }
        future.append(HistoryEntry(design: design, pageIndex: pageIndex))
        restore(entry)
    }

    func redo() {
        guard let entry = future.popLast() else { return }
        past.append(HistoryEntry(design: design, pageIndex: pageIndex))
        restore(entry)
    }

    private func restore(_ entry: HistoryEntry) {
        design = entry.design
        pageIndex = min(entry.pageIndex, design.pages.count - 1)
        let ids = Set(page.elements.map(\.id))
        selection = selection.intersection(ids)
        editingTextId = nil
        pending = nil
        onCommit?()
    }

    // MARK: selection

    func select(_ id: String?, additive: Bool = false) {
        editingTextId = nil
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
            el.x = (design.width - el.w) / 2
            el.y = (design.height - el.h) / 2
        }
        applyToPage { $0.elements.append(el) }
        selection = [el.id]
    }

    func deleteSelected() {
        // Only unlocked elements go; committing when nothing can be removed
        // would push a history entry identical to the previous one.
        let ids = Set(selectedElements.filter { !$0.locked }.map(\.id))
        guard !ids.isEmpty else { return }
        applyToPage { page in
            page.elements.removeAll { ids.contains($0.id) }
        }
        selection.subtract(ids)   // anything locked stays selected, visibly
        announce(ids.count == 1 ? "Deleted 1 element" : "Deleted \(ids.count) elements")
    }

    func duplicateSelected() {
        let copies = Self.remapGroups(selectedElements.filter { !$0.locked }.map { $0.duplicated() })
        guard !copies.isEmpty else { return }
        applyToPage { $0.elements.append(contentsOf: copies) }
        selection = Set(copies.map(\.id))
    }

    /// Copies must not stay welded to the source's group: re-key each source
    /// group, preserving grouping *within* the copies.
    private static func remapGroups(_ elements: [Element]) -> [Element] {
        var map: [String: String] = [:]
        return elements.map { element in
            guard let group = element.group else { return element }
            if map[group] == nil { map[group] = UID.make("grp") }
            var copy = element
            copy.group = map[group]
            return copy
        }
    }

    // MARK: clipboard

    var hasClipboard: Bool { !clipboard.isEmpty || ElementClipboard.hasContent() }

    /// Commands that move elements ignore locked ones, so the UI must gate on
    /// the unlocked subset or it offers controls that quietly do nothing.
    var unlockedSelectionCount: Int { selectedElements.filter { !$0.locked }.count }
    var canGroup: Bool { unlockedSelectionCount >= 2 }
    var canDistribute: Bool { unlockedSelectionCount >= 3 }

    func copySelected() {
        let selected = selectedElements
        guard !selected.isEmpty else { return }
        clipboard = selected
        pasteCount = 0
        ElementClipboard.write(selected)
    }

    func cutSelected() {
        // Symmetric with deleteSelected: cut takes exactly what it removes,
        // so a locked element is never both left behind and on the clipboard.
        let removable = selectedElements.filter { !$0.locked }
        guard !removable.isEmpty else { return }
        clipboard = removable
        pasteCount = 0
        ElementClipboard.write(removable)
        deleteSelected()
    }

    func paste() {
        // Our own copy first; otherwise whatever another app left: a
        // picture, or some text.
        if clipboard.isEmpty {
            if let mine = ElementClipboard.read() {
                clipboard = mine
                pasteCount = 0
            } else if let stranger = ElementClipboard.foreign(designWidth: design.width) {
                add(stranger)
                return
            }
        }
        guard !clipboard.isEmpty else { return }
        pasteCount += 1
        // Copies arrive unlocked: locked is a property of the original, and a
        // pasted element the user cannot move, edit or delete is a dead end.
        let copies = Self.remapGroups(clipboard.map { element -> Element in
            var copy = element.duplicated(offset: 24 * Double(pasteCount))
            copy.locked = false
            return copy
        })
        applyToPage { $0.elements.append(contentsOf: copies) }
        selection = Set(copies.map(\.id))
    }

    func selectAll() {
        editingTextId = nil
        selection = Set(page.elements.filter { !$0.locked }.map(\.id))
    }

    /// Rubber-band selection: everything the rectangle touches, with sticky
    /// groups expanded so a band across one member takes the whole group.
    func select(within rect: CGRect) {
        editingTextId = nil
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
        guard selectedElements.filter({ !$0.locked }).count >= 2 else { return }
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

    func alignSelected(_ mode: AlignMode) {
        let selected = selectedElements.filter { !$0.locked }
        guard !selected.isEmpty else { return }
        let bounds: CGRect = selected.count == 1
            ? CGRect(x: 0, y: 0, width: design.width, height: design.height)
            : Geometry.union(selected.map(Geometry.aabb))
        applyToPage { page in
            for i in page.elements.indices where self.selection.contains(page.elements[i].id) && !page.elements[i].locked {
                let box = Geometry.aabb(page.elements[i])
                var dx = 0.0, dy = 0.0
                switch mode {
                case .left: dx = bounds.minX - box.minX
                case .centerX: dx = bounds.midX - box.midX
                case .right: dx = bounds.maxX - box.maxX
                case .top: dy = bounds.minY - box.minY
                case .centerY: dy = bounds.midY - box.midY
                case .bottom: dy = bounds.maxY - box.maxY
                }
                page.elements[i].x += dx
                page.elements[i].y += dy
            }
        }
    }

    /// Tidy the unlocked selection into a row, column or grid, one undo step.
    /// The gap is a fiftieth of the page's shorter side: visible, not loose.
    func tidySelected(_ mode: Geometry.TidyMode) {
        let members = selectedElements.filter { !$0.locked }
        guard members.count >= 2 else { return }
        let gap = (min(design.width, design.height) / 50).rounded()
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
        guard dx != 0 || dy != 0, unlockedSelectionCount > 0 else { return }
        updateSelected { $0.x += dx; $0.y += dy }
    }

    /// The selection's box, for the numeric fields; nil when nothing is
    /// selected.
    var selectionBox: CGRect? {
        let members = selectedElements
        return members.isEmpty ? nil : Geometry.union(members.map(Geometry.aabb))
    }

    /// Resize the whole selection so its box becomes `to`, one undo step.
    func setSelectionBox(_ to: CGRect) {
        let members = selectedElements.filter { !$0.locked }
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
        let members = selectedElements.filter { !$0.locked }
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
        let selected = selectedElements.filter { !$0.locked }
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

    /// Something just happened that a first-timer might want a word about.
    /// The editor hands it to TipEngine, which decides whether to say it.
    var tipEvent: TipEvent?

    private func announce(_ text: String) {
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
        var range: NSRange
        /// The line the match sits on, for showing it in a list.
        var preview: String
    }

    /// Every occurrence of `needle` across every page, in reading order.
    ///
    /// Pure and non-mutating, so the sheet can show a live count while typing
    /// without touching the document or the undo stack.
    func matches(for needle: String, caseSensitive: Bool = false) -> [TextMatch] {
        guard !needle.isEmpty else { return [] }
        var found: [TextMatch] = []
        for (index, page) in design.pages.enumerated() {
            for element in page.elements where element.type == .text {
                let body = element.text ?? ""
                guard !body.isEmpty else { continue }
                let options: String.CompareOptions = caseSensitive ? [.literal] : [.caseInsensitive]
                var searchStart = body.startIndex
                while let range = body.range(of: needle, options: options,
                                             range: searchStart..<body.endIndex) {
                    let ns = NSRange(range, in: body)
                    found.append(TextMatch(pageIndex: index, elementId: element.id,
                                           range: ns, preview: line(of: body, containing: range)))
                    // Advance past this match, never past the end.
                    searchStart = range.upperBound > range.lowerBound
                        ? range.upperBound
                        : body.index(after: range.lowerBound)
                    if searchStart >= body.endIndex { break }
                }
            }
        }
        return found
    }

    private func line(of body: String, containing range: Range<String.Index>) -> String {
        let lower = body[body.startIndex..<range.lowerBound].lastIndex(of: "\n")
            .map { body.index(after: $0) } ?? body.startIndex
        let upper = body[range.upperBound...].firstIndex(of: "\n") ?? body.endIndex
        return String(body[lower..<upper]).trimmingCharacters(in: .whitespaces)
    }

    /// Replace every occurrence across every page, as one undo step.
    ///
    /// One step on purpose: a replace-all that took forty steps to undo would
    /// be worse than no undo at all. Returns how many were replaced.
    @discardableResult
    func replaceAll(_ needle: String, with replacement: String,
                    caseSensitive: Bool = false) -> Int {
        guard !needle.isEmpty else { return 0 }
        let total = matches(for: needle, caseSensitive: caseSensitive).count
        guard total > 0 else { return 0 }
        let options: String.CompareOptions = caseSensitive ? [.literal] : [.caseInsensitive]
        apply { design in
            for p in design.pages.indices {
                for i in design.pages[p].elements.indices
                where design.pages[p].elements[i].type == .text {
                    guard let body = design.pages[p].elements[i].text, !body.isEmpty else { continue }
                    let replaced = body.replacingOccurrences(of: needle, with: replacement,
                                                             options: options)
                    guard replaced != body else { continue }
                    design.pages[p].elements[i].text = replaced
                    design.pages[p].elements[i].h =
                        FontLibrary.layoutHeight(for: design.pages[p].elements[i])
                }
            }
        }
        announce(total == 1 ? "Replaced 1 occurrence" : "Replaced \(total) occurrences")
        return total
    }

    /// Show a match: switch to its page and select its element.
    func reveal(_ match: TextMatch) {
        guard design.pages.indices.contains(match.pageIndex) else { return }
        pageIndex = match.pageIndex
        selection = [match.elementId]
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
        var color: String?
        var fontFamily: String?
        var fontSize: Double?
        var fontWeight: Int?
        var italic: Bool?
        var underline: Bool?
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
              color: el.color, fontFamily: el.fontFamily, fontSize: el.fontSize,
              fontWeight: el.fontWeight, italic: el.italic, underline: el.underline,
              align: el.align, lineHeight: el.lineHeight, letterSpacing: el.letterSpacing,
              listStyle: el.listStyle, indent: el.indent, textFill: el.textFill,
              vAlign: el.vAlign, paragraphSpacing: el.paragraphSpacing,
              effect: el.effect, curve: el.curve, filter: el.filter,
              adjustments: el.adjustments, maskShapeId: el.maskShapeId, duotone: el.duotone,
              opacity: el.opacity, shadow: el.shadow, blendMode: el.blendMode,
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
        case .text:
            el.color = style.color
            el.fontFamily = style.fontFamily
            el.fontSize = style.fontSize
            el.fontWeight = style.fontWeight
            el.italic = style.italic
            el.underline = style.underline
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
    }

    func pasteStyle() {
        guard let style = copiedStyle else { return }
        updateSelected { Self.apply(style, to: &$0) }
    }

    func toggleLockSelected() {
        let anyUnlocked = selectedElements.contains { !$0.locked }
        applyToPage { page in
            for i in page.elements.indices where self.selection.contains(page.elements[i].id) {
                page.elements[i].locked = anyUnlocked
            }
        }
    }

    func flipSelected(horizontal: Bool) {
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
    }

    func duplicatePage() {
        var copy = page
        copy.id = UID.make("page")
        copy.elements = copy.elements.map {
            var el = $0
            el.id = UID.make()
            return el
        }
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
        apply { d in
            var out: [Page] = []
            for p in d.pages {
                out.append(p)
                if ids.contains(p.id) {
                    var copy = p
                    copy.id = UID.make("page")
                    copy.elements = copy.elements.map { var el = $0; el.id = UID.make(); return el }
                    out.append(copy)
                }
            }
            d.pages = out
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
    static func themed(_ design: Design, palette: [String]?, pairing: FontPairing?) -> Design {
        var out = design
        if let palette, !palette.isEmpty {
            let colors = ColorTools.documentColors(design, limit: 24)
            if !colors.isEmpty {
                for p in out.pages.indices {
                    ColorTools.shuffle(page: &out.pages[p], docColors: colors, palette: palette)
                }
            }
        }
        if let pairing {
            for p in out.pages.indices {
                for i in out.pages[p].elements.indices where out.pages[p].elements[i].type == .text {
                    let spec = (out.pages[p].elements[i].fontSize ?? 42) >= headingSize
                        ? pairing.heading : pairing.body
                    out.pages[p].elements[i].fontFamily = spec.fontFamily
                    out.pages[p].elements[i].fontWeight = spec.fontWeight
                    if let spacing = spec.letterSpacing { out.pages[p].elements[i].letterSpacing = spacing }
                    out.pages[p].elements[i].h = FontLibrary.layoutHeight(for: out.pages[p].elements[i])
                }
            }
        }
        return out
    }

    /// Apply a theme to the whole document as one undo step.
    func applyTheme(palette: [String]?, pairing: FontPairing?) {
        let next = Self.themed(design, palette: palette, pairing: pairing)
        guard next != design else { return }
        apply { $0 = next }
        announce("Applied theme to \(design.pages.count == 1 ? "the page" : "all \(design.pages.count) pages")")
    }

    // MARK: components

    /// Save the selection as a component, keeping nothing locked in it.
    @discardableResult
    func saveSelectionAsComponent(named name: String) -> Component? {
        Components.add(named: name, from: selectedElements)
    }

    /// Drop a component onto the page at half its width, centred.
    func insertComponent(_ component: Component) {
        let width = (design.width * 0.5).rounded()
        let height = width * component.height / max(component.width, 1)
        let origin = CGPoint(x: ((design.width - width) / 2).rounded(), y: ((design.height - height) / 2).rounded())
        let elements = Components.instance(of: component, width: width, at: origin)
        guard !elements.isEmpty else { return }
        applyToPage { $0.elements.append(contentsOf: elements) }
        selection = Set(elements.map(\.id))
    }

    // MARK: text styles

    /// Apply a saved style to the selected text elements, one undo step.
    func applyTextStyle(_ style: TextStyle) {
        updateSelected { el in TextStyles.apply(style, to: &el) }
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
        addGuide(vertical: vertical, at: (vertical ? design.width / 2 : design.height / 2).rounded())
    }

    func addGuide(vertical: Bool, at position: Double) {
        apply { $0.guides.append(Guide(vertical: vertical, position: position)) }
    }

    /// Slide a guide while dragging; commit() when the finger lifts.
    func moveGuideTransient(_ id: String, to position: Double) {
        beginGesture()
        if let i = design.guides.firstIndex(where: { $0.id == id }) {
            let limit = design.guides[i].vertical ? design.width : design.height
            design.guides[i].position = min(max(position, 0), limit).rounded()
        }
    }

    func removeGuide(_ id: String) {
        apply { $0.guides.removeAll { $0.id == id } }
    }

    func clearGuides() {
        guard !design.guides.isEmpty else { return }
        apply { $0.guides.removeAll() }
    }

    // MARK: page clipboard

    func copyPage() {
        PageClipboard.copy(page, width: design.width, height: design.height)
    }

    var hasPageOnClipboard: Bool { PageClipboard.hasPage() }

    /// Paste the copied page after the current one, scaled to this design.
    func pastePage() {
        guard let payload = PageClipboard.paste() else { return }
        let landed = PageClipboard.fitted(payload, width: design.width, height: design.height)
        apply { $0.pages.insert(landed, at: pageIndex + 1) }
        pageIndex += 1
        selection.removeAll()
    }

    func setPage(_ index: Int) {
        guard index >= 0 && index < design.pages.count && index != pageIndex else { return }
        pageIndex = index
        selection.removeAll()
        editingTextId = nil
    }

    /// Uniformly rescale all content to a new canvas size. Scaling to *fit*
    /// (and centring on both axes) keeps content on the page when the aspect
    /// ratio changes; scaling by width alone would push it off the bottom.
    func resizeDesign(width: Double, height: Double) {
        guard width != design.width || height != design.height else { return }
        let scale = min(width / design.width, height / design.height)
        let dx = (width - design.width * scale) / 2
        let dy = (height - design.height * scale) / 2
        apply { d in
            d.width = width
            d.height = height
            for p in d.pages.indices {
                for i in d.pages[p].elements.indices {
                    d.pages[p].elements[i].x = d.pages[p].elements[i].x * scale + dx
                    d.pages[p].elements[i].y = d.pages[p].elements[i].y * scale + dy
                    d.pages[p].elements[i].w *= scale
                    d.pages[p].elements[i].h *= scale
                    if let fs = d.pages[p].elements[i].fontSize {
                        d.pages[p].elements[i].fontSize = fs * scale
                    }
                    if let t = d.pages[p].elements[i].thickness {
                        d.pages[p].elements[i].thickness = max(1, t * scale)
                    }
                }
            }
        }
    }
}

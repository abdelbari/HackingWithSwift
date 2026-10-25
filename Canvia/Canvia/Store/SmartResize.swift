// Resize that fills a new shape, the way Magic Resize does it — the Android
// twin's PageResize.smartReflow, rule for rule (templates/resize-smart.json
// pins both): a full-bleed photo or shape covers the new page, bands keep
// their span, content placed side by side restacks when the orientation
// turns, and type stays readable. The Resize sheet offers it as Smart, the
// default, beside Keep layout (reflowedPage) and Fit (scaledPage), and
// remembers the choice under "resizeMode"; Copy & resize and a template
// added as a new page are fitted by it too.

import CoreGraphics
import Foundation

/// How Resize takes a design to its new size, as the sheet offers it: the
/// Android twin's PageResize.Mode, by the same keys.
enum ResizeMode: String, CaseIterable, Identifiable {
    /// DesignStore.smartReflow.
    case smart
    /// "Keep layout": DesignStore.reflowedPage.
    case reflow
    /// "Fit": DesignStore.scaledPage.
    case fit

    var id: String { rawValue }

    /// The preference both phones keep the sheet's choice under.
    static let key = "resizeMode"

    /// The mode a stored key names; Smart for none or one unknown.
    static func of(_ key: String?) -> ResizeMode { allCases.first { $0.rawValue == key } ?? .smart }

    var label: String {
        switch self {
        case .smart: return tr("Smart")
        case .reflow: return tr("Keep layout")
        case .fit: return tr("Fit")
        }
    }

    /// What the sheet says under the choice.
    var explanation: String {
        switch self {
        case .smart: return tr("Backgrounds fill the new shape, side-by-side content stacks when it turns, and text stays readable.")
        case .reflow: return tr("Things stay where they are relative to the edges and the centre, and text re-wraps to the new width.")
        case .fit: return tr("Everything shrinks or grows together, centred, with margins where the shape changed.")
        }
    }
}

extension DesignStore {

    /// How much of an old axis an element must cover to count as filling
    /// it: a backdrop both, a band one.
    static let smartFull = 0.9

    /// The margin, as a share of each side, restacked content keeps.
    static let stackMargin = 0.06

    /// The smallest body type, and heading type, as a share of the new
    /// page's shorter side.
    static let bodyMin = 0.035
    static let headingMin = 0.05

    /// One page taken from `old` to `new` in `mode`.
    static func fitted(_ page: Page, from old: CGSize, to new: CGSize, mode: ResizeMode,
                       heightFor: (Element) -> Double = { FontLibrary.layoutHeight(for: $0) }) -> Page {
        switch mode {
        case .smart: return smartReflow(page, from: old, to: new, heightFor: heightFor)
        case .reflow: return reflowedPage(page, from: old, to: new)
        case .fit: return scaledPage(page, from: old, to: new)
        }
    }

    /// Where on the new axis an element goes: the same share of the free
    /// room on either side as before; the centre's fraction when the element
    /// filled the axis and there was no room to share — reflowedPage's rule.
    private static func place(_ pos: Double, _ size: Double, _ oldAxis: Double, _ newSize: Double,
                              _ newAxis: Double) -> Double {
        let room = oldAxis - size
        if room > 0.5 { return (newAxis - newSize) * (pos / room) }
        return (pos + size / 2) / max(oldAxis, 1) * newAxis - newSize / 2
    }

    /// One page taken from `old` to `new` the way Magic Resize does it —
    /// the shared rule both phones follow, each element by the first that
    /// holds:
    ///
    /// 1. Locked stays put: its place by each axis's ratio, its sizes by
    ///    the smaller one.
    /// 2. Backdrop: an image (a photo, a clip, a grid) or a shape at least
    ///    `smartFull` of both old sides, unturned, covers the new page
    ///    exactly — a picture re-crops by cover, its crop scale and focus
    ///    kept; a shape stretches.
    /// 3. Band: one at least `smartFull` as wide as the old page keeps that
    ///    share of the new width, and one as tall its share of the new
    ///    height; on the other axis it scales by the smaller ratio and keeps
    ///    its share of the free room, as Keep layout does. When the
    ///    orientation flips, a band across the axis the rest restack along —
    ///    the full height of a wide page, the full width of a tall one —
    ///    restacks with them instead: a photo beside its words goes above
    ///    them.
    /// 4. The rest: when the orientation flips (wide to tall or tall to
    ///    wide) they restack (`restacked`); otherwise each keeps its share
    ///    of the free room, scaled by the smaller ratio, as Keep layout does
    ///    (words in a group not widened, so the group keeps its shape).
    ///
    /// Then type stays readable: a text box's size is never below its old
    /// size times the smaller ratio, nor below `bodyMin` (body) or
    /// `headingMin` (a heading, TextRoles of the page) of the new page's
    /// shorter side; `heightFor` measures every text box changed. Nothing
    /// is left off the page.
    static func smartReflow(_ page: Page, from old: CGSize, to new: CGSize,
                            heightFor: (Element) -> Double) -> Page {
        let ow = max(Double(old.width), 1), oh = max(Double(old.height), 1)
        let nw = Double(new.width), nh = Double(new.height)
        let rx = nw / ow, ry = nh / oh
        let s = min(rx, ry)
        let short = min(nw, nh)
        var holder = Design(title: "", width: ow, height: oh)
        holder.pages = [page]
        let headings = TextRoles.headingSizes(holder)

        func readable(_ orig: Element, _ e: Element) -> Element {
            guard orig.type == .text, let size = orig.fontSize else { return e }
            let role = TextRoles.stored(orig) ?? TextRoles.inferred(size, headingSizes: headings)
            let floor = short * (TextRoles.level(role) != nil ? headingMin : bodyMin)
            var sized = e
            sized.fontSize = max(e.fontSize ?? 0, size * s, floor)
            sized.h = heightFor(sized)
            return sized
        }

        func onPage(_ e: Element) -> Element {
            var out = e
            out.x = min(max(e.x, 0), max(nw - e.w, 0))
            out.y = min(max(e.y, 0), max(nh - e.h, 0))
            return out
        }

        func keptShare(_ el: Element) -> Element {
            var e = el.scaledSizes(by: s)
            // Words widen into a wider page, as Keep layout's do — but not
            // in a group, which keeps its shape.
            if el.type == .text && rx > s && el.group == nil { e.w = min(el.w * rx, nw) }
            if el.type == .text { e.h = heightFor(e) }
            e.x = place(el.x, el.w, ow, e.w, nw)
            e.y = place(el.y, el.h, oh, e.h, nh)
            return e
        }

        let flips = (ow > oh && nw < nh) || (ow < oh && nw > nh)
        let across = ow < oh
        var placed: [String: Element] = [:]
        var rest: [Element] = []
        for el in page.elements {
            let wide = el.w >= smartFull * ow
            let tall = el.h >= smartFull * oh
            if el.locked {
                var e = el.scaledSizes(by: s)
                e.x = el.x * rx
                e.y = el.y * ry
                placed[el.id] = e
            } else if wide && tall && el.rotation == 0 && (el.type == .image || el.type == .shape) {
                var e = el.scaledSizes(by: s)
                e.x = 0
                e.y = 0
                e.w = nw
                e.h = nh
                placed[el.id] = e
            } else if flips && ((tall && !across) || (wide && across)) {
                // A band across the axis content restacks along — a photo the
                // height of a wide slide, beside its words — restacks with
                // them rather than staying a band.
                rest.append(el)
            } else if wide {
                var e = el.scaledSizes(by: s)
                e.w = el.w * rx
                if el.type == .text { e.h = heightFor(e) }
                e.x = el.x * rx
                e.y = place(el.y, el.h, oh, e.h, nh)
                placed[el.id] = onPage(readable(el, e))
            } else if tall {
                var e = el.scaledSizes(by: s)
                e.h = el.h * ry
                e.x = place(el.x, el.w, ow, e.w, nw)
                e.y = el.y * ry
                placed[el.id] = onPage(readable(el, e))
            } else {
                rest.append(el)
            }
        }

        if flips {
            for (el, e) in restacked(rest, on: CGSize(width: nw, height: nh), across: across) {
                placed[el.id] = onPage(readable(el, e))
            }
        } else {
            for el in rest { placed[el.id] = onPage(readable(el, keptShare(el))) }
        }
        var out = page
        out.elements = page.elements.map { placed[$0.id] ?? $0 }
        return out
    }

    /// A cluster of elements restacked together, and the span round them.
    private struct Stack {
        var members: [Element]
        var lo: Double
        var hi: Double
    }

    /// `items` restacked on `new` (see `smartReflow`): grouped elements
    /// together, they are clustered into columns where their spans across
    /// overlap, the columns laid out top to bottom in reading order inside a
    /// `stackMargin` margin — or, `across`, going tall to wide, rows laid
    /// left to right — all scaled alike so the widest fills the new width
    /// (the tallest the new height), and down together when they do not
    /// fit, the room left shared evenly before, between and after them. The
    /// maths is the same with the axes swapped, so it is written once for
    /// columns, along "main" (the axis they stack on) and "cross".
    private static func restacked(_ items: [Element], on new: CGSize, across: Bool) -> [(Element, Element)] {
        guard !items.isEmpty else { return [] }
        func crossLo(_ e: Element) -> Double { across ? e.y : e.x }
        func crossLen(_ e: Element) -> Double { across ? e.h : e.w }
        func mainLo(_ e: Element) -> Double { across ? e.x : e.y }
        func mainLen(_ e: Element) -> Double { across ? e.w : e.h }
        // Groups stay whole: a unit is a group, or an element on its own,
        // in the order each first appears.
        var keys: [String] = []
        var byKey: [String: [Element]] = [:]
        for el in items {
            let key = el.group ?? el.id
            if byKey[key] == nil { keys.append(key) }
            byKey[key, default: []].append(el)
        }
        let units = keys.compactMap { byKey[$0] }
        // Sorted by where they start across, then along; a tie keeps their
        // order, as the Android twin's stable sort does.
        let sorted = units.enumerated().sorted { a, b in
            let ac = a.element.map(crossLo).min() ?? 0, bc = b.element.map(crossLo).min() ?? 0
            if ac != bc { return ac < bc }
            let am = a.element.map(mainLo).min() ?? 0, bm = b.element.map(mainLo).min() ?? 0
            if am != bm { return am < bm }
            return a.offset < b.offset
        }.map(\.element)
        var stacks: [Stack] = []
        for unit in sorted {
            let lo = unit.map(crossLo).min() ?? 0
            let hi = unit.map { crossLo($0) + crossLen($0) }.max() ?? 0
            if let last = stacks.indices.last, lo < stacks[last].hi {
                stacks[last].members += unit
                stacks[last].hi = max(stacks[last].hi, hi)
            } else {
                stacks.append(Stack(members: unit, lo: lo, hi: hi))
            }
        }
        let crossSide = Double(across ? new.height : new.width)
        let mainSide = Double(across ? new.width : new.height)
        let crossMargin = crossSide * stackMargin
        let mainMargin = mainSide * stackMargin
        let room = crossSide - 2 * crossMargin
        // One scale for every column, so the widest fills the new width and
        // the rest keep their sizes beside it.
        let widest = max(stacks.map { $0.hi - $0.lo }.max() ?? 1, 1)
        let k0 = room / widest
        let boxes = stacks.map { st -> (stack: Stack, top: Double, length: Double) in
            let top = st.members.map(mainLo).min() ?? 0
            let bottom = st.members.map { mainLo($0) + mainLen($0) }.max() ?? 0
            return (st, top, bottom - top)
        }
        let total = boxes.reduce(0) { $0 + $1.length * k0 }
        let avail = mainSide - 2 * mainMargin
        let fit = total > avail && total > 0 ? avail / total : 1
        let gap = (avail - total * fit) / Double(boxes.count + 1)
        let k = k0 * fit
        var at = mainMargin + gap
        var out: [(Element, Element)] = []
        for box in boxes {
            let st = box.stack
            let offset = crossMargin + (room - (st.hi - st.lo) * k) / 2
            for el in st.members {
                var e = el.scaledSizes(by: k)
                let c = offset + (crossLo(el) - st.lo) * k
                let m = at + (mainLo(el) - box.top) * k
                if across {
                    e.x = m
                    e.y = c
                } else {
                    e.x = c
                    e.y = m
                }
                out.append((el, e))
            }
            at += box.length * k + gap
        }
        return out
    }

    /// The whole design taken to `width` × `height` in `mode` — pages with a
    /// size of their own brought to the new one, each cut into slides as the
    /// new size is (PageSplit.forSize). Guides move as reflowing moves them
    /// for Smart and Keep layout, and as scaling does for Fit. Pure.
    static func resized(_ design: Design, width: Double, height: Double, mode: ResizeMode,
                        heightFor: (Element) -> Double = { FontLibrary.layoutHeight(for: $0) }) -> Design {
        guard width > 0, height > 0 else { return design }
        let new = CGSize(width: width, height: height)
        var out = design
        out.width = width
        out.height = height
        for p in out.pages.indices {
            out.pages[p] = fitted(design.pages[p], from: design.size(for: design.pages[p]), to: new, mode: mode,
                                  heightFor: heightFor)
            out.pages[p].width = nil
            out.pages[p].height = nil
            out.pages[p].split = PageSplit.forSize(width: width, height: height)
        }
        if mode == .fit {
            let s = min(width / max(design.width, 1), height / max(design.height, 1))
            let dx = (width - design.width * s) / 2, dy = (height - design.height * s) / 2
            out.guides = out.guides.map { g in
                var g2 = g
                g2.position = g.position * s + (g.vertical ? dx : dy)
                return g2
            }
        } else {
            let rx = width / max(design.width, 1), ry = height / max(design.height, 1)
            out.guides = out.guides.map { g in
                var g2 = g
                g2.position = g.vertical ? g.position * rx : g.position * ry
                return g2
            }
        }
        return out
    }

    /// Resize: the design, or this page alone, taken to `width` × `height`
    /// in `mode` (Smart, Keep layout or Fit) as one step named Resize — the
    /// whole design then measured in `units`, when given. As the Android
    /// twin's EditorViewModel.resize.
    func resize(width: Double, height: Double, mode: ResizeMode, pageOnly: Bool, units: UnitChoice? = nil) {
        guard width > 0, height > 0 else { return }
        if pageOnly {
            let old = pageSize
            let new = CGSize(width: width, height: height)
            guard new != old else { return }
            let index = pageIndex
            namedStep = tr("Resize")
            apply { d in
                var pg = Self.fitted(d.pages[index], from: old, to: new, mode: mode)
                let isDocument = width == d.width && height == d.height
                pg.width = isDocument ? nil : width
                pg.height = isDocument ? nil : height
                pg.split = PageSplit.forSize(width: width, height: height)
                d.pages[index] = pg
            }
            announce(tr("This page is now %@", "\(Int(width)) × \(Int(height))"))
        } else {
            let changesUnits = units.map { $0.unit != design.unit || $0.dpi != design.dpi } ?? false
            guard width != design.width || height != design.height || design.hasMixedPageSizes || changesUnits
            else { return }
            var next = Self.resized(design, width: width, height: height, mode: mode)
            if let units {
                next.unit = units.unit
                next.dpi = units.dpi
            }
            namedStep = tr("Resize")
            apply { $0 = next }
            announce(tr("Resized to %@", "\(Int(width)) × \(Int(height))"))
        }
        buzz(.confirm)
    }
}

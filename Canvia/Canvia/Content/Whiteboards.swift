// A page expanded to a whiteboard, as Canva's "Expand to whiteboard" makes
// one: an endless canvas round the page's own frame, for brainstorming —
// sticky notes, connectors — which collapses back to the page.
//
// Kept on the page as both phones write it (Page.whiteboard),
// "whiteboard": {"expanded": true, "bounds": [x, y, w, h]}: the bounds are
// everything on the page — the frame (0, 0, width, height) and every
// element's turned box, hidden ones too — in page units, so they may run
// negative, and the store keeps them up to date on every step (refreshed).
// The page's own width and height stay the collapsed frame. A collapsed page
// has no key at all. The geometry is the Android twin's Whiteboards, one
// test table for both.

import CoreGraphics
import Foundation

enum Whiteboards {

    /// The Whiteboard design type's id: a 1920 × 1080 frame that starts
    /// expanded.
    static let presetId = "whiteboard"

    /// How far a whiteboard zooms, a person's percent over 100: 5% to 400%.
    static let minZoom = 0.05
    static let maxZoom = 4.0

    /// The margin round the bounds an export, a thumbnail, Present and Fit
    /// to content take, as a share of the bounds' own width (each side) and
    /// height (top and bottom).
    static let margin = 0.05

    /// Said, with Undo, when a collapse hid what lay outside the frame.
    static func hiddenNote(_ count: Int) -> String {
        trn("%d element outside the page is hidden|%d elements outside the page are hidden", count)
    }

    static func isExpanded(_ page: Page) -> Bool { page.whiteboard?.expanded == true }

    /// The bounds as written, or nil when there are none that read.
    static func storedBounds(_ page: Page) -> CGRect? { page.whiteboard?.rect }

    /// Everything on a page of `frame` holding `elements`: the frame and
    /// each element's turned box.
    static func contentBounds(frame: CGSize, elements: [Element]) -> CGRect {
        let page = CGRect(origin: .zero, size: frame)
        return elements.reduce(page) { $0.union(Geometry.aabb($1)) }
    }

    /// `page`'s bounds now, worked out afresh from what is on it.
    static func bounds(_ design: Design, _ page: Page) -> CGRect {
        contentBounds(frame: design.size(for: page), elements: page.elements)
    }

    /// Whether `el`'s turned box shares no area with the frame — touching
    /// its edge from outside is still outside.
    static func isOutside(_ el: Element, frame: CGSize) -> Bool {
        let box = Geometry.aabb(el)
        return box.maxX <= 0 || box.maxY <= 0 || box.minX >= frame.width || box.minY >= frame.height
    }

    /// The elements of `page` wholly outside its frame.
    static func outside(_ page: Page, frame: CGSize) -> [Element] {
        page.elements.filter { isOutside($0, frame: frame) }
    }

    /// `page` expanded: every hidden element lying wholly outside the frame
    /// shown again — what collapsing hid, since a collapse hides exactly
    /// those — and the bounds worked out with them.
    static func expanded(_ page: Page, frame: CGSize) -> Page {
        var out = page
        for i in out.elements.indices where out.elements[i].isHidden && isOutside(out.elements[i], frame: frame) {
            out.elements[i].hidden = nil
        }
        out.whiteboard = PageWhiteboard(bounds: contentBounds(frame: frame, elements: out.elements))
        return out
    }

    /// `page` collapsed back to its frame: the key gone, and every element
    /// wholly outside the frame kept but hidden, so nothing lost is drawn
    /// over the workspace round a page that no longer reaches it.
    static func collapsed(_ page: Page, frame: CGSize) -> Page {
        var out = page
        for i in out.elements.indices where isOutside(out.elements[i], frame: frame) {
            out.elements[i].hidden = true
        }
        out.whiteboard = nil
        return out
    }

    /// `design` with every expanded page's bounds as they now are — the
    /// same design when none has moved.
    static func refreshed(_ design: Design) -> Design {
        var out = design
        for i in out.pages.indices where isExpanded(out.pages[i]) {
            let now = bounds(design, out.pages[i])
            if storedBounds(out.pages[i]) != now { out.pages[i].whiteboard = PageWhiteboard(bounds: now) }
        }
        return out
    }

    /// `bounds` with `margin` round it: what an export, a thumbnail and
    /// Present show of an expanded page.
    static func withMargin(_ bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: -bounds.width * margin, dy: -bounds.height * margin)
    }

    /// What is drawn of `page` wherever it leaves the app: its bounds with
    /// their margin while expanded, else its frame.
    static func shownRect(_ design: Design, _ page: Page) -> CGRect {
        isExpanded(page) ? withMargin(bounds(design, page)) : CGRect(origin: .zero, size: design.size(for: page))
    }

    /// `design` with every expanded page as the plain page that is drawn of
    /// it — sized to its bounds and their margin, everything moved by the
    /// same amount, the master's elements with it, and the key gone — so an export, a thumbnail or Present
    /// draws it as it draws any page. The same design when none is
    /// expanded.
    static func flattened(_ design: Design) -> Design {
        guard design.pages.contains(where: isExpanded) else { return design }
        var out = design
        out.pages = design.pages.map { drawn(design, $0) }
        return out
    }

    /// `page` as flattened draws it — the page itself unless it is
    /// expanded. Sized in its own right, so `design` measures it as it is.
    /// The master's shown elements behind it are carried onto it, moved
    /// with its own, and the page no longer shows the master — so a logo
    /// at the frame's corner stays at the frame's corner.
    static func drawn(_ design: Design, _ page: Page) -> Page {
        guard isExpanded(page) else { return page }
        let rect = shownRect(design, page)
        var out = page
        out.whiteboard = nil
        out.usesMaster = false
        out.elements = design.masterElements(behind: page) + page.elements
        out.width = Double(rect.width)
        out.height = Double(rect.height)
        for i in out.elements.indices {
            out.elements[i].x -= Double(rect.minX)
            out.elements[i].y -= Double(rect.minY)
        }
        return out
    }

    /// The zoom and pan that show `content` whole and centred in `viewport`
    /// — Fit to content, and Present's Zoom to fit — the zoom held within
    /// `minZoom` and `maxZoom` (screen units to one page unit); the pan is
    /// where the page's origin lands on screen.
    static func fit(content: CGRect, viewport: CGSize, minZoom: Double, maxZoom: Double) -> (zoom: Double, pan: CGPoint) {
        guard content.width > 0, content.height > 0, viewport.width > 0, viewport.height > 0 else { return (1, .zero) }
        let zoom = min(max(min(Double(viewport.width / content.width), Double(viewport.height / content.height)), minZoom), maxZoom)
        return (zoom, CGPoint(x: Double(viewport.width) / 2 - Double(content.midX) * zoom,
                              y: Double(viewport.height) / 2 - Double(content.midY) * zoom))
    }

    /// What the pan keeps reachable on an expanded page: its bounds and one
    /// screen — `viewport` at `zoom`, in page units — round them.
    static func panContent(bounds: CGRect, viewport: CGSize, zoom: Double) -> CGRect {
        guard zoom > 0 else { return bounds }
        return bounds.insetBy(dx: -Double(viewport.width) / zoom, dy: -Double(viewport.height) / zoom)
    }

    /// The zoom range of a whiteboard on a screen of `density` screen units
    /// to a point: 5% to 400%. On this phone a point is the unit, so 1.
    static func zoomRange(density: Double = 1) -> ClosedRange<Double> {
        minZoom * density...maxZoom * density
    }

    /// How far apart the light dot grid round an expanded frame is, in page
    /// units, at the zoom shown — doubled until the dots are at least
    /// `minScreenGap` screen units apart, so zoomed out they never crowd.
    static func gridStep(zoom: Double, base: Double = 40, minScreenGap: Double = 16) -> Double {
        var step = base
        guard zoom > 0 else { return step }
        while step * zoom < minScreenGap { step *= 2 }
        return step
    }

    /// `design` made at the Whiteboard type: its pages expanded.
    static func started(_ design: Design) -> Design {
        var out = design
        out.pages = design.pages.map { expanded($0, frame: design.size(for: $0)) }
        return out
    }
}

/// A sticky note, the whiteboard's own insert: a square shape with words in
/// it, in one of six paper colours, whose words shrink to stay inside as
/// more are typed rather than growing the note. Said with `"sticky": true`
/// on the shape (Element.sticky), as the Android twin's StickyNotes.
enum StickyNotes {

    /// The six papers, in the order Add offers them: yellow, pink, green,
    /// blue, purple and orange.
    static let colours = ["#fff176", "#f8bbd0", "#c5e1a5", "#b3e5fc", "#d1c4e9", "#ffcc80"]

    /// A new note's side, in page units.
    static let side = 280.0

    /// The words' largest size, which they start at and grow back to.
    static let fontSize = 40.0

    /// The least they shrink to.
    static let minFontSize = 10.0

    static func isSticky(_ el: Element) -> Bool { el.sticky == true }

    /// What VoiceOver calls a paper in Add: "Sticky note, yellow".
    static func spoken(_ colour: String) -> String {
        tr("Sticky note, %@", ElementNames.colourName(colour))
    }

    /// A new note of `colour`, its words dark and centred, at the origin.
    static func note(_ colour: String) -> Element {
        var shape = Element.shape("rectangle", w: side, h: side)
        shape.fill = .solid(colour)
        shape.radius = 0
        var started = ShapeText.starting(shape)
        started.fontSize = fontSize
        started.color = ShapeText.darkInk
        started.sticky = true
        return started
    }

    /// The largest whole size, from `fontSize` down to `minFontSize`, at
    /// which words `heightAt` that size tall fit `room` — found by halving,
    /// as taller words never take less room. `minFontSize` when even that
    /// does not fit.
    static func fittedFontSize(room: Double, heightAt: (Double) -> Double) -> Double {
        var low = Int(minFontSize)
        var high = Int(fontSize)
        if heightAt(Double(high)) <= room { return fontSize }
        while high - low > 1 {
            let mid = (low + high) / 2
            if heightAt(Double(mid)) <= room { low = mid } else { high = mid }
        }
        return Double(low)
    }

    /// `note` with its words at the size that fits it, measured as the
    /// canvas lays them out.
    static func fitted(_ note: Element) -> Element {
        let room = Double(ShapeText.box(for: note).height)
        let size = fittedFontSize(room: room) { s in
            var sized = note
            sized.fontSize = s
            return FontLibrary.measuredHeight(for: ShapeText.textElement(for: sized))
        }
        guard size != note.fontSize else { return note }
        var out = note
        out.fontSize = size
        return out
    }

    /// Where a new note goes on a whiteboard: centred on `centre`, the
    /// middle of what is on screen, in page units.
    static func placed(_ note: Element, at centre: CGPoint) -> Element {
        var out = note
        out.x = Double(centre.x) - note.w / 2
        out.y = Double(centre.y) - note.h / 2
        return out
    }
}

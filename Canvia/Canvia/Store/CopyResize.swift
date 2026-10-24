// Copy & resize: one new design per size ticked, each the original reflowed
// to that size, and the original left exactly as it was.
//
// A copy is the design again with every id fresh — the design's, each
// page's and each element's — made page by page through Copies, so arrows
// stay joined to the copies of their boxes, groups, tables and charts stay
// whole, and the master page is still the master. It is then reflowed as
// Resize's Reflow does it (DesignStore.reflowed), takes the size's unit, and
// is titled "<title> – <size>" under a name the shelf does not have yet.
// Photos, clips and fonts are shared with the original by reference, as a
// duplicate shares them; the launch sweep reads every design, so a photo
// either one uses is kept. No undo step is recorded: nothing open changed.
// The Android twin's CopyResize, rule for rule.

import Foundation

/// One size a copy is made at: a design type, or a size typed.
struct ResizeTarget: Hashable, Identifiable {
    /// The design type's name; nil for a size typed.
    var name: String?
    /// Whole pixels.
    var width: Double
    var height: Double
    /// "mm", "cm" or "in"; nil is pixels.
    var unit: String?
    var dpi: Double?

    var id: String { "\(name ?? "custom")|\(Int(width))x\(Int(height))|\(unit ?? "px")" }

    static func preset(_ p: SizePreset) -> ResizeTarget {
        ResizeTarget(name: p.name, width: p.w, height: p.h, unit: p.unit, dpi: p.dpi)
    }

    /// A size typed, in pixels, in `unit` — at 300 dpi when that is a
    /// physical one.
    static func custom(width: Double, height: Double, unit: String) -> ResizeTarget {
        let physical = Units.isPhysical(unit)
        return ResizeTarget(name: nil, width: width, height: height,
                            unit: physical ? unit : nil, dpi: physical ? Units.printDPI : nil)
    }

    /// What it is called in a copy's title: the type's name, else its size
    /// in its unit — "1600 × 900", "210 × 297 mm".
    var label: String {
        name ?? Units.dimensions(width: width, height: height, unit: unit, dpi: dpi)
    }
}

enum CopyResize {

    /// "<title> – <size>": an en dash, spaced, as on Android.
    static func title(_ title: String, target: ResizeTarget) -> String {
        let base = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base.isEmpty ? tr("Untitled design") : base) – \(target.label)"
    }

    /// The editor's Make a copy: "<title> copy".
    static func copyTitle(_ title: String) -> String {
        let base = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return tr("%@ copy", base.isEmpty ? tr("Untitled design") : base)
    }

    /// The design again with every id fresh: its own, each page's (the
    /// master page id following its page) and each element's, by Copies'
    /// rules. Everything else — size, unit, folder, title — as it was, but
    /// the star: a copy is not starred.
    static func freshCopy(of design: Design) -> Design {
        var copy = design
        copy.id = UID.make("doc")
        copy.isStarred = false
        var pageIds: [String: String] = [:]
        copy.pages = design.pages.map { page in
            let fresh = Copies.of(page)
            pageIds[page.id] = fresh.id
            return fresh
        }
        copy.masterPageId = design.masterPageId.flatMap { pageIds[$0] }
        // What else names a page by its id follows it: the talks' pages,
        // the holds Beat Sync keeps and the links to pages.
        copy = Links.withPageIds(BeatSync.withPageIds(Recordings.withPageIds(copy, pageIds), pageIds), pageIds)
        copy.guides = design.guides.map { guide in
            var g = guide
            g.id = UID.make("guide")
            return g
        }
        return copy
    }

    /// One copy of `design` at `target`: fresh ids, reflowed, in the
    /// target's unit, titled `title`, in the same folder, with a title a
    /// person chose (so it never renames itself), made `now`.
    static func copy(of design: Design, to target: ResizeTarget, title: String, now: Date = Date()) -> Design {
        var copy = DesignStore.reflowed(freshCopy(of: design), width: target.width, height: target.height)
        copy.unit = target.unit
        copy.dpi = target.dpi
        copy.title = title
        copy.titleAuto = false
        copy.folder = design.folder
        copy.createdAt = now.timeIntervalSince1970 * 1000
        copy.updatedAt = copy.createdAt
        return copy
    }

    /// The editor's Make a copy: the design whole with fresh ids, titled
    /// "<title> copy" under a name the shelf does not have, never renaming
    /// itself, made `now`.
    static func madeCopy(of design: Design, taken: [String], now: Date = Date()) -> Design {
        var copy = freshCopy(of: design)
        copy.title = Titles.unique(copyTitle(design.title), taken: taken)
        copy.titleAuto = false
        copy.createdAt = now.timeIntervalSince1970 * 1000
        copy.updatedAt = copy.createdAt
        return copy
    }

    /// Every copy, in the order the sizes are given, each titled so no two
    /// — nor any already on the shelf (`taken`) — read the same.
    static func copies(of design: Design, to targets: [ResizeTarget], taken: [String],
                       now: Date = Date()) -> [Design] {
        var used = taken
        return targets.map { target in
            let name = Titles.unique(title(design.title, target: target), taken: used)
            used.append(name)
            return copy(of: design, to: target, title: name, now: now)
        }
    }

    /// The button: "Make 1 copy", "Make 3 copies".
    static func buttonTitle(count: Int) -> String {
        trn("Make %d copy|Make %d copies", count)
    }

    /// While they are made: "Making copy 2 of 3…".
    static func progressText(_ n: Int, of total: Int) -> String {
        tr("Making copy %d of %d…", n, total)
    }

    /// When none could be saved — the disk full, say — as Android says it.
    static let failedText = tr("Couldn't make the copies")

    /// Afterwards: "Made 1 resized copy", "Made 3 resized copies".
    static func doneText(count: Int) -> String {
        trn("Made %d resized copy|Made %d resized copies", count)
    }

    /// Whether a design has anything on it, so the Resize sheet opens on
    /// Copy & resize rather than resizing it in place.
    static func hasContent(_ design: Design) -> Bool {
        design.pages.contains { !$0.elements.isEmpty }
    }

    /// Saves each copy and its picture, one at a time with `progress(n)`
    /// before the nth — the file written away from the main actor, the
    /// picture drawn on it, where ImageRenderer works. Returns the copies
    /// saved; a Cancel stops between copies.
    @MainActor
    static func save(_ copies: [Design], progress: (Int) -> Void) async throws -> [Design] {
        var saved: [Design] = []
        for (n, copy) in copies.enumerated() {
            try Task.checkCancellation()
            progress(n + 1)
            let ok = await Task.detached(priority: .userInitiated) { DesignLibrary.save(copy) }.value
            guard ok else { continue }
            DesignLibrary.writeThumbnail(for: copy)
            saved.append(copy)
            // A breath between copies, so the progress line is drawn.
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return saved
    }
}

/// The designs Home shows highlighted the next time it appears: the copies
/// just made, from the editor's "Made 3 resized copies".
enum HomeHighlight {
    static var ids: [String] = []

    /// The ids waiting, cleared so they are shown once.
    static func take() -> [String] {
        defer { ids = [] }
        return ids
    }
}

// Reopening a design where you left off, as Canva returns to the page you
// were editing. A record on this phone alone — never in the design, so
// opening one changes neither its edit time nor its versions, and never in
// a backup — under the preference "lastPlace":
// {"<designId>": {"page": "<pageId>", "zoom": 1.5, "scroll": 0.42, "t": <epoch ms>}}.
// "zoom" is written only when the view was not at fit (fit is the key left
// out), "scroll" only for a Doc: how far down its blocks the top of the
// view was, 0 to 1. At most `limit` designs are kept, the longest unopened
// going first. Written as the editor leaves a page, closes or goes to the
// background; read as it opens, unless Settings ▸ Editing's "Open designs
// where I left off" ("resumePlace", on unless turned off) is off.
// Deleting a design, or emptying Recently deleted, takes its entry away.
// The Android twin's LastPlace, row for row.

import Foundation

enum LastPlace {

    static let key = "lastPlace"
    static let resumeKey = "resumePlace"

    /// The most designs kept.
    static let limit = 200

    struct Place: Equatable {
        /// The page's id.
        var page: String
        /// The zoom, nil at fit.
        var zoom: Double?
        /// A Doc's scroll, 0 to 1; nil for any other design.
        var scroll: Double?
        /// When it was written, epoch milliseconds.
        var t: Double
    }

    // MARK: the preference

    /// The places kept, by design id, from the preference's JSON: those
    /// with a page and a time; none for anything else.
    static func decode(_ text: String?) -> [String: Place] {
        guard let data = text?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var out: [String: Place] = [:]
        for (id, value) in object {
            guard let entry = value as? [String: Any], let page = entry["page"] as? String,
                  let t = (entry["t"] as? NSNumber)?.doubleValue else { continue }
            let zoom = (entry["zoom"] as? NSNumber)?.doubleValue.nonZeroFinite
            let scroll = (entry["scroll"] as? NSNumber).map { min(max($0.doubleValue, 0), 1) }
            out[id] = Place(page: page, zoom: zoom, scroll: scroll, t: t)
        }
        return out
    }

    /// The places as the preference keeps them, ids in order.
    static func encode(_ places: [String: Place]) -> String {
        var object: [String: Any] = [:]
        for (id, place) in places {
            var entry: [String: Any] = ["page": place.page, "t": place.t]
            if let zoom = place.zoom { entry["zoom"] = zoom }
            if let scroll = place.scroll { entry["scroll"] = scroll }
            object[id] = entry
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// `places` with `place` kept for `designId`, then only the `limit`
    /// written last — the oldest going first, the lower id on a tie.
    static func remembered(_ places: [String: Place], designId: String, place: Place) -> [String: Place] {
        var out = places
        out[designId] = place
        guard out.count > limit else { return out }
        let oldest = out.sorted { a, b in a.value.t == b.value.t ? a.key < b.key : a.value.t < b.value.t }
        for (id, _) in oldest.prefix(out.count - limit) { out[id] = nil }
        return out
    }

    // MARK: where a design opens

    /// The page `design` opens on from `place`: that page if it is still
    /// there and shown, else the nearest shown page before it, else the
    /// page itself; the first page when it is gone or there is no place.
    static func pageIndex(_ design: Design, place: Place?) -> Int {
        guard let place, let at = design.pages.firstIndex(where: { $0.id == place.page }) else { return 0 }
        guard design.pages[at].hidden == true else { return at }
        return (0..<at).reversed().first { design.pages[$0].hidden != true } ?? at
    }

    /// The zoom to keep for a view at `zoom` where `fit` shows the whole
    /// page: nil within CanvasGestures.fitSlack of fit.
    static func keptZoom(_ zoom: Double, fit: Double) -> Double? {
        guard zoom.isFinite, zoom > 0, fit > 0 else { return nil }
        return abs(zoom / fit - 1) <= CanvasGestures.fitSlack ? nil : zoom
    }

    /// Whether Home and Present offer "Present from where I left off" for
    /// `design`: the place is kept and lands past the first page.
    static func offersPresent(_ design: Design, place: Place?) -> Bool {
        place != nil && pageIndex(design, place: place) > 0
    }

    static var presentTitle: String { tr("Present from where I left off") }

    // MARK: kept on this phone

    static func places(_ defaults: UserDefaults = .standard) -> [String: Place] {
        decode(defaults.string(forKey: key))
    }

    static func place(for designId: String, _ defaults: UserDefaults = .standard) -> Place? {
        places(defaults)[designId]
    }

    /// Whether designs open where they were left: on unless turned off.
    static func resumes(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: resumeKey) as? Bool ?? true
    }

    static func remember(_ designId: String, _ place: Place, _ defaults: UserDefaults = .standard) {
        defaults.set(encode(remembered(places(defaults), designId: designId, place: place)), forKey: key)
    }

    /// The entries of `ids` taken away: designs deleted for good.
    static func forget(_ ids: [String], _ defaults: UserDefaults = .standard) {
        var kept = places(defaults)
        let before = kept.count
        for id in ids { kept[id] = nil }
        if kept.count != before { defaults.set(encode(kept), forKey: key) }
    }

    /// Now, in epoch milliseconds.
    static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }
}

private extension Double {
    /// Itself when it is a finite number above 0; nil otherwise.
    var nonZeroFinite: Double? { isFinite && self > 0 ? self : nil }
}

// Platform safe zones for story, reel, TikTok and Shorts pages: where the
// platform's own profile row, caption, like and comment rail and progress
// bar cover a full-screen vertical post. The zones are SafeZones.json
// (Tools/generate_safezones.py), the Android twin's file byte for byte.
//
// A design carries the zone it shows as `safeZone`, a zone's id, written
// only when set: "none" turns the aid off, no key shows the first zone the
// page's size matches — so a story opens with its zone on — and a zone that
// does not match the page's size (or one this build does not know) shows
// that default instead. The canvas draws what is covered as a hatched band
// (SafeZoneLayer), never in an export, Present, a thumbnail or a video; the
// zone's inner edges are snap lines ("Safe zone"); and Check accessibility
// says of a shown text more than a fifth of whose box is covered "Text sits
// under the app's buttons" (AccessibilityAudit, kind safeZone). The Android
// twin's SafeZones, rule for rule, with the shared rows of safe-zones.json.

import CoreGraphics
import Foundation

enum SafeZones {

    /// The `safeZone` that turns the aid off.
    static let off = "none"

    /// More than this share of a text's box covered, and it is under the
    /// app's buttons.
    static let underShare = 0.2

    struct ZoneInsets: Codable, Equatable {
        var top: Double
        var bottom: Double
        var left: Double
        var right: Double
    }

    /// A rectangle the platform draws over, as fractions of the page.
    struct Rail: Codable, Equatable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }

    struct Zone: Codable, Equatable, Identifiable {
        var id: String
        var label: String
        var sizes: [[Double]]
        var insets: ZoneInsets
        var rails: [Rail]

        /// Whether the zone is for a page of `size`, exactly.
        func fits(_ size: CGSize) -> Bool {
            sizes.contains { $0.count == 2 && $0[0] == Double(size.width) && $0[1] == Double(size.height) }
        }
    }

    /// Every zone, in the file's order; read once.
    static let all: [Zone] = {
        guard let url = Bundle.main.url(forResource: "SafeZones", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return zones(from: data)
    }()

    /// The zones in `data`, each on its own: one that does not read is
    /// passed over.
    static func zones(from data: Data) -> [Zone] {
        ((try? JSONDecoder().decode([LenientZone].self, from: data)) ?? []).compactMap(\.zone)
    }

    private struct LenientZone: Decodable {
        var zone: Zone?
        init(from decoder: Decoder) throws { zone = try? Zone(from: decoder) }
    }

    static func zone(id: String?, in zones: [Zone] = all) -> Zone? {
        zones.first { $0.id == id }
    }

    /// The zones a page of `size` can show, in order: the picker's choices.
    static func matching(_ size: CGSize, in zones: [Zone] = all) -> [Zone] {
        zones.filter { $0.fits(size) }
    }

    /// The zone `design` shows by default: the first its own size matches.
    static func forDesign(_ design: Design, in zones: [Zone] = all) -> Zone? {
        matching(design.size, in: zones).first
    }

    /// The zone shown on `page` (see the top): none when the design says
    /// "none" or nothing matches the page's size.
    static func shown(_ design: Design, page: Page, in zones: [Zone] = all) -> Zone? {
        guard design.safeZone != off else { return nil }
        let choices = matching(design.size(for: page), in: zones)
        return choices.first { $0.id == design.safeZone } ?? choices.first
    }

    /// What `zone` covers on a page of `size`, in page units: its bands
    /// along the top, bottom, left and right, then its rails; none of no
    /// size.
    static func covered(_ zone: Zone, size: CGSize) -> [CGRect] {
        let w = Double(size.width), h = Double(size.height), i = zone.insets
        let bands = [
            CGRect(x: 0, y: 0, width: w, height: i.top * h),
            CGRect(x: 0, y: h - i.bottom * h, width: w, height: i.bottom * h),
            CGRect(x: 0, y: 0, width: i.left * w, height: h),
            CGRect(x: w - i.right * w, y: 0, width: i.right * w, height: h),
        ]
        let rails = zone.rails.map { CGRect(x: $0.x * w, y: $0.y * h, width: $0.w * w, height: $0.h * h) }
        return (bands + rails).filter { $0.width > 0 && $0.height > 0 }
    }

    /// The part of a page of `size` nothing covers but the rails: inside
    /// the insets.
    static func safeRect(_ zone: Zone, size: CGSize) -> CGRect {
        let w = Double(size.width), h = Double(size.height), i = zone.insets
        return CGRect(x: i.left * w, y: i.top * h, width: w * (1 - i.left - i.right), height: h * (1 - i.top - i.bottom))
    }

    /// The zone's inner edges, the lines a move snaps to: each inset's
    /// edge, and each rail edge that lies inside the page — never the
    /// page's own edges. Across (x) and down (y), in page units, each once.
    static func edges(_ zone: Zone, size: CGSize) -> (x: [Double], y: [Double]) {
        let w = Double(size.width), h = Double(size.height), i = zone.insets
        var xs: [Double] = [], ys: [Double] = []
        func addX(_ v: Double) { if v > 0 && v < w && !xs.contains(v) { xs.append(v) } }
        func addY(_ v: Double) { if v > 0 && v < h && !ys.contains(v) { ys.append(v) } }
        addY(i.top * h)
        addY(h - i.bottom * h)
        addX(i.left * w)
        addX(w - i.right * w)
        for r in zone.rails {
            addX(r.x * w)
            addX((r.x + r.w) * w)
            addY(r.y * h)
            addY((r.y + r.h) * h)
        }
        return (xs, ys)
    }

    /// How much of `box` the zone covers, 0 to 1: the area of the box under
    /// any covered part, counted once where they overlap, over the box's.
    static func coveredShare(of box: CGRect, zone: Zone, size: CGSize) -> Double {
        let area = Double(box.width * box.height)
        guard area > 0 else { return 0 }
        let parts = covered(zone, size: size).map { $0.intersection(box) }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        guard !parts.isEmpty else { return 0 }
        // The parts' edges cut the box into cells, each covered or not.
        let xs = Array(Set(parts.flatMap { [$0.minX, $0.maxX] })).sorted()
        let ys = Array(Set(parts.flatMap { [$0.minY, $0.maxY] })).sorted()
        var under = 0.0
        for a in 0..<(xs.count - 1) {
            for b in 0..<(ys.count - 1) {
                let mid = CGPoint(x: (xs[a] + xs[a + 1]) / 2, y: (ys[b] + ys[b + 1]) / 2)
                if parts.contains(where: { $0.contains(mid) }) {
                    under += Double((xs[a + 1] - xs[a]) * (ys[b + 1] - ys[b]))
                }
            }
        }
        return under / area
    }

    /// Whether `box` is under the app's buttons: more than underShare of
    /// it covered.
    static func isUnder(_ box: CGRect, zone: Zone, size: CGSize) -> Bool {
        coveredShare(of: box, zone: zone, size: size) > underShare
    }

    /// `box` moved by the least into the safe rect — flush with its left or
    /// top edge on an axis where it is bigger than the rect: Move inside.
    static func movedInside(_ box: CGRect, zone: Zone, size: CGSize) -> CGRect {
        let safe = safeRect(zone, size: size)
        func shift(_ low: CGFloat, _ high: CGFloat, _ from: CGFloat, _ to: CGFloat) -> CGFloat {
            if high - low > to - from || low < from { return from - low }
            if high > to { return to - high }
            return 0
        }
        return box.offsetBy(dx: shift(box.minX, box.maxX, safe.minX, safe.maxX),
                            dy: shift(box.minY, box.maxY, safe.minY, safe.maxY))
    }

    /// The Snapping and guides sheet's name for a zone, and for none.
    static func label(_ zone: Zone?) -> String {
        zone?.label ?? tr("Off")
    }
}

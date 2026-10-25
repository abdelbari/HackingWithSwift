// The export sheet's Share to row: the social apps installed on this phone,
// each a tap that exports the design in the type that app takes and hands
// it straight to it — the Android twin's ShareTargets, rule for rule. The
// apps, their ids and their order are the same on both phones; how one is
// found installed and handed the file is each phone's own: here
// canOpenURL on its URL scheme (Info.plist's LSApplicationQueriesSchemes),
// the file saved to Photos and the app opened on its library where it has
// a URL for one, else the share sheet with the file in it.

import Foundation

enum ShareTargets {

    /// The recent targets, newest first, kept on this phone under this
    /// preference as the Android twin keeps them: `["instagram", …]`.
    static let key = "shareTargets"

    /// The most the row shows, and the most recent ones kept.
    static let maxShown = 5
    static let maxRecent = 6

    /// One app: its id, its name, the Android twin's package, this phone's
    /// URL scheme, the design type (SizePreset) whose width its pictures are
    /// made at — nil to keep the design's own — the prefix of the design
    /// types that are its own, which put it first, and the URL that opens
    /// it on its photo library, where it has one.
    struct Target: Equatable, Identifiable {
        var id: String
        var name: String
        var packageName: String
        var scheme: String
        var sizeId: String?
        var typePrefix: String?
        var library: String? = nil

        /// What canOpenURL asks about.
        var url: URL? { URL(string: scheme + "://") }
    }

    static let all: [Target] = [
        Target(id: "instagram", name: "Instagram", packageName: "com.instagram.android", scheme: "instagram",
               sizeId: "insta-post", typePrefix: "insta-", library: "instagram://library"),
        Target(id: "tiktok", name: "TikTok", packageName: "com.zhiliaoapp.musically", scheme: "tiktok",
               sizeId: "tiktok-video", typePrefix: "tiktok-"),
        Target(id: "whatsapp", name: "WhatsApp", packageName: "com.whatsapp", scheme: "whatsapp",
               sizeId: nil, typePrefix: nil),
        Target(id: "facebook", name: "Facebook", packageName: "com.facebook.katana", scheme: "fb",
               sizeId: "facebook-post", typePrefix: "facebook-"),
        Target(id: "pinterest", name: "Pinterest", packageName: "com.pinterest", scheme: "pinterest",
               sizeId: "pinterest-pin", typePrefix: "pinterest-"),
        Target(id: "linkedin", name: "LinkedIn", packageName: "com.linkedin.android", scheme: "linkedin",
               sizeId: "linkedin-post", typePrefix: "linkedin-"),
    ]

    static func byId(_ id: String) -> Target? { all.first { $0.id == id } }

    /// The row for a design of type `typeId` (DesignLibrary.typeOf): of the
    /// targets `installed` (by id), the one whose design types it is —
    /// insta-* puts Instagram first — then the `recent` ones, newest first,
    /// then the rest in `all`'s order; at most maxShown.
    static func ordered(_ typeId: String?, installed: Set<String>, recent: [String] = []) -> [Target] {
        let own = all.filter { t in
            guard let typeId, let prefix = t.typePrefix else { return false }
            return typeId.hasPrefix(prefix)
        }
        var seen = Set<String>()
        let candidates = own + recent.compactMap(byId) + all
        let row = candidates.filter { seen.insert($0.id).inserted && installed.contains($0.id) }
        return Array(row.prefix(maxShown))
    }

    /// What a target is sent: "mp4" for a design that moves or sounds
    /// (ExportSuggestion's "mp4"), else its suggested picture — "jpg" for a
    /// photo, "png" otherwise. A document's "pdf" and a website's "html"
    /// are sent as pictures too: these apps take pictures and films.
    static func format(_ design: Design, presets: [SizePreset] = SizePreset.all) -> String {
        switch ExportSuggestion.suggest(design, presets: presets) {
        case "mp4": return "mp4"
        case "jpg": return "jpg"
        default: return "png"
        }
    }

    /// The scale a picture is made at for `target`: its design type's width
    /// over the design's, so a post comes out at the width the app shows it
    /// at; 1 for a target with no type, or a design of no width. A carousel
    /// (its first page split, PageSplit) goes as its slides, so one slide's
    /// width is what is matched: Instagram's 1080 for each of a 3240-wide
    /// carousel's three, not 360. Both phones' rule.
    static func scale(_ design: Design, target: Target, presets: [SizePreset] = SizePreset.all) -> Double {
        guard let id = target.sizeId, let preset = presets.first(where: { $0.id == id }) else { return 1 }
        let across = max(design.pages.first?.split?.columns ?? 1, 1)
        let slide = design.width / Double(across)
        return slide > 0 ? preset.w / slide : 1
    }

    /// `recent` with `id` first, once, and at most maxRecent.
    static func remembered(_ recent: [String], id: String) -> [String] {
        Array(([id] + recent.filter { $0 != id }).prefix(maxRecent))
    }

    /// The recent targets from the preference's JSON: known ids only, once
    /// each, at most maxRecent.
    static func decode(_ text: String?) -> [String] {
        guard let data = text?.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        var out: [String] = []
        for item in array {
            guard let id = item as? String, byId(id) != nil, !out.contains(id) else { continue }
            out.append(id)
        }
        return Array(out.prefix(maxRecent))
    }

    static func encode(_ recent: [String]) -> String { RecentSearches.encode(recent) }

    /// "Instagram isn't installed on this phone": said when an app the
    /// sheet offered has gone, rather than a dead icon.
    static func notInstalled(_ target: Target) -> String {
        tr("%@ isn't installed on this phone", target.name)
    }

    /// "Share to Instagram": the icon's name for a screen reader.
    static func shareTo(_ target: Target) -> String { tr("Share to %@", target.name) }

    // MARK: kept on this phone

    static func recent(_ defaults: UserDefaults = .standard) -> [String] {
        decode(defaults.string(forKey: key))
    }

    static func remember(_ id: String, _ defaults: UserDefaults = .standard) {
        defaults.set(encode(remembered(recent(defaults), id: id)), forKey: key)
    }
}

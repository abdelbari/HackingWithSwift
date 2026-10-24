// Settings ▸ Accessibility: preferences of the phone, never of a design,
// kept under the same keys on both phones and carried in a backup's
// settings.json (Backup.encodeSettings) — the Android twin's
// AccessibilityPrefs.
//
//  - "a11yReduceMotion": "system" (as the phone says), "on" or "off" —
//    element animations in the editor and Present, never an export.
//  - "a11yAutoplayClips": true, unless turned off: false keeps clips paused
//    in the editor until tapped.
//  - "a11yAltTextPrompt": false, unless turned on: true asks for alt text
//    right after a photo, graphic or chart is added.
//  - "a11yUnderlineLinks": false, unless turned on: true underlines linked
//    words in the editor and Present only.
//  - "a11yLargerHandles": false, unless turned on: true makes selection
//    handles and their hit targets `largerScale` times as big.
//
// And one of Settings ▸ Editing kept with them, on this phone only:
//
//  - "canvia.showDistances": true, unless turned off: a move, or a hold
//    still on what is selected, measures the distances to its neighbours
//    and the page's edges (Geometry.nearestDistances).

import Foundation

enum AccessibilityPrefs {

    static let reduceMotionKey = "a11yReduceMotion"
    static let autoplayClipsKey = "a11yAutoplayClips"
    static let altTextPromptKey = "a11yAltTextPrompt"
    static let underlineLinksKey = "a11yUnderlineLinks"
    static let largerHandlesKey = "a11yLargerHandles"
    static let showDistancesKey = "canvia.showDistances"

    /// Whether moving measures the distances round what moves: on unless
    /// turned off.
    static func showsDistances(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showDistancesKey) as? Bool ?? true
    }

    static let system = "system"
    static let on = "on"
    static let off = "off"

    /// Reduce motion's choices, in the order the row offers them.
    static let reduceMotionChoices = [system, on, off]

    /// How much bigger Larger handles makes them.
    static let largerScale = 1.4

    /// A Reduce motion value as kept, anything else "system".
    static func reduceMotionOf(_ value: String?) -> String {
        value.flatMap { reduceMotionChoices.contains($0) ? $0 : nil } ?? system
    }

    /// Whether element animations are left out: as the phone says for
    /// "system" (`systemReduces`), else as chosen.
    static func reducesMotion(_ value: String?, systemReduces: Bool) -> Bool {
        switch reduceMotionOf(value) {
        case on: return true
        case off: return false
        default: return systemReduces
        }
    }

    /// The scale the handles are drawn and hit at.
    static func handleScale(larger: Bool) -> Double { larger ? largerScale : 1 }

    /// Reduce motion's name on its row.
    static func reduceMotionName(_ value: String) -> String {
        switch value {
        case on: return tr("On")
        case off: return tr("Off")
        default: return tr("System")
        }
    }

    /// Whether an element just added is one Ask for alt text asks about: a
    /// photo, a graphic or a chart.
    static func prompts(_ el: Element) -> Bool {
        AccessibilityAudit.isPicture(el) || el.graphicId != nil || el.chart != nil
    }

    // MARK: kept on the phone

    /// The settings as a backup carries them; nil is one this phone keeps
    /// as it is, the file having none.
    struct Settings: Equatable {
        var reduceMotion: String?
        var autoplayClips: Bool?
        var altTextPrompt: Bool?
        var underlineLinks: Bool?
        var largerHandles: Bool?
    }

    /// This phone's, every one of them, defaults where none was set.
    static func current(_ defaults: UserDefaults = .standard) -> Settings {
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        return Settings(reduceMotion: reduceMotionOf(defaults.string(forKey: reduceMotionKey)),
                        autoplayClips: flag(autoplayClipsKey, true),
                        altTextPrompt: flag(altTextPromptKey, false),
                        underlineLinks: flag(underlineLinksKey, false),
                        largerHandles: flag(largerHandlesKey, false))
    }

    /// `settings` kept on this phone, those it has.
    static func apply(_ settings: Settings, to defaults: UserDefaults = .standard) {
        if let v = settings.reduceMotion { defaults.set(reduceMotionOf(v), forKey: reduceMotionKey) }
        if let v = settings.autoplayClips { defaults.set(v, forKey: autoplayClipsKey) }
        if let v = settings.altTextPrompt { defaults.set(v, forKey: altTextPromptKey) }
        if let v = settings.underlineLinks { defaults.set(v, forKey: underlineLinksKey) }
        if let v = settings.largerHandles { defaults.set(v, forKey: largerHandlesKey) }
    }

    /// `settings` written into a settings object, those it has.
    static func write(_ settings: Settings, into object: inout [String: Any]) {
        if let v = settings.reduceMotion { object[reduceMotionKey] = reduceMotionOf(v) }
        if let v = settings.autoplayClips { object[autoplayClipsKey] = v }
        if let v = settings.altTextPrompt { object[altTextPromptKey] = v }
        if let v = settings.underlineLinks { object[underlineLinksKey] = v }
        if let v = settings.largerHandles { object[largerHandlesKey] = v }
    }

    /// The settings in a backup's settings.json: a key missing, or of
    /// another kind — a choice it does not know, a flag in words — is nil.
    static func decodeSettings(_ data: Data?) -> Settings {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Settings() }
        func flag(_ key: String) -> Bool? {
            // A JSON true or false, not a number that would read as one.
            guard let n = object[key] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
            return n.boolValue
        }
        let motion = (object[reduceMotionKey] as? String).flatMap { reduceMotionChoices.contains($0) ? $0 : nil }
        return Settings(reduceMotion: motion, autoplayClips: flag(autoplayClipsKey), altTextPrompt: flag(altTextPromptKey),
                        underlineLinks: flag(underlineLinksKey), largerHandles: flag(largerHandlesKey))
    }
}

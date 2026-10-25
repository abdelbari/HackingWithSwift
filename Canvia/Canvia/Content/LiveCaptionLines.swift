// Live captions in Present: what the presenter says, heard by the phone's
// own recogniser (LiveCaptioner) and drawn over the slide for the audience —
// on the phone and on an attached display alike, never in an export. At
// most `maxLines` lines, white on a band of black at `bandAlpha`, gone
// `hideSeconds` after the last word. The pure parts, shared with the
// Android twin's LiveCaptionLines (Fixtures/live-captions.json): the lines
// (`wrap`) and the setting (`Settings`).

import Foundation

enum LiveCaptionLines {

    /// The setting's key among the phone's preferences.
    static let pref = "presentCaptions"

    static let maxLines = 2

    /// The band behind the words: black at this opacity.
    static let bandAlpha = 0.7

    /// Seconds of silence before the captions go.
    static let hideSeconds = 3.0

    /// The recogniser is started again this often, as one task stops
    /// listening after about a minute.
    static let restartSeconds = 55.0

    /// How soon it listens again after a stretch of speech ends.
    static let relistenSeconds = 0.25

    /// The sizes and where the band sits.
    static let small = "small"
    static let medium = "medium"
    static let large = "large"
    static let sizes = [small, medium, large]
    static let bottom = "bottom"
    static let top = "top"
    static let positions = [bottom, top]

    /// What the menu calls a size or a position.
    static func name(_ choice: String) -> String {
        switch choice {
        case small: return tr("Small")
        case large: return tr("Large")
        case top: return tr("Top")
        case bottom: return tr("Bottom")
        default: return tr("Medium")
        }
    }

    /// The letters' height, a share of the stage's shorter side, by size.
    static func textShare(_ size: String) -> Double {
        switch size {
        case small: return 0.04
        case large: return 0.065
        default: return 0.05
        }
    }

    /// The most characters a line holds, by size: the larger the type, the
    /// fewer.
    static func lineChars(_ size: String) -> Int {
        switch size {
        case small: return 48
        case large: return 32
        default: return 40
        }
    }

    /// {"on": false, "size": "medium", "position": "bottom"}; a value this
    /// build does not know reads as the default.
    struct Settings: Equatable {
        var on = false
        var size = LiveCaptionLines.medium
        var position = LiveCaptionLines.bottom

        /// The three keys in the twin's order.
        func encoded() -> String {
            "{\"on\":\(on),\"size\":\"\(size)\",\"position\":\"\(position)\"}"
        }

        static func decoded(_ text: String?) -> Settings {
            guard let data = text?.data(using: .utf8),
                  let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return Settings() }
            var out = Settings()
            // A number is no switch, even one JSONSerialization would read as one.
            if let on = o["on"] as? NSNumber, CFGetTypeID(on) == CFBooleanGetTypeID() { out.on = on.boolValue }
            if let size = o["size"] as? String, LiveCaptionLines.sizes.contains(size) { out.size = size }
            if let position = o["position"] as? String, LiveCaptionLines.positions.contains(position) {
                out.position = position
            }
            return out
        }
    }

    /// Whether `c` parts words: any space, a line's end, a tab, or a zero
    /// width space, as the Android twin's Captions.blank.
    private static func blank(_ c: Character) -> Bool {
        c.isWhitespace || c == "\u{200B}"
    }

    /// The lines shown for `text`, what has been heard so far: its words
    /// laid into lines of at most `maxChars` characters, a word that is
    /// longer cut into pieces that long, and the last `maxLines` of them —
    /// so the newest words are always up and the oldest scroll off the top.
    static func wrap(_ text: String, maxChars: Int) -> [String] {
        let width = max(maxChars, 1)
        var words: [String] = []
        for word in text.split(whereSeparator: blank) {
            var rest = Substring(word)
            while !rest.isEmpty {
                words.append(String(rest.prefix(width)))
                rest = rest.dropFirst(width)
            }
        }
        var lines: [String] = []
        var line = ""
        for w in words {
            if !line.isEmpty && line.count + 1 + w.count > width {
                lines.append(line)
                line = ""
            }
            if !line.isEmpty { line += " " }
            line += w
        }
        if !line.isEmpty { lines.append(line) }
        return Array(lines.suffix(maxLines))
    }

    /// The contrast of white words on the band at its weakest — the band
    /// over a white slide — by WCAG's ratio: what keeps them at 4.5:1 or
    /// better whatever the slide.
    static func worstContrast() -> Double {
        let grey = Int(((1 - bandAlpha) * 255).rounded())
        return ContrastAudit.ratio("#ffffff", String(format: "#%02x%02x%02x", grey, grey, grey))
    }
}

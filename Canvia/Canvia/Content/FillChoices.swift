// Which of the fill picker's gradients, patterns and photo fills is the one
// already there — ringed and said to be chosen, and not recorded again when
// tapped — as the Android twin's pickers mark theirs.

import Foundation

enum FillChoices {
    /// The same gradient: kind, angle, shape and every stop.
    static func isGradient(_ current: Paint?, _ candidate: Paint) -> Bool {
        GradientPreset.same(current, candidate)
    }

    /// The same pattern, by name — its colour follows the swatches.
    static func isPattern(_ current: Paint?, named name: String) -> Bool {
        current?.kind == "pattern" && current?.pattern == name
    }

    /// The same photo pouring into the shape.
    static func isPhoto(_ current: Paint?, src: String) -> Bool {
        current?.kind == "image" && current?.src == src
    }

    /// Whether patterns and photo fills are worth offering: only a shape
    /// draws them. Text draws a colour or a gradient and nothing else, so
    /// offering it a pattern saved a fill that never showed.
    static func offersPatterns(for elements: [Element]) -> Bool {
        elements.contains { $0.type == .shape && !Freehand.isStroke($0) }
    }

    // MARK: photo fills

    /// How many of the built-in pictures lead the Photo fill row.
    static let builtInPhotoFills = 8

    /// The pictures a shape can be filled with: the first eight built-in
    /// ones, then every picture the design already shows, each once. A QR
    /// code is left out — a shape full of a code's squares is nobody's
    /// fill, and through a star it would not scan. As the Android twin.
    static func photoFillSources(_ design: Design) -> [String] {
        var out = PhotoLibrary.photos.prefix(builtInPhotoFills).map { "asset:\($0.id)" }
        for page in design.pages {
            for el in page.elements where el.type == .image {
                guard let src = el.src, CodeGenerator.payload(from: src) == nil, !out.contains(src) else { continue }
                out.append(src)
            }
        }
        return out
    }

    /// What a Photo fill tile says: the built-in picture's name, or which
    /// of the design's own it is — "Fill with photo" for every one left no
    /// way to choose.
    static func photoFillLabel(_ src: String, sources: [String]) -> String {
        if let photo = builtInPhoto(src) { return "Fill with \(photo.name)" }
        let own = sources.filter { builtInPhoto($0) == nil }
        guard let n = own.firstIndex(of: src) else { return "Fill with photo" }
        return "Fill with photo \(n + 1) of \(own.count) from this design"
    }

    private static func builtInPhoto(_ src: String) -> PhotoDef? {
        guard src.hasPrefix("asset:") else { return nil }
        let id = String(src.dropFirst("asset:".count))
        return PhotoLibrary.photos.first { $0.id == id }
    }

    // MARK: spoken

    /// What a shape's Fill chip says when its fill is not one colour —
    /// "gradient from dark blue", "photo", "red pattern", "no fill" — or
    /// nil when it is, and the colour's name says it. As the Android twin.
    static func spokenFill(_ fill: Paint?) -> String? {
        switch fill?.kind {
        case "gradient": return "gradient from \(ElementNames.colourName(fill?.primaryColor))"
        case "image": return "photo"
        case "pattern": return "\(ElementNames.colourName(fill?.color)) pattern"
        case "none": return "no fill"
        default: return nil
        }
    }
}

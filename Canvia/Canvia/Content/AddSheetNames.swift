// What the Add sheet's picture tiles say to VoiceOver.
//
// Every upload used to read "Uploaded picture" and every built-in picture
// nothing at all, so a list of forty read as forty of the same. As the
// Android twin says them: which one it is and where in the list, then
// whether it is starred and whether it is the one already in the frame
// being replaced.

import Foundation

enum AddSheetNames {
    static func picture(_ name: String, starred: Bool, inFrame: Bool) -> String {
        var label = name
        if starred { label = tr("%@, favourite", label) }
        if inFrame { label = tr("%@, the one in this frame now", label) }
        return label
    }

    static func upload(_ index: Int, of count: Int) -> String {
        tr("Uploaded picture %d of %d", index + 1, count)
    }

    /// An SVG kept among the uploads, placed again as a graphic.
    static func uploadedGraphic(_ index: Int, of count: Int) -> String {
        tr("Uploaded SVG graphic %d of %d", index + 1, count)
    }

    static func uploadedVideo(_ index: Int, of count: Int) -> String {
        tr("Uploaded video %d of %d", index + 1, count)
    }

    /// A song by its own name and its place, then whether it is starred and
    /// whether the design plays it on a track already.
    static func music(_ name: String, _ index: Int, of count: Int, starred: Bool, playing: Bool) -> String {
        var label = tr("%@, music %d of %d", name, index + 1, count)
        if starred { label = tr("%@, favourite", label) }
        if playing { label = tr("%@, in this design", label) }
        return label
    }

    static func logo(_ index: Int, of count: Int) -> String {
        tr("Brand logo %d of %d", index + 1, count)
    }

    static func brandPhoto(_ index: Int, of count: Int) -> String {
        tr("Brand photo %d of %d", index + 1, count)
    }

    static func brandGraphic(_ index: Int, of count: Int) -> String {
        tr("Brand graphic %d of %d", index + 1, count)
    }

    /// A brand colour by its name — the one the kit gives it, else its
    /// hue's — and what a tap paints with it.
    static func brandColour(_ hex: String, name: String?, selection: Bool) -> String {
        let said = name ?? ElementNames.spokenColour(hex)
        return selection ? tr("%@, brand colour, for what is selected", said)
            : tr("%@, brand colour, for the page background", said)
    }

    static func artwork(_ photo: PhotoDef, _ index: Int, of count: Int) -> String {
        tr("%@, %@, artwork %d of %d", photo.name, photo.category.lowercased(), index + 1, count)
    }
}

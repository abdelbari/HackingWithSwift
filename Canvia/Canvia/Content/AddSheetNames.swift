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
        if starred { label += ", favourite" }
        if inFrame { label += ", the one in this frame now" }
        return label
    }

    static func upload(_ index: Int, of count: Int) -> String {
        "Uploaded picture \(index + 1) of \(count)"
    }

    static func logo(_ index: Int, of count: Int) -> String {
        "Brand logo \(index + 1) of \(count)"
    }

    static func artwork(_ photo: PhotoDef, _ index: Int, of count: Int) -> String {
        "\(photo.name), \(photo.category.lowercased()), artwork \(index + 1) of \(count)"
    }
}

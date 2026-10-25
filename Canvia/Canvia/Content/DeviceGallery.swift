// Add's Gallery: the phone's own photos and videos inline at the top of Add
// ▸ Photos and Add ▸ Videos, newest first, with a chip for each Choice and
// a clip's length on its tile. On the iPhone the grid is the system's own
// inline photo picker — newest first, a clip's length on it, ticks numbered
// in the order picked — which asks for no permission: the phone shows only
// what is picked. A tap brings one in as a picked one comes in — into the
// selected empty frames first (PhotoFrames.fillOrder); Select picks
// several, and Add N brings them in in the order picked. What it brings in
// are ordinary uploads. The rules the Android twin's DeviceGallery keeps.

import Foundation

enum DeviceGallery {

    /// The most a Select brings in at once, as the picker button takes.
    static let maxPicks = 10

    /// The grid's columns: three, four on a tablet — a screen whose shorter
    /// side is at least 600 points. The system picker lays its own grid out
    /// so; kept for the rule both phones share.
    static func columns(smallestWidth: Double) -> Int {
        smallestWidth >= 600 ? 4 : 3
    }

    enum Choice: String, CaseIterable, Identifiable {
        case all, photos, videos
        /// Only where the phone keeps favourites the picker can show; the
        /// iPhone's picker has no such filter, so it is never offered here.
        case favourites

        var id: String { rawValue }

        /// The chip's words, in English: the catalogue's key.
        var label: String {
            switch self {
            case .all: return "All"
            case .photos: return "Photos"
            case .videos: return "Videos"
            case .favourites: return "Favourites"
            }
        }
    }

    /// The chips offered: every filter, Favourites only where the phone has
    /// them.
    static func filters(favourites: Bool) -> [Choice] {
        Choice.allCases.filter { favourites || $0 != .favourites }
    }

    /// The filter a tab opens on: Add ▸ Videos on Videos, Add ▸ Photos on
    /// All.
    static func startFilter(videosTab: Bool) -> Choice {
        videosTab ? .videos : .all
    }

    /// The button that brings the picked ones in: "Add 3".
    static func addLabel(_ count: Int) -> String {
        trn("Add %d|Add %d", count)
    }
}

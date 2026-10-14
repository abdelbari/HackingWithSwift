// The menu a still hold on the empty page brings up at the finger, as
// Canva's does: Paste — what was copied, put where you pressed — Paste page,
// Select all, Add text here and Background. The Android twin's HoldMenu,
// with the same items in the same order, and the same words.

import CoreGraphics
import Foundation

enum HoldMenu {

    enum HoldItem: String, CaseIterable, Identifiable {
        case paste, pastePage, selectAll, addText, background

        var id: String { rawValue }

        var title: String {
            switch self {
            case .paste: return "Paste"
            case .pastePage: return "Paste page"
            case .selectAll: return "Select all"
            case .addText: return "Add text here"
            case .background: return "Background"
            }
        }

        var symbol: String {
            switch self {
            case .paste: return "doc.on.clipboard"
            case .pastePage: return "doc.badge.plus"
            case .selectAll: return "checkmark.circle"
            case .addText: return "textformat"
            case .background: return "photo.artframe"
            }
        }
    }

    /// The items offered: Paste when there is something to paste — copied
    /// elements, or a picture another app left — Paste page when a page was
    /// copied, and the rest always.
    static func items(canPaste: Bool, canPastePage: Bool) -> [HoldItem] {
        HoldItem.allCases.filter { item in
            switch item {
            case .paste: return canPaste
            case .pastePage: return canPastePage
            default: return true
            }
        }
    }

    /// Where something `box` big goes when put down at `point` on a page of
    /// `page` size, as a top-left: centred on the point, then moved by the
    /// least that keeps it inside the page (PageColumn.clampToPage).
    static func placed(_ box: CGSize, at point: CGPoint, page: CGSize) -> CGPoint {
        let centred = CGRect(x: point.x - box.width / 2, y: point.y - box.height / 2,
                             width: box.width, height: box.height)
        return PageColumn.clampToPage(centred, page: page)
    }
}

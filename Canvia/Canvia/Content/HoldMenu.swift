// The menu a still hold on the empty page brings up at the finger, as
// Canva's does: Paste — what was copied, put where you pressed — Paste as
// plain text — another app's words as they read — Paste page, Select all,
// Unlock all and Show hidden when the page has locked or hidden things on
// it, Add text here, Background and Animate, the page's own animations. The
// Android twin's HoldMenu, with the same items in the same order, and the
// same words.

import CoreGraphics
import Foundation

enum HoldMenu {

    enum HoldItem: String, CaseIterable, Identifiable {
        case paste, pastePlain, pastePage, selectAll, unlockAll, showHidden, addText, background, animate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .paste: return tr("Paste")
            case .pastePlain: return tr("Paste as plain text")
            case .pastePage: return tr("Paste page")
            case .selectAll: return tr("Select all")
            // Never offered at 0: the pill and the menus name how many
            // (unlockAllTitle, showHiddenTitle), the Android twin's words.
            case .unlockAll: return HoldMenu.unlockAllTitle(0)
            case .showHidden: return HoldMenu.showHiddenTitle(0)
            case .addText: return tr("Add text here")
            case .background: return tr("Background")
            case .animate: return tr("Animate")
            }
        }

        var symbol: String {
            switch self {
            case .paste: return "doc.on.clipboard"
            case .pastePlain: return "doc.plaintext"
            case .pastePage: return "doc.badge.plus"
            case .selectAll: return "checkmark.circle"
            case .unlockAll: return "lock.open"
            case .showHidden: return "eye"
            case .addText: return "textformat"
            case .background: return "photo.artframe"
            case .animate: return "sparkles.rectangle.stack"
            }
        }
    }

    /// What Add text here's box says until it is typed over — the default
    /// text box's words, as on the Android twin; they open chosen, so the
    /// first key replaces them.
    static let words = tr("Your text here")

    /// The items offered: Paste when there is something to paste — copied
    /// elements, or a picture another app left — Paste as plain text when
    /// there are words to paste, Paste page when a page was copied, Unlock
    /// all when `locked` things are on a page that is not itself locked,
    /// Show hidden when `hidden` things are, and the rest always.
    static func items(canPaste: Bool, canPastePlain: Bool = false, canPastePage: Bool,
                      locked: Int = 0, hidden: Int = 0, pageLocked: Bool = false) -> [HoldItem] {
        HoldItem.allCases.filter { item in
            switch item {
            case .paste: return canPaste
            case .pastePlain: return canPastePlain
            case .pastePage: return canPastePage
            case .unlockAll: return locked > 0 && !pageLocked
            case .showHidden: return hidden > 0
            default: return true
            }
        }
    }

    /// "Unlock all (3)", for `count` locked things on the page.
    static func unlockAllTitle(_ count: Int) -> String { tr("Unlock all (%d)", count) }

    /// "Show hidden (2)", for `count` hidden things on the page.
    static func showHiddenTitle(_ count: Int) -> String { tr("Show hidden (%d)", count) }

    /// Where something `box` big goes when put down at `point` on a page of
    /// `page` size, as a top-left: centred on the point, then moved by the
    /// least that keeps it inside the page (PageColumn.clampToPage).
    static func placed(_ box: CGSize, at point: CGPoint, page: CGSize) -> CGPoint {
        let centred = CGRect(x: point.x - box.width / 2, y: point.y - box.height / 2,
                             width: box.width, height: box.height)
        return PageColumn.clampToPage(centred, page: page)
    }
}

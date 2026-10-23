// Larger Text in the editor's chrome. Menus, sheets and Home follow the
// system text size all the way up; the rows with no room to grow — the
// context toolbar, the pages bar, a page's header row, the selection's
// badges and the timeline — grow only to accessibility2, and past
// xxxLarge a toolbar item shows its icon alone, its word in the large
// content viewer a long press brings up and still read by VoiceOver. The
// canvas and the design's own text keep the sizes the person gave them.
// The Android twin's ui/LargeType.kt.

import SwiftUI

enum LargeType {
    /// The largest size the space-limited chrome grows to.
    static let chromeCap = DynamicTypeSize.accessibility2

    /// Whether a toolbar item shows its icon alone: past xxxLarge, where
    /// its word would push the row's other items out of reach.
    static func iconOnly(_ size: DynamicTypeSize) -> Bool {
        size > .xxxLarge
    }
}

extension View {
    /// Grows with Larger Text up to `LargeType.chromeCap`, no further.
    func chromeTypeSize() -> some View {
        dynamicTypeSize(...LargeType.chromeCap)
    }

    /// A toolbar item's icon and word in the large content viewer, which a
    /// long press shows at the accessibility sizes.
    func toolLargeContent(_ system: String, _ label: String) -> some View {
        accessibilityShowsLargeContentViewer {
            Image(systemName: system)
        } label: {
            Text(label)
        }
    }
}

/// A toolbar item's word under its icon — gone past xxxLarge, where the
/// large content viewer shows it, but still there for VoiceOver.
struct ToolCaption: View {
    var text: String
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if LargeType.iconOnly(typeSize) {
            Text(text)
                .font(Theme.controlLabel)
                .frame(width: 0, height: 0)
                .clipped()
        } else {
            Text(text).font(Theme.controlLabel)
        }
    }
}

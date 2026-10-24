// The Stickers tab's emoji: the whole catalogue (EmojiCatalogue), a tab
// for each of its eight groups, or what a search finds by name and words —
// the curated words the stickers always had among them. Only what this
// phone's emoji font draws is shown (EmojiGlyphs, CTFont; Paint.hasGlyph
// on the Android twin). One that takes a skin tone is shown, and put on the
// page, in the tone chosen last; a press and hold offers the five and none,
// and the one chosen is kept for next time (EmojiCatalogue.keepTone).
// What goes on the page is the sticker it always was.

import CoreText
import SwiftUI
import UIKit

struct EmojiPicker: View {
    let query: String
    let side: CGFloat
    /// Bumped when a favourite is toggled, so the tab re-reads the set.
    @Binding var favouritesVersion: Int
    let onPick: (String) -> Void
    /// What a sticker carries when it is held and dragged onto the page
    /// (LibraryDrag); none, and it is only tapped.
    var drag: ((String) -> LibraryDrag.Item)? = nil
    @State private var group = EmojiCatalogue.groups.first?.name ?? ""
    /// The emoji whose skin tones are offered, by its plain glyph.
    @State private var toning: String?
    @State private var tone: String? = EmojiCatalogue.lastTone()

    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var shown: [Emoji] {
        EmojiGlyphs.drawableOnes(searching ? EmojiCatalogue.search(query) : EmojiCatalogue.search("", in: group))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if searching {
                InsertSheet.header(tr("Emoji"))
            } else {
                tabs
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: side), spacing: 8)], spacing: 8) {
                ForEach(shown, id: \.g) { emoji in tile(emoji) }
            }
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EmojiCatalogue.groups) { g in tab(g.name) }
            }
            .padding(.top, 8)
        }
    }

    private func tab(_ name: String) -> some View {
        let selected = group == name
        return Button { group = name } label: {
            Text(tr(name))
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func tile(_ emoji: Emoji) -> some View {
        let glyph = EmojiCatalogue.toned(emoji.g, emoji.tone ? tone : nil)
        if emoji.tone {
            face(glyph, starred: emoji.g)
                .contentShape(Rectangle())
                .onTapGesture { onPick(glyph) }
                .onLongPressGesture { toning = emoji.g }
                .popover(isPresented: Binding(get: { toning == emoji.g }, set: { if !$0 { toning = nil } })) {
                    tones(emoji)
                        .presentationCompactAdaptation(.popover)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(emoji.name)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onPick(glyph) }
                .accessibilityAction(named: Text("Skin tone")) { toning = emoji.g }
        } else {
            Button { onPick(glyph) } label: { face(glyph, starred: emoji.g) }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji.name)
                .contextMenu { favouriteButton(emoji.g) }
                .modifier(LibraryDragTile(item: drag.map { carry in { carry(glyph) } }))
        }
    }

    /// `glyph` drawn, starred when `starred` — the emoji without a skin
    /// tone, which is what a favourite keeps, as on the Android twin.
    private func face(_ glyph: String, starred: String) -> some View {
        Text(glyph)
            .font(.largeTitle)
            .frame(width: side, height: side)
            .overlay(alignment: .topTrailing) {
                if Favorites.isFavorite("sticker", starred) { InsertSheet.favouriteStar.scaleEffect(0.8) }
            }
    }

    /// The five skin tones and none, each put on the page when chosen and
    /// kept for next time; and the star, as a press and hold gives any
    /// other sticker.
    private func tones(_ emoji: Emoji) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(([nil] + EmojiCatalogue.tones.map { Optional($0) }).enumerated()), id: \.offset) { pair in
                toneButton(emoji, pair.element, name: Self.toneNames[pair.offset])
            }
            Divider().frame(height: 28)
            favouriteButton(emoji.g)
                .labelStyle(.iconOnly)
        }
        .padding(8)
    }

    private func toneButton(_ emoji: Emoji, _ choice: String?, name: String) -> some View {
        Button {
            tone = choice
            EmojiCatalogue.keepTone(choice)
            toning = nil
            onPick(EmojiCatalogue.toned(emoji.g, choice))
        } label: {
            Text(EmojiCatalogue.toned(emoji.g, choice))
                .font(.title)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(choice == tone ? Theme.accentSubtle : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(choice == tone ? .isSelected : [])
    }

    /// What each choice is called aloud: none, then light to dark.
    private static var toneNames: [String] {
        [tr("No skin tone"), tr("Light skin tone"), tr("Medium-light skin tone"), tr("Medium skin tone"),
         tr("Medium-dark skin tone"), tr("Dark skin tone")]
    }

    private func favouriteButton(_ glyph: String) -> some View {
        let on = Favorites.isFavorite("sticker", glyph)
        return Button {
            Favorites.toggle("sticker", glyph)
            favouritesVersion += 1
        } label: {
            Label(on ? tr("Remove from favourites") : tr("Add to favourites"), systemImage: on ? "star.slash" : "star")
        }
    }
}

/// Which emoji this phone's font draws: a glyph for each of its code points
/// in Apple Color Emoji — the selector U+FE0F aside — and a flag's two
/// letters drawn as one, which they are not for a country the font has no
/// flag for. Each asked once, under a lock, as the sheet's views ask.
enum EmojiGlyphs {
    private static let lock = NSLock()
    private static var known: [String: Bool] = [:]
    private static let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 32, nil)

    static func drawableOnes(_ list: [Emoji]) -> [Emoji] {
        list.filter { drawable($0.g) }
    }

    static func drawable(_ glyph: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let found = known[glyph] { return found }
        let found = check(glyph)
        known[glyph] = found
        return found
    }

    private static func check(_ glyph: String) -> Bool {
        let scalars = glyph.unicodeScalars.filter { $0.value != 0xFE0F }
        var units: [UniChar] = []
        for scalar in scalars { units.append(contentsOf: String(scalar).utf16) }
        guard !units.isEmpty else { return false }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) else { return false }
        guard scalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) else { return true }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: [.font: font]))
        return CTLineGetGlyphCount(line) == 1
    }
}

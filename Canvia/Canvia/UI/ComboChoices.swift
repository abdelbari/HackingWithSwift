// Add ▸ Text's font combinations: chips for their categories, this phone's
// Recently used, From your brand when the kit sets a title, heading or body
// face, and the grid, two to a row — as the Android twin's Text tab lays
// them out. A tap hands the combination over (`onPick`).

import SwiftUI

struct ComboChoices: View {
    /// What is searched for: names, tags and categories (TextCombos.search).
    let search: String
    /// The active brand kit's faces, for From your brand.
    let fonts: BrandFonts
    var onPick: (TextCombos.Combo) -> Void
    /// The category chosen; nil is All.
    @State private var category: String?

    var body: some View {
        let combos = TextCombos.search(search, in: category)
        let browsing = search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && category == nil
        let recent = browsing ? TextCombos.named(RecentCombos.all()) : []
        let branded = combos.compactMap { TextCombos.branded($0, fonts: fonts) }
        return VStack(alignment: .leading, spacing: 10) {
            if combos.isEmpty && category == nil {
                noneFound(TextCombos.noneFound(search))
            } else {
                header(tr("Font combinations"))
                categoryChips
                if !recent.isEmpty { comboRow(tr("Recently used"), recent) }
                if !branded.isEmpty { comboRow(tr("From your brand"), branded) }
                grid(combos)
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(tr("All"), selected: category == nil) { category = nil }
                ForEach(TextCombos.categories, id: \.self) { name in
                    chip(tr(name), selected: category == name) {
                        category = category == name ? nil : name
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func grid(_ combos: [TextCombos.Combo]) -> some View {
        if combos.isEmpty {
            noneFound(tr("No %@ combinations match \u{201C}%@\u{201D}.", category.map { tr($0) } ?? "",
                         search.trimmingCharacters(in: .whitespacesAndNewlines)))
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(combos) { combo in tile(combo) }
            }
        }
    }

    /// A row of combinations under its own heading, swiped along —
    /// Recently used and From your brand.
    private func comboRow(_ title: String, _ combos: [TextCombos.Combo]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(combos) { combo in
                        tile(combo).frame(width: 150)
                    }
                }
            }
        }
    }

    /// A combination drawn as it goes on a page, its name under it.
    private func tile(_ combo: TextCombos.Combo) -> some View {
        Button {
            onPick(combo)
        } label: {
            VStack(spacing: 4) {
                thumb(combo)
                Text(combo.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(combo.name) font combination")
        .accessibilityValue(TextCombos.isAnimated(combo) ? tr("Animated") : "")
        .accessibilityAddTraits(.isButton)
    }

    /// An animated combination plays in its tile; the rest are pictures.
    @ViewBuilder
    private func thumb(_ combo: TextCombos.Combo) -> some View {
        if TextCombos.isAnimated(combo) {
            AnimatedComboThumb(combo: combo)
        } else {
            ComboThumb(combo: combo)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }

    private func noneFound(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}

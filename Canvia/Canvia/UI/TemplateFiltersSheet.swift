// Canva's Filters button for templates, on Home and in the Start sheet: a
// sheet of colour dots, Animated, With photos and Single page or Set; what
// is set shows as chips with an X under the search; nothing found says so,
// with Clear filters. The filter is kept for the session only
// (TemplateFilter.session). The Android twin's TemplateFiltersSheet.

import SwiftUI

/// The Filters button beside the template search, with how many are set.
struct TemplateFiltersButton: View {
    let filter: TemplateFilter
    var action: () -> Void

    var body: some View {
        let count = filter.chips.count
        Button(action: action) {
            Label(count == 0 ? tr("Filters") : tr("Filters") + " · \(count)",
                  systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline))
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
    }
}

/// What is set, as chips each with an X that takes it away; nothing when
/// no filter is set.
struct TemplateFilterChips: View {
    @Binding var filter: TemplateFilter

    var body: some View {
        let chips = filter.chips
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        Button { filter = chip.without } label: { chipLabel(chip.label) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tr("Remove filter %@", chip.label))
                    }
                }
            }
        }
    }

    private func chipLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: "xmark").font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.accent, in: Capsule())
        .foregroundStyle(Color.white)
    }
}

/// What an empty result says, with the way out of it.
struct NoTemplatesMatch: View {
    var clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TemplateFilter.noMatch)
                .foregroundStyle(.secondary)
            Button("Clear filters", action: clear)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
    }
}

/// The sheet: each change applies at once.
struct TemplateFiltersSheet: View {
    @Binding var filter: TemplateFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Colour")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    dots
                    HStack(spacing: 8) {
                        toggleChip(tr("Animated"), on: filter.animated == true) {
                            filter.animated = filter.animated == true ? nil : true
                        }
                        toggleChip(tr("With photos"), on: filter.photo == true) {
                            filter.photo = filter.photo == true ? nil : true
                        }
                    }
                    Text("Pages")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    pagesRow
                    Button("Clear filters") { filter = TemplateFilter() }
                        .disabled(filter.isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var dots: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(TemplateFilter.allColors, id: \.self) { id in
                dot(id)
            }
        }
    }

    private func dot(_ id: String) -> some View {
        let picked = filter.colors.contains(id)
        return Button {
            if picked { filter.colors.remove(id) } else { filter.colors.insert(id) }
        } label: {
            Circle()
                .fill(Color(hex: TemplateFilter.swatches[id] ?? "#9e9e9e"))
                .padding(4)
                .overlay(Circle().stroke(picked ? Theme.accent : Theme.hairline, lineWidth: picked ? 3 : 1))
                .overlay {
                    if picked {
                        // A tick that reads on light and dark dots alike.
                        Image(systemName: "checkmark")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(id == "white" || id == "yellow" ? Color.black : Color.white)
                    }
                }
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TemplateFilter.colorName(id))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private var pagesRow: some View {
        HStack(spacing: 8) {
            toggleChip(tr("Any"), on: filter.multiPage == nil) { filter.multiPage = nil }
            toggleChip(tr("Single page"), on: filter.multiPage == false) {
                filter.multiPage = filter.multiPage == false ? nil : false
            }
            toggleChip(tr("Set", context: "pages"), on: filter.multiPage == true) {
                filter.multiPage = filter.multiPage == true ? nil : true
            }
        }
    }

    private func toggleChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(on ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// The chips under Add's search, as the Android twin's ElementFilterChips:
// Type (a sheet of the kinds to keep, several at once), Animated and Static,
// then a row of colour swatches — twelve, and the brand kit's colours after
// them. Each chip says how many hits it would leave, and a tap changes the
// results at once (ElementSearch.filtered). The filters last while the app
// runs (ElementSearch.sessionFilter).

import SwiftUI

struct ElementFilterChips: View {
    /// The search's hits before any filter.
    let hits: [ElementSearch.Hit]
    let brandColours: [String]
    @Binding var filter: ElementSearch.Filter
    @State private var choosingTypes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    typeChip
                    motionChip(.animated, title: tr("Animated"))
                    motionChip(.still, title: tr("Static"))
                }
            }
            swatchRow
        }
        .sheet(isPresented: $choosingTypes) {
            ElementTypeSheet(hits: hits, filter: $filter)
                .presentationDetents([.medium])
        }
    }

    /// How many hits `filter` would leave.
    private func left(_ by: ElementSearch.Filter) -> Int {
        ElementSearch.filtered(hits, by).count
    }

    private var typeChip: some View {
        let on = !(filter.kinds ?? []).isEmpty
        let title = tr("Type", context: "element kind")
        return chip(title, count: left(filter), on: on) { choosingTypes = true }
            .accessibilityHint(Text("Choose the types of element to show"))
    }

    private func motionChip(_ motion: ElementSearch.Motion, title: String) -> some View {
        let on = filter.motion == motion
        var toggled = filter
        toggled.motion = on ? .any : motion
        return chip(title, count: left(on ? filter : toggled), on: on) { filter = toggled }
    }

    private func chip(_ title: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text(verbatim: "\(count)").monospacedDigit().opacity(0.7)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(on ? Theme.accent : Theme.card, in: Capsule())
            .foregroundStyle(on ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ElementSearch.filterLabel(title, on: on))
        .accessibilityValue(trn("%d result|%d results", count))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The twelve swatches and the brand kit's colours, each once.
    private var swatches: [String] {
        var out: [String] = []
        for hex in ElementSearch.swatches + brandColours {
            let lower = hex.lowercased()
            if Cmyk.rgb(lower) != nil && !out.contains(lower) { out.append(lower) }
        }
        return out
    }

    private var swatchRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(swatches, id: \.self) { hex in swatch(hex) }
            }
            .padding(.vertical, 2)
        }
    }

    private func swatch(_ hex: String) -> some View {
        let on = filter.colour == hex
        var toggled = filter
        toggled.colour = on ? nil : hex
        let shown = left(on ? filter : toggled)
        return Button { filter = toggled } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(on ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ElementSearch.filterLabel(ElementNames.colourName(hex), on: on))
        .accessibilityValue(trn("%d result|%d results", shown))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Type: the kinds of element to keep, several at once, each with how many
/// hits it has under the other filters; none picked keeps them all.
struct ElementTypeSheet: View {
    let hits: [ElementSearch.Hit]
    @Binding var filter: ElementSearch.Filter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ElementSearch.FilterType.allCases) { type in
                    row(type)
                }
            }
            .navigationTitle(tr("Type", context: "element kind"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { filter.kinds = nil }
                        .disabled((filter.kinds ?? []).isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ type: ElementSearch.FilterType) -> some View {
        let picked = filter.kinds ?? []
        let on = !type.kinds.isDisjoint(with: picked)
        var alone = filter
        alone.kinds = type.kinds
        let shown = ElementSearch.filtered(hits, alone).count
        return Button {
            var kinds = picked
            if on { kinds.subtract(type.kinds) } else { kinds.formUnion(type.kinds) }
            filter.kinds = kinds.isEmpty ? nil : kinds
        } label: {
            HStack {
                Text(type.title).foregroundStyle(Theme.ink)
                Spacer()
                Text(verbatim: "\(shown)").monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.accent : Color.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ElementSearch.filterLabel(type.title, on: on))
        .accessibilityValue(trn("%d result|%d results", shown))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

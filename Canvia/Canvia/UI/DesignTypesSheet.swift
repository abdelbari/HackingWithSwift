// Every design type, from Home's "More sizes": the catalogue's forty-odd
// sizes in their categories, a chip row to keep to one, and a search that
// finds a type by its name, its other words or its pixels — "tiktok",
// "resume", "1080x1920". A tap opens the Start sheet on that size. The
// Android twin's DesignTypesSheet.

import SwiftUI

struct DesignTypesSheet: View {
    var onPick: (SizePreset) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    categoryChips
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(shownCategories, id: \.self) { name in
                        Section(name) {
                            ForEach(SizePreset.all.filter { $0.category == name }) { row($0) }
                        }
                    }
                } else {
                    let found = SizePreset.search(query).filter { category == nil || $0.category == category }
                    if found.isEmpty {
                        Text("No design type matches “\(query)”.")
                            .foregroundStyle(.secondary)
                    } else {
                        Section("\(found.count) found") {
                            ForEach(found) { row($0) }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search sizes, like TikTok or A4")
            .navigationTitle("Design types")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var shownCategories: [String] {
        SizePreset.categories.filter { category == nil || $0 == category }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: category == nil) { category = nil }
                ForEach(SizePreset.categories, id: \.self) { name in
                    chip(name, selected: category == name) {
                        category = category == name ? nil : name
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func row(_ preset: SizePreset) -> some View {
        let count = ContentLibrary.templateCounts[preset.id] ?? 0
        return Button {
            onPick(preset)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preset.icon)
                    .frame(width: 28)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.body.weight(.medium))
                    Text("\(preset.dimensions) · \(count) ready-made")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("\(preset.name), \(preset.dimensions.replacingOccurrences(of: " × ", with: " by ")), \(count) ready-made designs")
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
}

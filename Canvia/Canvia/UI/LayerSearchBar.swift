// Under Layers' search box: the kind chips — Text, Photos and videos,
// Shapes and lines, Graphics, Groups, Hidden, Locked — and the scope, This
// page or All pages, beside All and Overlapping. What they pick lasts while
// the app runs (LayerSearch.session) and is never saved with the design.

import SwiftUI

struct LayerSearchBar: View {
    @Binding var query: LayerSearch.Query
    @Binding var filter: LayerRows.Filter

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LayerSearch.KindChip.allCases) { kind in chip(kind) }
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
                scopePicker
                filterPicker
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var scopePicker: some View {
        Picker("Pages", selection: $query.allPages) {
            Text("This page").tag(false)
            Text("All pages").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var filterPicker: some View {
        Picker("Show", selection: $filter) {
            ForEach(LayerRows.Filter.allCases) { choice in
                Text(tr(choice.rawValue)).tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// One kind's chip, filled while it is picked; chips combine with each
    /// other and with Overlapping.
    private func chip(_ kind: LayerSearch.KindChip) -> some View {
        let on = query.kinds.contains(kind)
        return Button {
            if on { query.kinds.remove(kind) } else { query.kinds.insert(kind) }
        } label: {
            Text(kind.title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(on ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ElementSearch.filterLabel(kind.title, on: on))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

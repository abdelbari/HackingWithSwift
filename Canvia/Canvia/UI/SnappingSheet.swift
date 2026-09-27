// The snapping switches, the grid, the margins and the guides, as a sheet.
//
// The overflow menu's Snapping submenu is where they live day to day — one
// tap and back on the canvas. A Menu cannot be opened from code, though, so
// Help's "Show me" opens the same settings here, as the Android twin opens
// its Snapping and guides sheet.

import SwiftUI

struct SnappingSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                snapSection
                gridSection
                marginSection
                guidesSection
            }
            .navigationTitle("Snapping and guides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var snapSection: some View {
        Section {
            Toggle("Snap to elements", isOn: $store.snapping.toElements)
            Toggle("Snap to page", isOn: $store.snapping.toPage)
        } footer: {
            Text("A snap line says what it has lined things up with — the centre of the page, another element, your own guide.")
        }
    }

    private var gridSection: some View {
        Section("Grid") {
            Picker("Grid", selection: $store.snapping.grid) {
                Text("No grid").tag(0.0)
                ForEach(SnapSettings.gridChoices.filter { $0 > 0 }, id: \.self) { step in
                    Text("Every \(Int(step)) px").tag(step)
                }
            }
            Toggle("Show grid", isOn: $store.snapping.showGrid)
                .disabled(!store.snapping.gridEnabled)
        }
    }

    private var marginSection: some View {
        Section("Margins") {
            Picker("Margins", selection: $store.snapping.margin) {
                Text("No margins").tag(0.0)
                ForEach(SnapSettings.marginChoices.filter { $0 > 0 }, id: \.self) { m in
                    Text("\(Int((m * 100).rounded()))% of the short side").tag(m)
                }
            }
            Toggle("Show margins", isOn: $store.snapping.showMargins)
                .disabled(!store.snapping.marginEnabled)
        }
    }

    private var guidesSection: some View {
        Section {
            Button { store.addGuide(vertical: true) } label: {
                Label("Add vertical guide", systemImage: "line.vertical")
            }
            Button { store.addGuide(vertical: false) } label: {
                Label("Add horizontal guide", systemImage: "line.horizontal")
            }
            Button(role: .destructive) { store.clearGuides() } label: {
                Label("Remove all guides", systemImage: "trash")
            }
            .disabled(store.design.guides.isEmpty)
        } header: {
            Text("Guides")
        } footer: {
            Text(store.design.guides.isEmpty
                 ? "No guides on this design."
                 : (store.design.guides.count == 1 ? "1 guide." : "\(store.design.guides.count) guides."))
        }
    }
}

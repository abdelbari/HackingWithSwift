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
    @State private var askingCustomGrid = false

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
        .customGridAlert(isPresented: $askingCustomGrid, store: store)
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
            Self.gridPicker(store: store, askingCustom: $askingCustomGrid)
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
            NavigationLink { AddGuidesView(store: store) } label: {
                Label("Add guides…", systemImage: "rectangle.split.3x1")
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

    /// The Grid picker, the sheet's and the overflow menu's: no grid, the
    /// spacings offered, one set with Custom… when there is one, and
    /// "Custom…", which asks for a spacing rather than picking one.
    static func gridPicker(store: DesignStore, askingCustom: Binding<Bool>) -> some View {
        let custom = SnapSettings.isCustomGrid(store.snapping.grid) ? store.snapping.grid : nil
        return Picker("Grid", selection: Binding(
            get: { store.snapping.grid },
            set: { step in
                if step == Self.customGridTag { askingCustom.wrappedValue = true } else { store.snapping.grid = step }
            })) {
            Text("No grid").tag(0.0)
            ForEach(SnapSettings.gridChoices.filter { $0 > 0 }, id: \.self) { step in
                Text(SnapSettings.gridLabel(step)).tag(step)
            }
            if let custom {
                Text(SnapSettings.gridLabel(custom)).tag(custom)
            }
            Text("Custom…").tag(Self.customGridTag)
        }
    }

    /// The picker's tag for "Custom…": no spacing anyone could set.
    private static let customGridTag = -1.0
}

// MARK: - custom grid

extension View {
    /// Asks for a grid spacing of your own, 2 to 500 px, when `isPresented`.
    func customGridAlert(isPresented: Binding<Bool>, store: DesignStore) -> some View {
        modifier(CustomGridAlert(isPresented: isPresented, store: store))
    }
}

private struct CustomGridAlert: ViewModifier {
    @Binding var isPresented: Bool
    let store: DesignStore
    @State private var typed = ""

    func body(content: Content) -> some View {
        content
            .alert("Custom grid", isPresented: $isPresented) {
                TextField("px", text: $typed)
                    .keyboardType(.decimalPad)
                Button("Set") {
                    if let step = SnapSettings.customGrid(typed) {
                        store.snapping.grid = step
                    } else {
                        store.buzz(.reject)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Grid spacing, \(Int(SnapSettings.customGridRange.lowerBound)) to \(Int(SnapSettings.customGridRange.upperBound)) px.")
            }
            // Starts from the spacing there is, when there is one.
            .onChange(of: isPresented) { _, open in
                guard open else { return }
                let grid = store.snapping.grid
                typed = grid > 0 ? (grid == grid.rounded() ? String(Int(grid)) : String(grid)) : ""
            }
    }
}

// MARK: - add guides

/// Add guides…: columns and grids ready-made, or columns, rows, a gutter
/// and a margin of your own, laid out as guides on this page (see
/// Guides.layout) — added to the guides there, or in their place — as one
/// undo step.
struct AddGuidesView: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var replace = false
    @State private var columns = 3
    @State private var rows = 0
    @State private var gutter = 20
    @State private var margin = 40

    var body: some View {
        Form {
            Section {
                ForEach(Guides.presets) { preset in
                    Button(preset.label) { add(columns: preset.columns, rows: preset.rows, gutter: 0, margin: 0) }
                }
                NavigationLink(Guides.customLabel) { customForm }
            } header: {
                Text("Presets")
            }
            replaceSection
        }
        .navigationTitle("Add guides")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var replaceSection: some View {
        Section {
            Toggle("Replace existing guides", isOn: $replace)
        } footer: {
            Text(store.design.guides.isEmpty
                 ? "No guides on this design yet."
                 : (store.design.guides.count == 1 ? "1 guide on this design." : "\(store.design.guides.count) guides on this design."))
        }
    }

    private var customForm: some View {
        Form {
            Section {
                field("Columns", value: $columns, in: Guides.columnRange, unit: nil)
                field("Rows", value: $rows, in: Guides.rowRange, unit: nil)
                field("Gutter", value: $gutter, in: Guides.gutterRange, unit: "px")
                field("Margin", value: $margin, in: Guides.marginRange, unit: "px")
            } footer: {
                Text("Columns share the page inside the margin, with the gutter between them. No rows adds columns only.")
            }
            replaceSection
            Section {
                Button("Add guides") {
                    add(columns: columns, rows: rows, gutter: Double(gutter), margin: Double(margin))
                }
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("Custom guides")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A number typed or stepped, kept within `range`.
    private func field(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>, unit: String?) -> some View {
        let kept = Binding<Int>(get: { value.wrappedValue },
                                set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) })
        return HStack {
            Text(label)
            Spacer()
            TextField(label, value: kept, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            if let unit { Text(unit).foregroundStyle(.secondary) }
            Stepper(label, value: kept, in: range)
                .labelsHidden()
        }
    }

    private func add(columns: Int, rows: Int, gutter: Double, margin: Double) {
        let before = store.design.guides
        let added = store.addGuideLayout(columns: columns, rows: rows, gutter: gutter, margin: margin, replace: replace)
        if store.design.guides == before {
            store.announce("Those guides are already there", undoable: false)
        } else {
            store.announce(added == 1 ? "Added 1 guide" : "Added \(added) guides")
        }
        dismiss()
    }
}


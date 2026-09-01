// Contextual toolbar: morphs with the selection type, plus a universal
// cluster (position, opacity, lock, duplicate, layer order, delete).

import SwiftUI

struct ContextToolbar: View {
    @Bindable var store: DesignStore
    @Binding var activeSheet: EditorSheet?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                if let el = store.singleSelection {
                    typeControls(el)
                    Divider().frame(height: 26)
                }
                universalControls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.background)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: per-type

    @ViewBuilder
    private func typeControls(_ el: Element) -> some View {
        switch el.type {
        case .text: textControls(el)
        case .shape: shapeControls(el)
        case .image: imageControls(el)
        case .line: lineControls(el)
        case .sticker: EmptyView()
        }
    }

    @ViewBuilder
    private func textControls(_ el: Element) -> some View {
        toolButton("textformat", "Font") { activeSheet = .fonts }
        colorChip(el.color ?? "#1f2430", "Color") { activeSheet = .colorText }

        // Font size stepper
        HStack(spacing: 4) {
            Button { bumpFontSize(-2) } label: { Image(systemName: "minus") }
            Text("\(Int(el.fontSize ?? 42))")
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 34)
            Button { bumpFontSize(2) } label: { Image(systemName: "plus") }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(.systemGray6)))

        toggle("bold", active: (el.fontWeight ?? 400) >= 700) {
            store.updateSelected { $0.fontWeight = ($0.fontWeight ?? 400) >= 700 ? 400 : 700 }
        }
        toggle("italic", active: el.italic == true) {
            store.updateSelected { $0.italic = !($0.italic ?? false) }
        }
        toggle("underline", active: el.underline == true) {
            store.updateSelected { $0.underline = !($0.underline ?? false) }
        }
        toolButton(alignIcon(el.align), "Align") {
            store.updateSelected { e in
                switch e.align ?? "center" {
                case "left": e.align = "center"
                case "center": e.align = "right"
                default: e.align = "left"
                }
            }
        }
        toggle("list.bullet", active: el.listStyle == "bullet") {
            store.updateSelected { $0.listStyle = $0.listStyle == "bullet" ? "none" : "bullet" }
            reconcileTextHeight()
        }
        toolButton("wand.and.stars", "Effects") { activeSheet = .effects }
        toolButton("arrow.up.and.down.text.horizontal", "Spacing") { activeSheet = .spacing }
    }

    @ViewBuilder
    private func shapeControls(_ el: Element) -> some View {
        colorChip(el.fill?.primaryColor ?? "#8b5cf6", "Fill") { activeSheet = .colorFill }
        colorChip(el.stroke ?? "#0d1216", "Border") { activeSheet = .colorStroke }
        if ContentLibrary.shape(el.shapeId).rectLike == true {
            sliderControl("Round", value: el.radius ?? 0, in: 0...(min(el.w, el.h) / 2)) { v in
                store.updateSelectedTransient { $0.radius = v }
            }
        }
    }

    @ViewBuilder
    private func imageControls(_ el: Element) -> some View {
        toolButton("camera.filters", "Filters") { activeSheet = .filters }
        toolButton("crop", "Crop") { activeSheet = .crop }
        sliderControl("Round", value: el.radius ?? 0, in: 0...(min(el.w, el.h) / 2)) { v in
            store.updateSelectedTransient { $0.radius = v }
        }
    }

    @ViewBuilder
    private func lineControls(_ el: Element) -> some View {
        colorChip(el.color ?? "#1f2430", "Color") { activeSheet = .colorLine }
        sliderControl("Weight", value: el.thickness ?? 4, in: 1...30) { v in
            store.updateSelectedTransient {
                $0.thickness = v
                $0.h = max(8, v)
            }
        }
        Menu {
            ForEach(["solid", "dashed", "dotted"], id: \.self) { dash in
                Button(dash.capitalized) { store.updateSelected { $0.dash = dash } }
            }
        } label: {
            Image(systemName: "line.horizontal.3")
        }
        Menu {
            Button("No caps") { store.updateSelected { $0.startCap = "none"; $0.endCap = "none" } }
            Button("Arrow end →") { store.updateSelected { $0.startCap = "none"; $0.endCap = "arrow" } }
            Button("Both arrows ↔") { store.updateSelected { $0.startCap = "arrow"; $0.endCap = "arrow" } }
            Button("Dot ends") { store.updateSelected { $0.startCap = "dot"; $0.endCap = "dot" } }
        } label: {
            Image(systemName: "arrow.left.and.right")
        }
    }

    // MARK: universal

    @ViewBuilder
    private var universalControls: some View {
        toolButton("square.3.layers.3d", "Position") { activeSheet = .position }

        // Opacity
        if let el = store.selectedElements.first {
            sliderControl("Opacity", value: el.opacity, in: 0.02...1) { v in
                store.updateSelectedTransient { $0.opacity = v }
            }
        }

        let anyUnlocked = store.selectedElements.contains { !$0.locked }
        toolButton(anyUnlocked ? "lock.open" : "lock", anyUnlocked ? "Lock" : "Unlock") {
            store.toggleLockSelected()
        }
        toolButton("plus.square.on.square", "Duplicate") { store.duplicateSelected() }
        toolButton("square.2.layers.3d.top.filled", "Forward") { store.reorderSelected(.forward) }
        toolButton("square.2.layers.3d.bottom.filled", "Backward") { store.reorderSelected(.backward) }
        toolButton("trash", "Delete") { store.deleteSelected() }
            .foregroundStyle(.red)
    }

    // MARK: helpers

    private func toolButton(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: system).font(.system(size: 17))
                Text(label).font(.system(size: 9.5))
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ system: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Color(hex: "#f1e8ff") : Color.clear))
                .foregroundStyle(active ? Color(hex: "#7300e6") : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func colorChip(_ hex: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: hex))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.15)))
                    .frame(width: 26, height: 26)
                Text(label).font(.system(size: 9.5))
            }
        }
        .buttonStyle(.plain)
    }

    private func sliderControl(_ label: String, value: Double, in range: ClosedRange<Double>,
                               onChange: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 2) {
            Slider(value: Binding(
                get: { value },
                set: { onChange($0) }
            ), in: range, onEditingChanged: { editing in
                if !editing { store.commit() }
            })
            .frame(width: 110)
            Text(label).font(.system(size: 9.5))
        }
    }

    private func alignIcon(_ align: String?) -> String {
        switch align ?? "center" {
        case "left": return "text.alignleft"
        case "right": return "text.alignright"
        default: return "text.aligncenter"
        }
    }

    private func bumpFontSize(_ delta: Double) {
        store.updateSelected { el in
            el.fontSize = min(500, max(6, (el.fontSize ?? 42) + delta))
        }
        reconcileTextHeight()
    }

    private func reconcileTextHeight() {
        store.beginGesture()
        for i in store.design.pages[store.pageIndex].elements.indices {
            let el = store.design.pages[store.pageIndex].elements[i]
            if el.type == .text && store.selection.contains(el.id) {
                store.design.pages[store.pageIndex].elements[i].h = FontLibrary.measuredHeight(for: el)
            }
        }
        store.commit()
    }
}

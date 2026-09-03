// Contextual toolbar: morphs with the selection type, plus a universal
// cluster (position, opacity, lock, duplicate, layer order, delete).

import SwiftUI

/// `.plain` removes SwiftUI's default press dimming, so every control in this
/// bar acknowledged a tap with nothing at all. This restores that and enforces
/// Apple's 44pt minimum target, which none of the three helpers below met:
/// the toggle was 32x32, the colour chip 26x26, and the tool button had no
/// frame at all — a 17pt glyph over a 9.5pt label, about 32pt tall.
private struct ToolButtonStyle: ButtonStyle {
    var minWidth: Double = Touch.minTarget

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: minWidth, minHeight: Touch.minTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.45 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7),
                       value: configuration.isPressed)
            .sensoryFeedback(trigger: configuration.isPressed) { _, pressed in
                pressed ? .impact(weight: .light) : nil
            }
    }
}

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

    // Grouped into three stacks rather than listed flat: a ViewBuilder block
    // takes at most ten child views, and a flat list of these controls sits
    // exactly on that ceiling — the next control added would fail to build.
    @ViewBuilder
    private func textControls(_ el: Element) -> some View {
        HStack(spacing: 14) {
            toolButton("textformat", "Font") { activeSheet = .fonts }
            colorChip(el.color ?? "#1f2430", "Color") { activeSheet = .colorText }
            fontSizeStepper(el)
        }
        HStack(spacing: 14) {
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
                store.updateSelected {
                    $0.listStyle = $0.listStyle == "bullet" ? "none" : "bullet"
                    $0.h = FontLibrary.measuredHeight(for: $0)
                }
            }
        }
        HStack(spacing: 14) {
            toolButton("wand.and.stars", "Effects") { activeSheet = .effects }
            toolButton("arrow.up.and.down.text.horizontal", "Spacing") { activeSheet = .spacing }
        }
    }

    private func fontSizeStepper(_ el: Element) -> some View {
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
        toolButton("arrow.2.squarepath", "Replace") {
            store.replaceTargetId = el.id
            activeSheet = .insert
        }
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
        .buttonStyle(ToolButtonStyle())
    }

    private func toggle(_ system: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Theme.accentSubtle : Color.clear))
                .foregroundStyle(active ? Theme.accent : Color.primary)
        }
        .buttonStyle(ToolButtonStyle())
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
        .buttonStyle(ToolButtonStyle())
    }

    private func sliderControl(_ label: String, value: Double, in range: ClosedRange<Double>,
                               onChange: @escaping (Double) -> Void) -> some View {
        // A zero-length range makes Slider divide by zero; corner-radius
        // bounds derive from element size, so keep a floor.
        let safe = range.lowerBound < range.upperBound
            ? range : range.lowerBound...(range.lowerBound + 1)
        return VStack(spacing: 2) {
            Slider(value: Binding(
                get: { value },
                set: { onChange($0) }
            ), in: safe, onEditingChanged: { editing in
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
            el.h = FontLibrary.measuredHeight(for: el)
        }
    }
}

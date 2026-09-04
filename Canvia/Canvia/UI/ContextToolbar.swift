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

    @State private var cuttingOut = false
    @State private var cutoutError: String?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let el = store.singleSelection, hasTypeControls(el) {
                        typeControls(el)
                        Divider().frame(height: 24).padding(.horizontal, 6)
                    }
                    universalControls
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            }
            // Fade the trailing edge so it is visible that the row continues.
            // A text selection has eleven controls and about six fit on a
            // 390pt phone, so Effects and Spacing were simply invisible.
            .mask(LinearGradient(
                stops: [.init(color: .black, location: 0),
                        .init(color: .black, location: 0.93),
                        .init(color: .clear, location: 1)],
                startPoint: .leading, endPoint: .trailing))

            // Destructive, so it gets a fixed home rather than a position that
            // depends on how far you happen to have scrolled.
            Divider().frame(height: 24)
            deleteButton
                .padding(.horizontal, 4)
        }
        .background(Theme.chrome)
        .overlay(alignment: .top) { Divider() }
        .alert("Remove background",
               isPresented: Binding(get: { cutoutError != nil },
                                    set: { if !$0 { cutoutError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cutoutError ?? "")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            store.deleteSelected()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "trash").font(Theme.controlGlyph)
                Text("Delete").font(Theme.controlLabel)
            }
            .foregroundStyle(.red)
        }
        .buttonStyle(ToolButtonStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: store.selection)
    }

    /// A sticker selection emits nothing, which would leave a stray leading
    /// divider with no group in front of it.
    private func hasTypeControls(_ el: Element) -> Bool {
        el.type != .sticker
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
            toggle("bold", "Bold", active: (el.fontWeight ?? 400) >= 700) {
                store.updateSelected { $0.fontWeight = ($0.fontWeight ?? 400) >= 700 ? 400 : 700 }
            }
            toggle("italic", "Italic", active: el.italic == true) {
                store.updateSelected { $0.italic = !($0.italic ?? false) }
            }
            toggle("underline", "Underline", active: el.underline == true) {
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
            toggle("list.bullet", "Bulleted list", active: el.listStyle == "bullet") {
                store.updateSelected {
                    $0.listStyle = $0.listStyle == "bullet" ? "none" : "bullet"
                    $0.h = FontLibrary.layoutHeight(for: $0)
                }
            }
        }
        HStack(spacing: 14) {
            toolButton("wand.and.stars", "Effects") { activeSheet = .effects }
            toolButton("arrow.up.and.down.text.horizontal", "Spacing") { activeSheet = .spacing }
            sliderControl("Curve", value: el.curve ?? 0, in: -180...180) { degrees in
                store.updateSelectedTransient { curve(&$0, to: degrees) }
            }
        }
    }

    /// Bend a text element's baseline, and resize its box to the ink.
    ///
    /// Curving makes a line of text shorter and much taller, and nothing else
    /// in the app can work that out — the straight measurement would leave the
    /// arc hanging outside its own selection box. The width only ever grows,
    /// so straightening the text again returns it to the wrap width the user
    /// chose rather than to whatever the widest arc happened to need.
    private func curve(_ el: inout Element, to degrees: Double) {
        let centre = CGPoint(x: el.x + el.w / 2, y: el.y + el.h / 2)
        let straight = abs(degrees) < TextOutliner.straightBelowDegrees
        el.curve = straight ? nil : degrees
        if straight {
            // measuredHeight, not layoutHeight: the curve has just been
            // cleared and this is deliberately the flat measurement.
            el.h = FontLibrary.measuredHeight(for: el)
        } else if let size = TextOutliner.curvedSize(for: el, degrees: degrees) {
            el.w = max(el.w, size.width)
            el.h = max(size.height, el.fontSize ?? 42)
        }
        el.x = centre.x - el.w / 2
        el.y = centre.y - el.h / 2
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
        cutoutButton(el)
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
            // Floor of 0, not 0.02. The old floor bought nothing — 2% is
            // visually indistinguishable from invisible — while making the
            // slider's own readout bottom out at "Opacity 2%", which reads as
            // a bug, and denying a clean fully-transparent value. An element
            // at 0 is still selected, still outlined, and still listed in the
            // Layers sheet, so it cannot be lost.
            sliderControl("Opacity", value: el.opacity, in: 0...1) { v in
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
    }

    // MARK: helpers

    /// Background removal. Kept at the head of the image controls because it
    /// is the reason to reach for this bar at all — everything else here is a
    /// refinement, this one changes the picture.
    private func cutoutButton(_ el: Element) -> some View {
        Button {
            removeBackground(el)
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    // Swapped in place rather than replacing the button, so
                    // the bar does not reflow mid-operation and shift every
                    // other control out from under a waiting finger.
                    Image(systemName: "person.and.background.dotted")
                        .font(Theme.controlGlyph)
                        .opacity(cuttingOut ? 0 : 1)
                    if cuttingOut { ProgressView().controlSize(.small) }
                }
                Text("Cut out").font(Theme.controlLabel)
            }
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(ToolButtonStyle())
        .disabled(cuttingOut)
        .accessibilityLabel("Remove background")
    }

    /// Vision's segmenter, off the main actor: it is fast, but "fast" for a
    /// neural-engine pass is still tens of milliseconds more than a frame.
    private func removeBackground(_ el: Element) {
        guard !cuttingOut else { return }
        cuttingOut = true
        let id = el.id
        let src = el.src
        Task {
            let cut = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
                guard let image = PhotoLibrary.resolve(src) else {
                    return .failure(SubjectMask.Failure.failed)
                }
                do {
                    guard let stored = MediaStore.storeTransparent(try SubjectMask.cutout(image))
                    else { return .failure(SubjectMask.Failure.failed) }
                    return .success(stored)
                } catch {
                    return .failure(error)
                }
            }.value
            cuttingOut = false
            switch cut {
            case .failure(let error):
                cutoutError = error.localizedDescription
            case .success(let newSrc):
                // Committed through the page so it lands in undo as one step,
                // and addressed by id rather than by selection: the cutout
                // finishes asynchronously and the selection may have moved on.
                store.applyToPage { page in
                    if let i = page.elements.firstIndex(where: { $0.id == id }) {
                        page.elements[i].src = newSrc
                    }
                }
            }
        }
    }

    private func toolButton(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: system).font(Theme.controlGlyph)
                Text(label).font(Theme.controlLabel)
            }
        }
        .buttonStyle(ToolButtonStyle())
    }

    private func toggle(_ system: String, _ name: String, active: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Theme.accentSubtle : Color.clear))
                .foregroundStyle(active ? Theme.accent : Color.primary)
        }
        .buttonStyle(ToolButtonStyle())
        // The only icon-only control in the bar; the rest carry a visible
        // text label that VoiceOver can already read.
        .accessibilityLabel(name)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private func colorChip(_ hex: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: hex))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.15)))
                    .frame(width: 26, height: 26)
                Text(label).font(Theme.controlLabel)
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
            Text(readout(label, value))
                .font(Theme.controlLabel)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    /// "Round" tells you nothing; "Round 24" is a control.
    private func readout(_ label: String, _ value: Double) -> String {
        label == "Opacity"
            ? "\(label) \(Int((value * 100).rounded()))%"
            : "\(label) \(Int(value.rounded()))"
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
            el.h = FontLibrary.layoutHeight(for: el)
        }
    }
}

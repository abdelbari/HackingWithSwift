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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: minWidth, minHeight: Touch.minTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.45 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7),
                       value: configuration.isPressed)
            .sensoryFeedback(trigger: configuration.isPressed) { _, pressed in
                pressed ? .impact(weight: .light) : nil
            }
    }
}

struct ContextToolbar: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @State private var editingAlt = false
    @State private var altDraft = ""
    @State private var namingStyle = false
    @State private var styleName = ""
    @State private var styleVersion = 0
    @Bindable var store: DesignStore
    @Binding var activeSheet: EditorSheet?

    @State private var cuttingOut = false
    @State private var dictationBase = ""
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
            toggle("text.justify.leading", "Vertical", active: el.vertical == true) {
                store.updateSelected { e in
                    e.vertical = e.vertical == true ? nil : true
                    // A column wants height; give a one-line box a few rows.
                    if e.vertical == true, e.h < (e.fontSize ?? 42) * 4 { e.h = (e.fontSize ?? 42) * 4 }
                }
            }
            toolButton(alignIcon(el.align), "Align") {
                store.updateSelected { e in
                    switch e.align ?? "center" {
                    case "left": e.align = "center"
                    case "center": e.align = "right"
                    case "right": e.align = "justify"
                    default: e.align = "left"
                    }
                }
            }
            listMenu(el)
            toolButton("decrease.indent", "Outdent") { indent(el, by: -1) }
                .disabled(FontLibrary.indentLevel(of: el) == 0)
            toolButton("increase.indent", "Indent") { indent(el, by: 1) }
                .disabled(FontLibrary.indentLevel(of: el) >= FontLibrary.maxIndent)
        }
        HStack(spacing: 14) {
            stylesMenu(el)
            toolButton("wand.and.stars", "Effects") { activeSheet = .effects }
            toolButton("arrow.up.and.down.text.horizontal", "Spacing") { activeSheet = .spacing }
            pathMenu(el)
            if Dictation.isAvailable { dictateButton(el) }
            sliderControl("Curve", value: el.curve ?? 0, in: -180...180) { degrees in
                store.updateSelectedTransient { curve(&$0, to: degrees) }
            }
        }
    }

    /// Speak, and the words append to the selected text as they arrive;
    /// tap again to stop, which is when the change is recorded.
    private func dictateButton(_ el: Element) -> some View {
        let listening = Dictation.shared.isListening
        return toolButton(listening ? "mic.fill" : "mic", listening ? "Stop" : "Dictate") {
            if listening {
                Dictation.shared.stop()
                store.commit()
                return
            }
            dictationBase = el.text ?? ""
            let base = dictationBase
            Dictation.shared.start { spoken, isFinal in
                Task { @MainActor in
                    store.updateSelectedTransient { e in
                        e.text = Dictation.merge(base, spoken)
                        e.h = FontLibrary.layoutHeight(for: e)
                    }
                    if isFinal { store.commit() }
                }
            }
        }
        .alert("Dictation", isPresented: Binding(
            get: { Dictation.shared.error != nil },
            set: { if !$0 { Dictation.shared.error = nil } })) {
            Button("OK") { Dictation.shared.error = nil }
        } message: {
            Text(Dictation.shared.error ?? "")
        }
    }

    /// Text along a path: a wave, an arch, a circle — set on the element as
    /// path data in its box, so the box's shape is the path's.
    private func pathMenu(_ el: Element) -> some View {
        Menu {
            Button {
                store.updateSelected { $0.textPath = nil }
            } label: { Label("Straight", systemImage: el.textPath == nil ? "checkmark" : "circle") }
            Divider()
            ForEach(TextPaths.presets) { preset in
                Button {
                    store.updateSelected { e in
                        e.textPath = preset.data
                        e.curve = nil
                        // A path wants room above and below its line.
                        if e.h < (e.fontSize ?? 42) * 3 { e.h = (e.fontSize ?? 42) * 3 }
                    }
                } label: {
                    Label(preset.name, systemImage: el.textPath == preset.data ? "checkmark" : "circle")
                }
            }
        } label: {
            toolLabel("point.topleft.down.to.point.bottomright.curvepath", "Path", active: el.textPath != nil)
        }
    }

    /// An entrance for the selection, and a way to see it.
    private func animateMenu(_ el: Element) -> some View {
        Menu {
            Button { store.animateSelected(nil) } label: {
                Label("No animation", systemImage: el.animation == nil ? "checkmark" : "circle")
            }
            Divider()
            ForEach(ElementAnimation.kinds.filter { !ElementAnimation.textKinds.contains($0) && !ElementAnimation.loopKinds.contains($0) }, id: \.self) { kind in
                Button { store.animateSelected(kind); store.playPreview() } label: {
                    Label(ElementAnimation.name(kind), systemImage: el.animation?.kind == kind ? "checkmark" : "circle")
                }
            }
            Divider()
            ForEach(ElementAnimation.kinds.filter { ElementAnimation.loopKinds.contains($0) }, id: \.self) { kind in
                Button { store.animateSelected(kind); store.playPreview() } label: {
                    Label(ElementAnimation.name(kind), systemImage: el.animation?.kind == kind ? "checkmark" : "circle")
                }
            }
            if store.selectedElements.contains(where: { $0.type == .text }) {
                Divider()
                ForEach(ElementAnimation.kinds.filter { ElementAnimation.textKinds.contains($0) }, id: \.self) { kind in
                    Button { store.animateSelected(kind); store.playPreview() } label: {
                        Label(ElementAnimation.name(kind), systemImage: el.animation?.kind == kind ? "checkmark" : "circle")
                    }
                }
            }
            Divider()
            Button { store.playPreview() } label: { Label("Play this page", systemImage: "play") }
                .disabled(!store.pageIsAnimated)
        } label: {
            toolLabel("sparkles.rectangle.stack", "Animate", active: el.animation != nil)
        }
    }

    private func blendMenu(_ el: Element) -> some View {
        Menu {
            Picker("Blend", selection: Binding(
                get: { BlendModes.mode(el.blendMode).id },
                set: { id in
                    store.updateSelected { $0.blendMode = BlendModes.isNormal(id) ? nil : id }
                })) {
                ForEach(BlendModes.all) { Text($0.name).tag($0.id) }
            }
        } label: {
            toolLabel("circle.lefthalf.filled", "Blend", active: !BlendModes.isNormal(el.blendMode))
        }
    }

    /// Live Text: the words in the picture become text elements over it.
    private func readText(_ el: Element) {
        guard let image = PhotoLibrary.resolve(el.src) else { return }
        let frame = el.frame
        Task.detached(priority: .userInitiated) {
            let lines = TextRecognizer.lines(in: image)
            await MainActor.run {
                let elements = TextRecognizer.elements(from: lines, in: frame)
                guard !elements.isEmpty else { return }
                store.applyToPage { $0.elements.append(contentsOf: elements) }
                store.selection = Set(elements.map(\.id))
            }
        }
    }

    /// The picture's ink — its opaque part, or its dark part — becomes a
    /// path shape over the same spot, in the ink's own colour.
    private func traceImage(_ el: Element) {
        guard let image = PhotoLibrary.resolve(el.src) else { return }
        let frame = el.frame
        Task.detached(priority: .userInitiated) {
            let traced = Tracer.trace(image)
            await MainActor.run {
                guard let traced else { return }
                let w = (frame.width * traced.bounds.width).rounded(), h = (frame.height * traced.bounds.height).rounded()
                var shape = Element.shape("traced", w: max(w, 4), h: max(h, 4))
                shape.x = (frame.minX + frame.width * traced.bounds.minX).rounded()
                shape.y = (frame.minY + frame.height * traced.bounds.minY).rounded()
                shape.pathData = traced.pathData
                shape.fill = .solid(traced.color)
                store.add(shape, centered: false)
                store.announce("Traced — a shape in the picture's colour")
            }
        }
    }

    /// A code in the picture becomes a clean, editable code element beside it.
    private func readCode(_ el: Element) {
        guard let image = PhotoLibrary.resolve(el.src) else { return }
        let frame = el.frame
        Task.detached(priority: .userInitiated) {
            let payload = TextRecognizer.codePayload(in: image)
            await MainActor.run {
                guard let payload else { return }
                let side = min(frame.width, frame.height) * 0.6
                var code = Element.image(CodeGenerator.source(for: payload), w: side.rounded(), h: side.rounded())
                code.x = (frame.midX - side / 2).rounded(); code.y = (frame.midY - side / 2).rounded()
                store.add(code, centered: false)
            }
        }
    }

    /// Saved, linked text styles: apply one, save the current look as one,
    /// or push this element's look back into the style it follows.
    private func stylesMenu(_ el: Element) -> some View {
        let styles = TextStyles.load()
        let followed = styles.first { $0.id == el.textStyleId }
        return Menu {
            if styles.isEmpty {
                Text("No saved styles yet")
            }
            ForEach(styles) { style in
                Button {
                    store.applyTextStyle(style)
                    styleVersion += 1
                } label: {
                    Label(style.name, systemImage: style.id == el.textStyleId ? "checkmark" : "textformat")
                }
            }
            Divider()
            Button {
                styleName = ""
                namingStyle = true
            } label: { Label("Save this look as a style…", systemImage: "plus") }
            if let followed {
                Button {
                    store.updateTextStyle(followed.id, from: el)
                    styleVersion += 1
                } label: { Label("Update “\(followed.name)” from this text", systemImage: "arrow.triangle.2.circlepath") }
                Button(role: .destructive) {
                    TextStyles.remove(followed.id)
                    styleVersion += 1
                } label: { Label("Delete “\(followed.name)”", systemImage: "trash") }
            }
        } label: {
            toolLabel("character.textbox", "Styles", active: followed != nil)
        }
        .id(styleVersion)
        .alert("Name this style", isPresented: $namingStyle) {
            TextField("Heading, Caption, Price…", text: $styleName)
            Button("Save") {
                let name = styleName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let saved = TextStyles.add(named: name, from: el)
                store.updateSelected { $0.textStyleId = saved.id }
                styleVersion += 1
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Bullets, numbers or letters. A menu rather than a toggle because
    /// three list kinds through one button would cycle, and nobody counts
    /// taps to reach "letters".
    private func listMenu(_ el: Element) -> some View {
        Menu {
            Picker("List", selection: Binding(
                get: { el.listStyle ?? "none" },
                set: { style in
                    store.updateSelected {
                        $0.listStyle = style == "none" ? nil : style
                        $0.h = FontLibrary.layoutHeight(for: $0)
                    }
                })) {
                Label("No list", systemImage: "text.alignleft").tag("none")
                Label("Bullets", systemImage: "list.bullet").tag("bullet")
                Label("Numbers", systemImage: "list.number").tag("number")
                Label("Letters", systemImage: "character").tag("letter")
            }
        } label: {
            let icon = el.listStyle == "number" ? "list.number"
                : el.listStyle == "letter" ? "character" : "list.bullet"
            toolLabel(icon, "List", active: FontLibrary.isList(el))
        }
    }

    private func indent(_ el: Element, by delta: Int) {
        store.updateSelected {
            $0.indent = min(FontLibrary.maxIndent, max(0, FontLibrary.indentLevel(of: $0) + delta))
            if $0.indent == 0 { $0.indent = nil }
            $0.h = FontLibrary.layoutHeight(for: $0)
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
        if abs(degrees) >= TextOutliner.straightBelowDegrees { el.textPath = nil }
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
        if el.fill?.kind == "none" {
            // A drawn stroke or an outline: its width is what there is to set.
            sliderControl("Width", value: el.strokeWidth ?? 4, in: 1...40) { v in
                store.updateSelectedTransient { $0.strokeWidth = v }
            }
        }
        if Freehand.isStroke(el) {
            toolButton("text.viewfinder", "To text") { store.strokesToText() }
        }
        if ContentLibrary.shape(el.shapeId).rectLike == true && el.pathData == nil {
            sliderControl("Round", value: el.radius ?? 0, in: 0...(min(el.w, el.h) / 2)) { v in
                store.updateSelectedTransient { $0.radius = v; $0.corners = nil }
            }
            cornersMenu(el)
        }
    }

    /// Which corners the rounding applies to. The slider sets how much;
    /// this sets where, as the patterns people actually use.
    private func cornersMenu(_ el: Element) -> some View {
        let r = el.radius ?? 0
        let patterns: [(String, [Double])] = [
            ("All corners", [r, r, r, r]), ("Top only", [r, r, 0, 0]), ("Bottom only", [0, 0, r, r]),
            ("Left only", [r, 0, 0, r]), ("Right only", [0, r, r, 0]), ("Opposite corners", [r, 0, r, 0]),
        ]
        return Menu {
            ForEach(patterns, id: \.0) { name, radii in
                Button(name) {
                    store.updateSelected { e in
                        e.corners = name == "All corners" ? nil : radii
                        if e.radius == nil || e.radius == 0 { e.radius = min(e.w, e.h) * 0.2 }
                        if e.corners != nil {
                            let rr = e.radius ?? 0
                            e.corners = radii.map { $0 > 0 ? rr : 0 }
                        }
                    }
                }
            }
        } label: {
            toolLabel("rectangle.tophalf.inset.filled", "Corners", active: el.corners != nil)
        }
        .disabled(r <= 0 && el.corners == nil)
    }

    @ViewBuilder
    private func imageControls(_ el: Element) -> some View {
        cutoutButton(el)
        toolButton("square.on.circle", "Frame") { activeSheet = .frame }
        toolButton("camera.filters", "Filters") { activeSheet = .filters }
        toolButton("crop", "Crop") { activeSheet = .crop }
        if VideoStore.isVideo(el.src) {
            // A clip: play the page to see it move; stills come from its poster.
            toolButton("play.circle", "Play") { store.playPreview() }
        } else {
            toolButton("eraser", "Erase") { store.beginErasing(el.id) }
        }
        Menu {
            Button {
                readText(el)
            } label: { Label("Text in this picture → text elements", systemImage: "text.viewfinder") }
            Button {
                readCode(el)
            } label: { Label("QR code in this picture → code element", systemImage: "qrcode.viewfinder") }
            Button {
                traceImage(el)
            } label: { Label("Trace to a vector shape", systemImage: "scribble.variable") }
        } label: {
            toolLabel("doc.text.magnifyingglass", "Read")
        }
        toolButton("text.below.photo", "Alt text") {
            altDraft = el.altText ?? ""
            editingAlt = true
        }
        .alert("Describe this picture", isPresented: $editingAlt) {
            TextField("What it shows", text: $altDraft)
            Button("Suggest") {
                if let ui = PhotoLibrary.resolve(el.src), let draft = AltText.describe(ui) {
                    altDraft = draft
                }
                editingAlt = true
            }
            Button("Save") {
                let text = altDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                store.updateSelected { $0.altText = text.isEmpty ? nil : text }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Read by VoiceOver and written into SVG exports. Suggest asks the on-device classifier for a first draft.")
        }
        toolButton("arrow.2.squarepath", "Replace") {
            store.replaceTargetId = el.id
            activeSheet = .insert
        }
        // Hidden behind a frame: a corner radius on a star means nothing, and
        // a slider whose range is derived from the box looks broken when the
        // box is not what is being drawn.
        if el.maskShapeId == nil {
            sliderControl("Round", value: el.radius ?? 0, in: 0...(min(el.w, el.h) / 2)) { v in
                store.updateSelectedTransient { $0.radius = v }
            }
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
        toolButton("shadow", "Shadow") { activeSheet = .shadow }
        if let el = store.selectedElements.first { blendMenu(el); animateMenu(el) }

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
        if store.selection.count == 2 {
            toolButton("arrow.right", "Connect") { store.connectSelected() }
        }
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

    /// The face of a toolButton without the button, for a Menu label.
    private func toolLabel(_ system: String, _ label: String, active: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: system).font(Theme.controlGlyph)
            Text(label).font(Theme.controlLabel)
        }
        .foregroundStyle(active ? Theme.accent : Color.primary)
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
                // Differentiate Without Colour: "on" is also a bar under
                // the glyph, not only a tint.
                .overlay(alignment: .bottom) {
                    if active && differentiate {
                        Capsule().fill(Theme.accent).frame(width: 16, height: 2).padding(.bottom, 3)
                    }
                }
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
        case "justify": return "text.justify"
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

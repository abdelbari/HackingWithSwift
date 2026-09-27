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
            .feel(trigger: configuration.isPressed) { _, pressed in
                pressed ? .impact(weight: .light) : nil
            }
    }
}

struct ContextToolbar: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @State private var editingAlt = false
    @State private var editingCode = false
    @State private var altDraft = ""
    @State private var editingLink = false
    @State private var linkDraft = ""
    @State private var namingStyle = false
    @State private var styleName = ""
    @State private var styleVersion = 0
    @Bindable var store: DesignStore
    @Binding var activeSheet: EditorSheet?

    /// The border as a drag of its slider began, so going back to None puts
    /// back what was there.
    private struct BorderBefore {
        var stroke: String?
        var width: Double?
    }
    @State private var borderBefore: BorderBefore?
    /// Which corners round, read as a Round drag began and held through it
    /// (the outer nil: no drag under way).
    @State private var heldCorners: CornerPatterns.Pattern??

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
        // Its alerts type; the editor's plain Delete key must leave them be.
        .onChange(of: editingAlt || editingLink || namingStyle) { _, open in
            store.textFieldOpen = open
        }
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
        .feel(.impact(weight: .medium), trigger: store.selection)
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
        case .image:
            // A locked photo is kept as it is: one line says how to change
            // that, in place of tools that could only do nothing. The Lock
            // switch among the universal controls stays.
            if el.locked { lockedPhotoNote } else { imageControls(el) }
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
            colorChip(el.color ?? "#1f2430", "Colour") { activeSheet = .colorText }
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
        let size = image.size
        Task.detached(priority: .userInitiated) {
            let traced = Tracer.trace(image)
            await MainActor.run {
                guard let traced else {
                    store.buzz(.reject)
                    store.announce("Nothing in the picture to trace", undoable: false)
                    return
                }
                store.add(Tracer.shape(traced, over: el, imageSize: size), centered: false)
                store.buzz(.confirm)
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
            let fits = payload.map { CodeGenerator.modules(for: $0) != nil } ?? false
            await MainActor.run {
                guard let payload else {
                    store.buzz(.reject)
                    store.announce("No code found in this picture", undoable: false)
                    return
                }
                // A code read from a print can hold more than a code drawn
                // here can: refused, rather than a blank code on the page.
                guard fits else {
                    store.buzz(.reject)
                    store.announce("That code holds more than a QR code can", undoable: false)
                    return
                }
                let side = min(frame.width, frame.height) * 0.6
                var code = Element.image(CodeGenerator.source(for: payload), w: side.rounded(), h: side.rounded())
                code.x = (frame.midX - side / 2).rounded(); code.y = (frame.midY - side / 2).rounded()
                store.add(code, centered: false)
                store.buzz(.confirm)
                store.announce("Read the code — here it is, clean")
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
        if Freehand.isStroke(el) {
            // A drawing has one colour, its ink. A Fill chip showed a colour
            // it does not have, and picking one filled the scribble in and
            // stopped it being a stroke — as the Android twin, one slot.
            colorChip(el.stroke ?? "#0d1216", "Colour") { activeSheet = .colorStroke }
        } else {
            colorChip(el.fill?.primaryColor ?? "#8b5cf6", "Fill",
                      spoken: FillChoices.spokenFill(el.fill)) { activeSheet = .colorFill }
            colorChip(el.stroke ?? "#0d1216", "Border") { activeSheet = .colorStroke }
        }
        if el.fill?.kind == "none" {
            // A drawn stroke or an outline: its width is what there is to set.
            sliderControl("Width", value: el.strokeWidth ?? 4, in: 1...40) { v in
                store.updateSelectedTransient { $0.strokeWidth = v }
            }
        } else if !Freehand.isStroke(el) {
            borderSlider(el)
        }
        if Freehand.isStroke(el) {
            toolButton("text.viewfinder", "To text") { store.strokesToText() }
        }
        if ContentLibrary.shape(el.shapeId).rectLike == true && el.pathData == nil {
            // Which corners round is read once, as the drag starts, and kept
            // through it: a Top only rounding stays top only, and a drag
            // through zero does not lose it — as on the Android twin.
            sliderControl("Round", value: el.radius ?? 0, in: 0...(min(el.w, el.h) / 2),
                          onEditing: { editing in
                              heldCorners = editing ? .some(CornerPatterns.pattern(of: el)) : nil
                          }) { v in
                let pattern = heldCorners ?? CornerPatterns.pattern(of: el)
                store.updateSelectedTransient { CornerPatterns.setRadius(v, keeping: pattern, on: &$0) }
            }
            cornersMenu(el)
        }
    }

    /// How wide a filled shape's border is — down to None, which takes it
    /// off. The Border chip could colour one but never remove it, nor say
    /// how thick it was. A whole drag is one Undo, and one that tries a
    /// border and comes back to None leaves the shape as it was. The Android
    /// twin's Border slider, to the same 40 and the same default ink.
    private func borderSlider(_ el: Element) -> some View {
        let width = el.strokeWidth ?? 0
        let ceiling = max(40, width)
        return VStack(spacing: 2) {
            Slider(value: Binding(get: { width }, set: { setBorder($0, on: el) }),
                   in: 0...ceiling,
                   onEditingChanged: { editing in
                       if editing {
                           borderBefore = BorderBefore(stroke: el.stroke, width: el.strokeWidth)
                       } else {
                           store.commit()
                           borderBefore = nil
                       }
                   })
            .frame(width: 110)
            .accessibilityLabel("Border")
            .accessibilityValue(width < 0.5 ? "None" : "\(Int(width.rounded()))")
            Text(width < 0.5 ? "Border None" : "Border \(Int(width.rounded()))")
                .font(Theme.controlLabel)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private func setBorder(_ v: Double, on el: Element) {
        let before = borderBefore ?? BorderBefore(stroke: el.stroke, width: el.strokeWidth)
        store.updateSelectedTransient { e in
            guard e.type == .shape, !Freehand.isStroke(e) else { return }
            if v < 0.5 {
                // None: a border that was there goes to 0; one that was not
                // stays as it was, colour and all.
                e.strokeWidth = (before.width ?? 0) > 0 ? 0 : before.width
                e.stroke = before.stroke
            } else {
                e.strokeWidth = v
                if e.stroke == nil { e.stroke = "#0d1216" }
            }
        }
    }

    /// Which corners the rounding applies to. The slider sets how much;
    /// this sets where, as the patterns people actually use — the current
    /// one ticked, and any of them from square, at a fifth of the shorter
    /// side.
    private func cornersMenu(_ el: Element) -> some View {
        let current = CornerPatterns.pattern(of: el)
        return Menu {
            ForEach(CornerPatterns.choices, id: \.name) { pattern in
                Button {
                    guard pattern != current else { return }
                    store.updateSelected { CornerPatterns.apply(pattern, to: &$0) }
                    store.buzz(.tick)
                } label: {
                    if pattern == current {
                        Label(pattern.name, systemImage: "checkmark")
                    } else {
                        Text(pattern.name)
                    }
                }
            }
        } label: {
            toolLabel("rectangle.tophalf.inset.filled", "Corners", active: el.corners != nil)
        }
        .accessibilityLabel("Corners")
        .accessibilityValue(current?.name ?? "Square")
    }

    private var lockedPhotoNote: some View {
        Label("This photo is locked. Tap Unlock to edit it.", systemImage: "lock")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 220, alignment: .leading)
            .frame(minHeight: Touch.minTarget)
    }

    @ViewBuilder
    private func imageControls(_ el: Element) -> some View {
        cutoutButton(el)
        toolButton("square.on.circle", "Frame") { activeSheet = .frame }
        toolButton("camera.filters", "Filters") { activeSheet = .filters }
        // Crop mode, on the canvas: the picture dragged, pinched and trimmed
        // where it sits. The sheet, for straightening, fit and the drift, is
        // a tap away in crop mode's bar.
        toolButton("crop", "Crop") { store.startCrop(el.id) }
        if VideoStore.isVideo(el.src) {
            // A clip: play the page to see it move; stills come from its poster.
            toolButton("play.circle", "Play") { store.playPreview() }
        } else if let payload = CodeGenerator.payload(from: el.src ?? "") {
            // A code's words, changed where it sits — erasing part of a code
            // only stops it scanning, so that is not offered.
            toolButton("qrcode", "Edit code") { editingCode = true }
                .sheet(isPresented: $editingCode) {
                    QRCodeSheet(store: store, id: el.id, payload: payload)
                }
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
        colorChip(el.color ?? "#1f2430", "Colour") { activeSheet = .colorLine }
        // To 60, as on the Android twin, and further when a line already is,
        // so it is shown as it is and not snapped thinner on first touch.
        sliderControl("Weight", value: el.thickness ?? 4, in: 1...max(60, el.thickness ?? 4)) { v in
            store.updateSelectedTransient {
                $0.thickness = v
                $0.h = max(8, v)
            }
        }
        dashMenu(el)
        // Each end on its own — none, an arrow or a dot, nine ways — as the
        // Android twin sets them, with the old pairs kept as quick picks.
        Menu {
            Picker("Start", selection: capBinding(el, start: true)) {
                ForEach(Self.lineEnds, id: \.key) { end in Text(end.name).tag(end.key) }
            }
            .pickerStyle(.menu)
            Picker("End", selection: capBinding(el, start: false)) {
                ForEach(Self.lineEnds, id: \.key) { end in Text(end.name).tag(end.key) }
            }
            .pickerStyle(.menu)
            Section("Both ends") {
                Button("No caps") { setEnds("none", "none") }
                Button("Arrow end →") { setEnds("none", "arrow") }
                Button("Both arrows ↔") { setEnds("arrow", "arrow") }
                Button("Dot ends") { setEnds("dot", "dot") }
            }
        } label: {
            toolLabel("arrow.left.and.right", "Ends")
        }
        .accessibilityLabel("Line ends")
    }

    /// Solid, dashed or dotted: captioned like the rest of the bar, the
    /// current one ticked, and choosing it again records nothing.
    private func dashMenu(_ el: Element) -> some View {
        let current = Self.dashStyle(el.dash)
        return Menu {
            ForEach(Self.dashStyles, id: \.self) { dash in
                Button {
                    guard dash != current else { return }
                    store.updateSelected { $0.dash = dash }
                    store.buzz(.tick)
                } label: {
                    if dash == current {
                        Label(dash.capitalized, systemImage: "checkmark")
                    } else {
                        Text(dash.capitalized)
                    }
                }
            }
        } label: {
            toolLabel("line.3.horizontal.decrease", "Dash", active: current != "solid")
        }
        .accessibilityLabel("Dash")
        .accessibilityValue(current.capitalized)
    }

    static let dashStyles = ["solid", "dashed", "dotted"]

    /// A line's dash as one of those; none, or anything else, is solid.
    static func dashStyle(_ dash: String?) -> String {
        dashStyles.contains(dash ?? "") ? dash ?? "solid" : "solid"
    }

    /// Both ends at once, and nothing recorded when they already are.
    private func setEnds(_ start: String, _ end: String) {
        let lines = store.selectedElements.filter { $0.type == .line && !$0.locked }
        guard lines.contains(where: { Self.lineEnd($0.startCap) != start || Self.lineEnd($0.endCap) != end })
        else { return }
        store.updateSelected { e in
            guard e.type == .line else { return }
            e.startCap = start
            e.endCap = end
        }
        store.buzz(.tick)
    }

    /// The ends a line can have, as both phones write them.
    static let lineEnds: [(key: String, name: String)] = [("none", "None"), ("arrow", "Arrow"), ("dot", "Dot")]

    /// A line's end as one of those keys; anything else reads as none.
    static func lineEnd(_ cap: String?) -> String {
        lineEnds.contains { $0.key == cap } ? cap ?? "none" : "none"
    }

    /// One end of the selected line, changed on its own — and nothing
    /// recorded when it is already that.
    private func capBinding(_ el: Element, start: Bool) -> Binding<String> {
        Binding(get: { Self.lineEnd(start ? el.startCap : el.endCap) },
                set: { key in
                    let lines = store.selectedElements.filter { $0.type == .line && !$0.locked }
                    guard lines.contains(where: { Self.lineEnd(start ? $0.startCap : $0.endCap) != key }) else { return }
                    store.updateSelected { e in
                        guard e.type == .line else { return }
                        if start { e.startCap = key } else { e.endCap = key }
                    }
                    store.buzz(.tick)
                })
    }

    // MARK: universal

    @ViewBuilder
    private var universalControls: some View {
        // Several things selected — a sticky group, a band's worth — recolour
        // together, each its own way: text, lines, shapes and drawn strokes.
        if store.selection.count > 1 && store.selectionTakesColour {
            multiColourChip
        }
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
        if let el = store.singleSelection, !el.locked { linkButton(el) }
        toolButton("plus.square.on.square", "Duplicate") { store.duplicateSelected() }
        if store.selection.count == 2 {
            toolButton("arrow.right", "Connect") { store.connectSelected() }
        }
        Group {
            toolButton("square.2.layers.3d.top.filled", "Forward") { store.reorderSelected(.forward) }
            toolButton("square.2.layers.3d.bottom.filled", "Backward") { store.reorderSelected(.backward) }
        }
    }

    /// A colour chip with no one colour in it, since the selection has many.
    private var multiColourChip: some View {
        Button { activeSheet = .colorSelection } label: {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.15)))
                    .frame(width: 26, height: 26)
                Text("Colour").font(Theme.controlLabel)
            }
        }
        .buttonStyle(ToolButtonStyle())
        .accessibilityLabel("Colour of everything selected")
    }

    /// A web address, email or phone number on the element: clickable in the
    /// PDF and SVG, and opened by a tap in the presenter. Typed as people
    /// type them, and read as the Android twin reads them (see Links).
    private func linkButton(_ el: Element) -> some View {
        let linked = el.link?.isEmpty == false
        return Button {
            // The link as stored, scheme and all. Its shortened label read
            // back through `normalized` came out a different link — http
            // made https, an address's trailing slash lost — or none at all,
            // so saving an unchanged link could rewrite it or refuse it.
            linkDraft = el.link ?? ""
            editingLink = true
        } label: {
            toolLabel("link", linked ? "Linked" : "Link", active: linked)
        }
        .buttonStyle(ToolButtonStyle())
        .alert(linked ? "Edit link" : "Link", isPresented: $editingLink) {
            TextField("canvia.app", text: $linkDraft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            // Save is off while what is typed reads as no link, as the
            // Android twin's Done is, and the message below says why: an
            // alert cannot ask again from its own button, so the typing was
            // being dropped without a word.
            Button("Save") { saveLink() }
                .disabled(linkUnreadable)
            if linked {
                Button("Remove", role: .destructive) {
                    store.updateSelected { $0.link = nil }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(linkUnreadable
                 ? "That doesn't read as a link. Try a web address like canvia.app, an email address or a phone number."
                 : "A web address, email or phone number. Clickable in a PDF, and opened by a tap in Present.")
        }
    }

    /// Whether something is typed that does not read as a link. Nothing at
    /// all is fine: saving it takes the link off.
    private var linkUnreadable: Bool {
        let draft = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !draft.isEmpty && Links.normalized(draft) == nil
    }

    /// Saves what was typed as a link, or clears it when nothing was. Save
    /// is off for anything else, so there is nothing else to handle.
    private func saveLink() {
        let draft = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.isEmpty {
            store.updateSelected { $0.link = nil }
        } else if let url = Links.normalized(draft) {
            store.updateSelected { $0.link = url }
        }
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
        guard !el.locked else {
            store.buzz(.reject)
            store.announce("This photo is locked. Tap Unlock to edit it.", undoable: false)
            return
        }
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
                // Locked while the cutout ran: kept as it is.
                if store.element(id)?.locked == true {
                    store.buzz(.reject)
                    store.announce("This photo is locked. Tap Unlock to edit it.", undoable: false)
                    return
                }
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

    private func colorChip(_ hex: String, _ label: String, spoken: String? = nil,
                           action: @escaping () -> Void) -> some View {
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
        // "Fill, dark blue": what it is now, in words — or "photo", "red
        // pattern", "no fill" when it is not one colour.
        .accessibilityValue(spoken ?? ElementNames.colourName(hex))
    }

    private func sliderControl(_ label: String, value: Double, in range: ClosedRange<Double>,
                               onEditing: ((Bool) -> Void)? = nil,
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
                onEditing?(editing)
                if !editing { store.commit() }
            })
            .frame(width: 110)
            // Named, with the number shown beside it, so VoiceOver says
            // "Round, 24" rather than an unnamed percentage.
            .accessibilityLabel(label)
            .accessibilityValue(Self.readoutValue(label, value))
            Text(readout(label, value))
                .font(Theme.controlLabel)
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityHidden(true)
        }
    }

    /// "Round" tells you nothing; "Round 24" is a control.
    private func readout(_ label: String, _ value: Double) -> String {
        "\(label) \(Self.readoutValue(label, value))"
    }

    /// The number a slider shows: a percentage for opacity, else whole.
    static func readoutValue(_ label: String, _ value: Double) -> String {
        label == "Opacity" ? "\(Int((value * 100).rounded()))%" : "\(Int(value.rounded()))"
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

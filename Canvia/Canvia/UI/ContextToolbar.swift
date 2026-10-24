// Contextual toolbar: morphs with the selection type, plus a universal
// cluster (position, opacity, lock, duplicate, layer order, delete).

import SwiftUI
import PhotosUI

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
    @State private var showingStyles = false
    /// The size control's number was tapped: a size to type or pick.
    @State private var enteringSize = false
    /// A photo picked for the selected text's letters (PhotoInLetters).
    @State private var letterPhoto: PhotosPickerItem?
    @Bindable var store: DesignStore
    @Binding var activeSheet: EditorSheet?
    /// Animated pictures play on the canvas, not only in Present and video.
    @AppStorage(AnimStore.playKey) private var playAnimated = false
    /// The editor's timeline is showing, with its playhead to time by.
    @AppStorage(TimelineStrip.key) private var timeline = false

    /// The border as a drag of its slider began, so going back to None puts
    /// back what was there.
    private struct BorderBefore {
        var stroke: String?
        var width: Double?
    }
    @State private var borderBefore: BorderBefore?
    /// The reach of the slider being dragged, held for the whole drag.
    @State private var heldReach: HeldReach?
    /// Which corners round, read as a Round drag began and held through it
    /// (the outer nil: no drag under way).
    @State private var heldCorners: CornerPatterns.Pattern?? = nil

    @State private var cuttingOut = false
    @State private var dictationBase = ""
    /// The type size's number, a toggle's glyph and its square, growing
    /// with Larger Text as far as the row does.
    @ScaledMetric(relativeTo: .subheadline) private var readoutSize: CGFloat = 14
    @ScaledMetric(relativeTo: .callout) private var toggleGlyph: CGFloat = 16
    @ScaledMetric(relativeTo: .callout) private var toggleSide: CGFloat = 32
    @State private var cutoutError: String?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Any part of a chart, or the whole of it: first in the
                    // row, before the controls of whichever part it is.
                    if store.selectedChart != nil {
                        toolButton("chart.bar.xaxis", "Edit chart") { activeSheet = .chart }
                        Divider().frame(height: 24).padding(.horizontal, 6)
                    }
                    if let el = store.singleSelection, hasTypeControls(el) {
                        typeControls(el)
                        Divider().frame(height: 24).padding(.horizontal, 6)
                    } else if store.textSelection != nil {
                        multiTextControls
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
        // A row with no room to grow: Larger Text up to accessibility2,
        // and past xxxLarge each item its icon alone (LargeType).
        .chromeTypeSize()
        // Its alerts and the size field type; the editor's plain Delete key
        // must leave them be.
        .onChange(of: editingAlt || editingLink || namingStyle || enteringSize) { _, open in
            store.textFieldOpen = open
        }
        // Dictation belongs to the one text box it began on: once anything
        // else is selected (the store sees to that), or the microphone stops
        // by itself, it is over — and it never began if the microphone or
        // speech was refused, so the box is not left waiting for it.
        .onChange(of: Dictation.shared.isListening) { _, listening in
            if !listening { store.finishDictation() }
        }
        .onChange(of: Dictation.shared.error) { _, error in
            if error != nil && !Dictation.shared.isListening { store.finishDictation() }
        }
        .onDisappear { endDictation() }
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
                ToolCaption(tr("Delete"))
            }
            .foregroundStyle(.red)
        }
        .toolLargeContent("trash", tr("Delete"))
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
        // Edit first, for a text box or a shape's words — a table cell's
        // too — as Canva puts it: the keyboard opens on the words.
        if let target = store.typedIn(el), store.editingTextId != target.id {
            toolButton("keyboard", "Edit") { store.startTyping(target.id) }
        }
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
        typeBasics
        HStack(spacing: 14) {
            styleToggles
            toggle("text.justify.leading", "Vertical", active: el.vertical == true) {
                store.updateSelected { e in
                    e.vertical = e.vertical == true ? nil : true
                    // A column and a warp exclude each other.
                    if e.vertical == true { e.warp = nil }
                    // A column wants height; give a one-line box a few rows.
                    if e.vertical == true, e.h < (e.fontSize ?? 42) * 4 { e.h = (e.fontSize ?? 42) * 4 }
                }
            }
            alignButton
            listMenu(el)
            indentButtons(el)
        }
        HStack(spacing: 14) {
            stylesMenu(el)
            // Only when some words have a colour, a size or a font of their
            // own, and not for a locked box, which it cannot change — as on
            // Android. It leaves links.
            if Spans.hasStyles(el.liveSpans) && !el.locked {
                toolButton("eraser", "Clear word colours and sizes") { store.clearWordStyles() }
            }
            toolButton("wand.and.stars", "Effects") { activeSheet = .effects }
            toolButton("arrow.up.and.down.text.horizontal", "Spacing") { activeSheet = .spacing }
            if !el.locked { photoInLetters(el) }
            if Dictation.isAvailable && !el.locked { dictateButton(el) }
            if el.vertical == true {
                // A curve or a path cannot bend words stood in columns; say
                // so rather than offer controls that change nothing.
                Text("A curve or a path waits while the words stand in columns.")
                    .font(Theme.controlLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(width: 150, alignment: .leading)
            } else {
                pathMenu(el)
                curveSliders(el)
            }
        }
    }

    /// Photo: a picture from the device poured into the letters
    /// (DesignStore.pourPhoto), as Canva fills type with a photo — the
    /// colour sheet's Photo fill row offers the design's own too — and,
    /// once filled, Adjust photo, which a double-tap offers as well.
    @ViewBuilder
    private func photoInLetters(_ el: Element) -> some View {
        PhotosPicker(selection: $letterPhoto, matching: .images) {
            toolLabel("photo", "Photo")
        }
        .buttonStyle(ToolButtonStyle())
        .onChange(of: letterPhoto) { _, item in
            guard let item else { return }
            letterPhoto = nil
            pourPickedPhoto(item)
        }
        if el.textFill?.isPhoto == true {
            toolButton("arrow.up.left.and.down.right.magnifyingglass", "Adjust photo") {
                if store.startPhotoAdjust(el.id) { activeSheet = .photoInLetters }
            }
        }
    }

    /// The picked photo stored among your uploads, as the Add sheet stores
    /// one, then poured into the selected texts' letters as one step.
    private func pourPickedPhoto(_ item: PhotosPickerItem) {
        let store = self.store
        Task {
            guard let src = await BackgroundYourPhotos.stored(item) else {
                store.buzz(.reject)
                store.announce(tr("Couldn't open that photo"), undoable: false)
                return
            }
            store.pourPhoto(src)
            store.buzz(.confirm)
        }
    }

    /// Several texts, or a group of nothing but text: the type they can
    /// share, set on every one at once and each box measured again, with
    /// "Mixed" wherever they differ. Lists, effects, curves and the rest
    /// stay one box's.
    @ViewBuilder
    private var multiTextControls: some View {
        typeBasics
        HStack(spacing: 14) {
            styleToggles
            alignButton
        }
    }

    /// Face, weight, colour and size, for one text or several. A font of
    /// your own this phone does not have says so beside the face: its words
    /// are in Modern Sans meanwhile.
    private var typeBasics: some View {
        HStack(spacing: 14) {
            let family = store.sharedText { FontLibrary.resolve($0.fontFamily) }
            fontButton(family)
            if let family, let missing = FontStore.missingNote(family, in: store.design) {
                missingFontChip(missing)
            }
            weightMenu
            textColourChip
            fontSizeStepper
        }
    }

    /// The face, "Aa" drawn in it — what the words will look like — opening
    /// the font picker; the plain glyph when the texts are in different ones.
    private func fontButton(_ family: String?) -> some View {
        Button { activeSheet = .fonts } label: {
            VStack(spacing: 3) {
                Group {
                    if let family {
                        Text(verbatim: "Aa")
                            .font(FontLibrary.font(family: family, size: 19, weight: 400, italic: false))
                            .lineLimit(1)
                    } else {
                        Image(systemName: "textformat").font(Theme.controlGlyph)
                    }
                }
                .frame(height: 22)
                ToolCaption(tr("Font"))
            }
        }
        .buttonStyle(ToolButtonStyle())
        .accessibilityLabel("Font")
        .accessibilityValue(family.map { FontStore.displayName($0, in: store.design) } ?? TypeReadouts.mixed)
    }

    /// Light to Black: the weights the texts' fonts have (TypeReadouts), the
    /// one they are drawn at ticked and said — none ticked when Mixed — set
    /// on every one as one Undo. None for texts only in fonts of your own,
    /// each one face. The font picker shows each drawn at its weight.
    @ViewBuilder
    private var weightMenu: some View {
        let texts = store.textsRead
        let weights = TypeReadouts.weights(texts)
        if !weights.isEmpty {
            Menu {
                Picker("Weight", selection: Binding(
                    get: { TypeReadouts.drawnWeight(texts) ?? 0 },
                    set: { store.setFontWeight($0) })) {
                    ForEach(weights, id: \.self) { weight in
                        Text(FontLibrary.weightName(weight)).tag(weight)
                    }
                }
            } label: {
                toolLabel("lineweight", "Weight")
            }
            .accessibilityLabel("Weight")
            .accessibilityValue(TypeReadouts.weightReadout(texts))
        }
    }

    /// "Font missing: <name>", which opens the font picker to choose another.
    private func missingFontChip(_ note: String) -> some View {
        Button { activeSheet = .fonts } label: {
            Label(note, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.controlLabel)
                .foregroundStyle(.red)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.12), in: Capsule())
        }
        .buttonStyle(ToolButtonStyle())
    }

    /// Gradient letters are not their plain colour underneath: the chip
    /// shows and says the gradient, as the Fill chip does a shape's. Texts
    /// in different colours get the chip in every colour.
    @ViewBuilder
    private var textColourChip: some View {
        let colour = store.sharedText { $0.color ?? "#1f2430" }
        let fill = store.sharedText { $0.textFill }
        if let colour, let fill {
            colorChip(fill?.primaryColor ?? colour, "Colour",
                      spoken: FillChoices.spokenFill(fill)) { activeSheet = .colorText }
        } else {
            mixedChip("Colour") { activeSheet = .colorText }
                .accessibilityValue(TypeReadouts.mixed)
        }
    }

    /// Bold, italic, underline, strikethrough and capitals, for every text
    /// selected: on for all of them, or off for all when every one has it
    /// already — Mixed while some are and some are not. Strikethrough strikes
    /// every word of each box (TextToggle.strike). Capitals have no symbol;
    /// "aA" says what they do.
    @ViewBuilder
    private var styleToggles: some View {
        styleToggle(.bold, "Bold", glyph: Image(systemName: "bold"))
        styleToggle(.italic, "Italic", glyph: Image(systemName: "italic"))
        styleToggle(.underline, "Underline", glyph: Image(systemName: "underline"))
        styleToggle(.strike, "Strikethrough", glyph: Image(systemName: "strikethrough"))
        styleToggle(.uppercase, "Uppercase", glyph: Text(verbatim: "aA"))
    }

    private func styleToggle<Glyph: View>(_ style: TextToggle, _ name: String, glyph: Glyph) -> some View {
        let shared = store.sharedText { style.isOn($0) }
        return toggle(glyph: glyph, name, active: shared == true, mixed: shared == nil) {
            store.toggleText(style)
        }
    }

    /// Left, centre, right, justify in turn — and which it is now, for
    /// VoiceOver, which otherwise heard only "Align". Several texts aligned
    /// differently all go to the first.
    private var alignButton: some View {
        let shared = store.sharedText { $0.align ?? "center" }
        return toolButton(alignIcon(shared), "Align") {
            let next = shared.map { TypeReadouts.nextAlignment(after: $0) } ?? "left"
            store.updateSelected { e in
                guard e.type == .text else { return }
                e.align = next
            }
        }
        .accessibilityValue(shared.map { TypeReadouts.alignment($0) } ?? TypeReadouts.mixed)
    }

    /// Speak, and the words append to this text as they arrive; tap again
    /// to stop, which is when the change is recorded. The words go into the
    /// box dictation began on and nowhere else — select anything else and
    /// the microphone stops, as the Android twin's does.
    private func dictateButton(_ el: Element) -> some View {
        let listening = Dictation.shared.isListening && store.dictationTarget == el.id
        return toolButton(listening ? "mic.fill" : "mic", listening ? "Stop" : "Dictate") {
            if listening {
                endDictation()
                return
            }
            endDictation()
            dictationBase = el.text ?? ""
            let base = dictationBase
            let target = el.id
            store.dictationTarget = target
            Dictation.shared.start(language: store.design.language) { spoken, isFinal in
                Task { @MainActor in
                    guard store.dictationTarget == target else { return }
                    store.dictate(Dictation.merge(base, RichText.escapeLiteral(spoken)))
                    if isFinal { store.finishDictation() }
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
                        e.curveStart = nil
                        e.warp = nil
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

    /// An entrance for the selection, an exit, and a way to see them.
    private func animateMenu(_ el: Element) -> some View {
        Menu {
            Button { store.animateSelected(nil) } label: {
                Label("No animation", systemImage: el.animation == nil ? "checkmark" : "circle")
            }
            Group {
                // Create: the element dragged round the page, recorded as its path.
                if store.selection.count == 1 {
                    Button { store.beginMotionRecord() } label: {
                        Label("Create", systemImage: el.animation?.kind == ElementAnimation.pathKind ? "checkmark" : "hand.draw")
                    }
                }
                Divider()
                entranceButtons(el)
            }
            Divider()
            ForEach(ElementAnimation.kinds.filter { ElementAnimation.loopKinds.contains($0) }, id: \.self) { kind in
                Button { store.animateSelected(kind); store.playPreview() } label: {
                    Label(ElementAnimation.name(kind), systemImage: el.animation?.kind == kind ? "checkmark" : "circle")
                }
            }
            if store.selectedElements.contains(where: { $0.type == .text }) {
                Divider()
                textAnimationButtons(el)
            }
            Divider()
            exitMenu(el)
            Button { store.playPreview() } label: { Label("Play this page", systemImage: "play") }
                .disabled(!store.pagePlays)
            if timeline || timed {
                Divider()
                timingButtons()
            }
        } label: {
            toolLabel("sparkles.rectangle.stack", "Animate", active: el.animation != nil || el.exitAnimation != nil)
        }
    }

    /// The text-only entrances, a menu of their own, and Animate by for
    /// the one on: letter, word or line.
    @ViewBuilder
    private func textAnimationButtons(_ el: Element) -> some View {
        Menu {
            ForEach(ElementAnimation.textKindOrder, id: \.self) { kind in
                Button { store.animateSelected(kind); store.playPreview() } label: {
                    Label(ElementAnimation.name(kind), systemImage: el.animation?.kind == kind ? "checkmark" : "circle")
                }
            }
        } label: {
            Label("Text animations", systemImage: "textformat")
        }
        if let animation = el.animation, ElementAnimation.textKinds.contains(animation.kind) {
            Picker("Animate by", selection: Binding(
                get: { animation.unit },
                set: { store.animateSelected(by: $0); store.playPreview() })) {
                Text(tr("Letter", context: "animate by")).tag("letter")
                Text("Word").tag("word")
                Text(tr("Line", context: "animate by")).tag("line")
            }
            .pickerStyle(.menu)
        }
    }

    /// The entrances that are not a loop or a text's own: Grow first, for a
    /// chart — its bars rise, its slices sweep and its lines draw on, every
    /// part of it together — then the rest.
    @ViewBuilder
    private func entranceButtons(_ el: Element) -> some View {
        if ElementAnimation.canGrow(store.selectedElements) {
            Button { store.animateSelected(ElementAnimation.grow); store.playPreview() } label: {
                Label(ElementAnimation.name(ElementAnimation.grow),
                      systemImage: el.animation?.kind == ElementAnimation.grow ? "checkmark" : "circle")
            }
        }
        ForEach(entranceKinds, id: \.self) { kind in
            Button { store.animateSelected(kind); store.playPreview() } label: {
                Label(ElementAnimation.name(kind), systemImage: el.animation?.kind == kind ? "checkmark" : "circle")
            }
        }
    }

    /// The entrances offered besides Grow and a text's own: a photo's motion
    /// only when a photo or a clip is selected. Tumble, a text kind that
    /// moves anything else whole (anyElementKinds), is here when no text is
    /// selected, and in the text menu when one is.
    private var entranceKinds: [String] {
        let photos = store.selectedElements.contains { $0.type == .image }
        let text = store.selectedElements.contains { $0.type == .text }
        return ElementAnimation.kinds.filter { kind in
            kind != ElementAnimation.grow
                && !(ElementAnimation.textKinds.contains(kind) && (text || ElementAnimation.textOnly(kind)))
                && !ElementAnimation.loopKinds.contains(kind) && (photos || !ElementAnimation.forPhotos(kind))
        }
    }

    /// Whether anything selected has a timing of its own.
    private var timed: Bool {
        store.selectedElements.contains { $0.timing != nil }
    }

    /// When the selection shows within its page: by the timeline's playhead
    /// while the timeline is on — gone from the menu while it is off,
    /// unavailable on a hidden page, and Hide not at the page's very start,
    /// which would hide it all through — and Show for the whole page once it
    /// has a timing. The Android twin's Animate panel, rule for rule.
    @ViewBuilder
    private func timingButtons() -> some View {
        let t = store.playheadInPage
        let none = store.unlockedSelectionCount == 0
        if timeline {
            Button { store.showSelectedFromPlayhead() } label: {
                Label("Show from playhead", systemImage: "eye")
            }
            .disabled(t == nil || none)
            Button { store.hideSelectedFromPlayhead() } label: {
                Label("Hide from playhead", systemImage: "eye.slash")
            }
            .disabled((t ?? 0) < 0.05 || none)
        }
        if timed {
            Button { store.clearSelectedTiming() } label: {
                Label("Show for the whole page", systemImage: "arrow.left.and.right")
            }
            .disabled(none)
        }
    }

    /// How the selection leaves as the page ends; a pick plays the page's
    /// last moments to show it.
    private func exitMenu(_ el: Element) -> some View {
        // A kind from a newer build leaves as a fade, so it is ticked as one.
        let known = ElementAnimation.exitKinds + Array(ElementAnimation.textKindOrder.dropFirst(4))
        let current = el.exitAnimation.map { known.contains($0.kind) ? $0.kind : "fade" }
        let texts = store.selectedElements.contains { $0.type == .text }
        return Menu {
            Button { store.exitSelected(nil) } label: {
                Label(ElementAnimation.exitName(nil), systemImage: current == nil ? "checkmark" : "circle")
            }
            Divider()
            ForEach(ElementAnimation.exitKinds, id: \.self) { kind in
                exitButton(kind, current: current)
            }
            // Text leaves a unit at a time too: the entrances played back.
            if texts {
                Divider()
                ForEach(Array(ElementAnimation.textKindOrder.dropFirst(4)), id: \.self) { kind in
                    exitButton(kind, current: current)
                }
            }
        } label: {
            // An animation's Exit, not a key's or a menu's.
            Label(tr("Exit", context: "animation"), systemImage: "rectangle.portrait.and.arrow.right")
        }
        .disabled(store.unlockedSelectionCount == 0)
    }

    private func exitButton(_ kind: String, current: String?) -> some View {
        Button {
            store.exitSelected(kind)
            store.playPreview(from: store.exitPreviewStart)
        } label: {
            Label(ElementAnimation.exitName(kind), systemImage: current == kind ? "checkmark" : "circle")
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
        // A code is traced in its own colours, its background round it.
        guard let image = CodeGenerator.picture(of: el)?.image ?? PhotoLibrary.resolve(el.src) else { return }
        let size = image.size
        Task.detached(priority: .userInitiated) {
            let traced = Tracer.trace(image)
            await MainActor.run {
                guard let traced else {
                    store.buzz(.reject)
                    store.announce(tr("Nothing in the picture to trace"), undoable: false)
                    return
                }
                store.add(Tracer.shape(traced, over: el, imageSize: size), centered: false)
                store.buzz(.confirm)
                store.announce(tr("Traced — a shape in the picture's colour"))
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
                    store.announce(tr("No code found in this picture"), undoable: false)
                    return
                }
                // A code read from a print can hold more than a code drawn
                // here can: refused, rather than a blank code on the page.
                guard fits else {
                    store.buzz(.reject)
                    store.announce(tr("That code holds more than a QR code can"), undoable: false)
                    return
                }
                let side = min(frame.width, frame.height) * 0.6
                var code = Element.image(CodeGenerator.source(for: payload), w: side.rounded(), h: side.rounded())
                code.x = (frame.midX - side / 2).rounded(); code.y = (frame.midY - side / 2).rounded()
                store.add(code, centered: false)
                store.buzz(.confirm)
                store.announce(tr("Read the code — here it is, clean"))
            }
        }
    }

    /// The active brand kit's text roles, then saved, linked text styles:
    /// apply one, save the current look as one, or push this element's look
    /// back into the style it follows. A popover rather than a menu,
    /// because a menu sets every row in the system font and each style is
    /// shown here in its own face — "Heading" looks like a heading — as the
    /// Android twin's style chips are.
    private func stylesMenu(_ el: Element) -> some View {
        let styles = TextStyles.load()
        let followed = styles.first { $0.id == el.textStyleId }
        return Button {
            showingStyles = true
        } label: {
            toolLabel("character.textbox", "Styles", active: followed != nil)
        }
        .buttonStyle(ToolButtonStyle())
        .accessibilityValue(followed?.name ?? tr("None"))
        .id(styleVersion)
        .popover(isPresented: $showingStyles) {
            stylesList(el, styles: styles, followed: followed)
                .presentationCompactAdaptation(.popover)
        }
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

    private func stylesList(_ el: Element, styles: [TextStyle], followed: TextStyle?) -> some View {
        // The kit's roles lead, those it sets, each in its face, as the
        // Android twin's Text panel leads with them.
        let fonts = BrandKit.load().fonts
        let roles = BrandFonts.Role.allCases.filter { fonts[$0] != nil }
        return VStack(alignment: .leading, spacing: 0) {
            if styles.isEmpty && roles.isEmpty {
                Text("No saved styles yet")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(roles) { role in
                            if let face = fonts[role] { brandRow(role, face: face, el: el) }
                        }
                        ForEach(styles) { style in styleRow(style, followed: style.id == followed?.id) }
                    }
                }
                .frame(maxHeight: 300)
            }
            Divider()
            styleActions(el, followed: followed)
        }
        .frame(minWidth: 260)
        .padding(.vertical, 6)
    }

    /// A brand role, in its own face: one tap sets the text in it.
    private func brandRow(_ role: BrandFonts.Role, face: BrandFont, el: Element) -> some View {
        let chosen = el.fontFamily == face.family && el.fontWeight == face.weight
        return Button {
            store.applyBrandFace(face, role: role)
            styleVersion += 1
            showingStyles = false
        } label: {
            HStack {
                Text(role.label)
                    .font(FontLibrary.font(family: face.family, size: 17, weight: face.weight, italic: false))
                    .lineLimit(1)
                Spacer(minLength: 12)
                if chosen { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(role.label), brand kit")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func styleRow(_ style: TextStyle, followed: Bool) -> some View {
        Button {
            store.applyTextStyle(style)
            styleVersion += 1
            showingStyles = false
        } label: {
            HStack {
                // In capitals when the style sets them.
                Text(style.style.uppercase == true ? style.name.uppercased() : style.name)
                    .font(FontLibrary.font(family: style.style.fontFamily, size: 17,
                                           weight: style.style.fontWeight ?? 400,
                                           italic: style.style.italic ?? false))
                    .lineLimit(1)
                Spacer(minLength: 12)
                if followed { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(followed ? .isSelected : [])
    }

    @ViewBuilder
    private func styleActions(_ el: Element, followed: TextStyle?) -> some View {
        Button {
            showingStyles = false
            styleName = ""
            // After the popover has gone, or the alert is never shown.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                namingStyle = true
            }
        } label: { Label("Save this look as a style…", systemImage: "plus") }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        if let followed {
            Button {
                store.updateTextStyle(followed.id, from: el)
                styleVersion += 1
                showingStyles = false
            } label: { Label("Update “\(followed.name)” from this text", systemImage: "arrow.triangle.2.circlepath") }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Button(role: .destructive) {
                TextStyles.remove(followed.id)
                styleVersion += 1
                showingStyles = false
            } label: { Label("Delete “\(followed.name)”", systemImage: "trash") }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    /// Bullets, numbers or letters on every line of the box — the typing
    /// bar sets the lines chosen — none ticked while the lines differ. A
    /// menu rather than a toggle because three list kinds through one
    /// button would cycle, and nobody counts taps to reach "letters".
    private func listMenu(_ el: Element) -> some View {
        let shared = TypeReadouts.shared(TextLists.lines(el).map(\.list))
        return Menu {
            Picker("List", selection: Binding(
                get: { shared ?? TypeReadouts.mixed },
                set: { style in
                    store.updateSelected {
                        $0.setListStyle(style)
                        $0.h = FontLibrary.layoutHeight(for: $0)
                    }
                })) {
                Label("No list", systemImage: "text.alignleft").tag("none")
                Label("Bullets", systemImage: "list.bullet").tag("bullet")
                Label("Numbers", systemImage: "list.number").tag("number")
                Label("Letters", systemImage: "character").tag("letter")
            }
        } label: {
            let icon = shared == "number" ? "list.number"
                : shared == "letter" ? "character" : "list.bullet"
            toolLabel(icon, "List", active: FontLibrary.isList(el))
        }
        .accessibilityLabel("List")
        .accessibilityValue(shared.map { TypeReadouts.listStyle($0) } ?? TypeReadouts.mixed)
    }

    /// Outdent and Indent for every line of the box, each held within the
    /// levels: Outdent while any line is in, Indent while any can go deeper.
    @ViewBuilder
    private func indentButtons(_ el: Element) -> some View {
        let levels = TextLists.lines(el).map(\.level)
        let deepest = levels.max() ?? 0
        toolButton("decrease.indent", "Outdent") { indent(by: -1) }
            .disabled(deepest == 0)
            .accessibilityValue("Level \(deepest)")
        toolButton("increase.indent", "Indent") { indent(by: 1) }
            .disabled((levels.min() ?? 0) >= FontLibrary.maxIndent)
            .accessibilityValue("Level \(deepest)")
    }

    private func indent(by delta: Int) {
        store.updateSelected {
            $0.stepIndent(by: delta)
            $0.h = FontLibrary.layoutHeight(for: $0)
        }
    }

    /// Curve, from a valley closed into a ring to a rainbow closed into one
    /// (TextPaths.maxCurve), pulled onto ±180 and ±360 with a tick as it
    /// lands; and, past half a ring, Rotate to turn it (curveStart).
    @ViewBuilder
    private func curveSliders(_ el: Element) -> some View {
        sliderControl("Curve", value: el.curve ?? 0, in: -TextPaths.maxCurve...TextPaths.maxCurve) { raw in
            let degrees = TextPaths.snappedCurve(raw)
            if degrees != raw && degrees != el.curve { store.buzz(.tick) }
            store.updateSelectedTransient { curve(&$0, to: degrees) }
        }
        if TextPaths.showsRotate(el.curve) {
            sliderControl("Rotate", value: el.curveStart ?? 0,
                          in: -TextPaths.maxCurveStart...TextPaths.maxCurveStart) { degrees in
                store.updateSelectedTransient { e in
                    let turned = degrees.rounded()
                    e.curveStart = turned == 0 ? nil : turned
                }
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
        if abs(degrees) >= TextOutliner.straightBelowDegrees {
            el.textPath = nil
            el.warp = nil
        }
        let centre = CGPoint(x: el.x + el.w / 2, y: el.y + el.h / 2)
        let straight = abs(degrees) < TextOutliner.straightBelowDegrees
        el.curve = straight ? nil : degrees
        // The ring's turn goes once the words are no longer a ring, as the
        // Rotate slider does.
        if !TextPaths.showsRotate(el.curve) { el.curveStart = nil }
        if straight {
            // measuredHeight, not layoutHeight: the curve has just been
            // cleared and this is deliberately the flat measurement.
            el.h = FontLibrary.measuredHeight(for: el)
        } else if let size = TextOutliner.curvedSize(for: el, degrees: degrees) {
            el.w = max(el.w, size.width)
            el.h = max(size.height, el.fontSize ?? 42)
            // A ring stands in its square.
            if abs(degrees) >= TextPaths.halfCurve { el.w = max(size.width, el.fontSize ?? 42) }
        }
        el.x = centre.x - el.w / 2
        el.y = centre.y - el.h / 2
    }

    /// Two steps of two points, and the number between them, which takes a
    /// size typed or picked from a list — 24 exactly, rather than nine taps.
    /// To VoiceOver it is one adjustable control, "Type size, 42", that
    /// swipes up and down — the iPhone's own way to read and change a
    /// number, rather than two bare "minus" and "plus" — with typing a size
    /// among its actions. Texts at different sizes read "Mixed".
    private var fontSizeStepper: some View {
        let size = store.sharedText { $0.fontSize ?? 42 }
        let readout = TypeReadouts.fontSize(size)
        return HStack(spacing: 4) {
            Button { bumpFontSize(-2) } label: { Image(systemName: "minus") }
                .accessibilityLabel("Smaller type")
            Button { enteringSize = true } label: {
                Text(readout)
                    .font(.system(size: readoutSize, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 34)
            }
            .popover(isPresented: $enteringSize) {
                TypeSizeEntry(current: size) { typed in
                    store.setFontSize(typed)
                    enteringSize = false
                }
                .presentationCompactAdaptation(.popover)
            }
            Button { bumpFontSize(2) } label: { Image(systemName: "plus") }
                .accessibilityLabel("Larger type")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(.systemGray6)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Type size")
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: bumpFontSize(2)
            case .decrement: bumpFontSize(-2)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Type a size") { enteringSize = true }
    }

    @ViewBuilder
    private func shapeControls(_ el: Element) -> some View {
        if Freehand.isStroke(el) {
            // A drawing has one colour, its ink. A Fill chip showed a colour
            // it does not have, and picking one filled the scribble in and
            // stopped it being a stroke — as the Android twin, one slot.
            colorChip(el.stroke ?? "#0d1216", "Colour") { activeSheet = .colorStroke }
        } else {
            // An SVG's line or outline part shows, and takes, its ink here.
            colorChip(Freehand.fillColour(el) ?? "#8b5cf6", "Fill",
                      spoken: Freehand.inksOnly(el) ? nil : FillChoices.spokenFill(el.fill)) { activeSheet = .colorFill }
            colorChip(el.stroke ?? "#0d1216", "Border") { activeSheet = .colorStroke }
        }
        if el.fill?.kind == "none" {
            // A drawn stroke or an outline: its width is what there is to set,
            // to 40 as on the Android twin, and further when it already is —
            // a highlighter stroke is 48 or 72 — so it is not snapped thinner
            // on the first touch.
            let width = el.strokeWidth ?? 4
            let widthReach = reach("Width", 1...40, width)
            sliderControl("Width", value: width, in: widthReach,
                          onEditing: { holdReach("Width", widthReach, $0) }) { v in
                store.updateSelectedTransient { $0.strokeWidth = v }
            }
            // An outline's line dashed or dotted too; a drawing's is not.
            if !Freehand.isStroke(el) { borderStylePicker(el) }
        } else if !Freehand.isStroke(el) {
            borderSlider(el)
            borderStylePicker(el)
        }
        if Freehand.isStroke(el) {
            toolButton("text.viewfinder", "To text") { store.strokesToText() }
        }
        // Words in the shape: their face, size, colour and style, and a way
        // in to type them, as a double tap on the shape is. A table cell's
        // words are its text box's.
        if ShapeText.takesText(el) && !el.locked && el.table == nil {
            toolButton("character.textbox", "Text") { activeSheet = .shapeText }
        }
        // Another shape in its place, keeping its size, colours and effects.
        // Not for a locked one, which it could not change, as on the Android
        // twin.
        if DesignStore.swapsShape(el) && !el.locked {
            toolButton("square.on.circle", "Shape") { activeSheet = .shapes }
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
        let border = reach("Border", 0...40, width)
        return VStack(spacing: 2) {
            Slider(value: Binding(get: { width }, set: { setBorder($0, on: el) }),
                   in: border,
                   onEditingChanged: { editing in
                       holdReach("Border", border, editing)
                       if editing {
                           borderBefore = BorderBefore(stroke: el.stroke, width: el.strokeWidth)
                       } else {
                           store.commit()
                           borderBefore = nil
                       }
                   })
            .frame(width: 110)
            .accessibilityLabel("Border")
            .accessibilityValue(width < 0.5 ? tr("None") : "\(Int(width.rounded()))")
            Text(width < 0.5 ? tr("Border None") : tr("Border %d", Int(width.rounded())))
                .font(Theme.controlLabel)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private func setBorder(_ v: Double, on el: Element) {
        let before = borderBefore ?? BorderBefore(stroke: el.stroke, width: el.strokeWidth)
        store.updateSelectedTransient { e in
            guard Self.takesBorderStyle(e) else { return }
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

    /// Solid, Dashed or Dotted, beside the Border slider (see BorderDash),
    /// as one step. A shape or photo with no border yet is given one at 4,
    /// in the Border chip's ink, so the choice shows.
    private func borderStylePicker(_ el: Element) -> some View {
        let current = BorderDash.kept(el.dash) ?? "solid"
        return Picker("Border style", selection: Binding(get: { current }, set: { setBorderStyle($0) })) {
            ForEach(BorderDash.styles, id: \.name) { style in
                Text(style.name).tag(style.key ?? "solid")
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 210)
        .accessibilityLabel("Border style")
    }

    private func setBorderStyle(_ key: String) {
        let dash = BorderDash.kept(key)
        let targets = store.selectedElements.filter { !$0.locked && Self.takesBorderStyle($0) }
        guard targets.contains(where: { BorderDash.kept($0.dash) != dash }) else { return }
        store.updateSelected { e in
            guard Self.takesBorderStyle(e) else { return }
            e.dash = dash
            if dash != nil && (e.strokeWidth ?? 0) < 0.5 {
                e.strokeWidth = 4
                if e.stroke == nil { e.stroke = "#0d1216" }
            }
        }
        store.buzz(.tick)
    }

    /// What has a border to set: a shape that is not a drawing, or a photo.
    static func takesBorderStyle(_ el: Element) -> Bool {
        (el.type == .shape && !Freehand.isStroke(el)) || el.type == .image
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
        .accessibilityValue(current?.name ?? tr("Square"))
    }

    /// Erase: the brush that makes parts of the photo clear and brings them
    /// back, and the one that takes an object away, filling where it was
    /// from what is round it.
    private func eraseMenu(_ el: Element) -> some View {
        Menu {
            Button {
                store.beginBrush(el.id, kind: .mask)
            } label: { Label("Erase and restore", systemImage: "eraser.line.dashed") }
            Button {
                if store.beginBrush(el.id, kind: .mask) { store.brushing?.clearing = true }
            } label: { Label("Clear a colour", systemImage: "drop.halffull") }
            Button {
                store.beginErasing(el.id)
            } label: { Label("Remove an object", systemImage: "wand.and.rays") }
        } label: {
            toolLabel("eraser", "Erase", active: el.mask?.strokes.isEmpty == false)
        }
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
            // A clip: its trim, speed and loop, and Play to see it move;
            // stills come from the frame at its start.
            toolButton("film", "Clip") { activeSheet = .clip }
        } else if CodeGenerator.isCode(el.src) {
            // A code's words, changed where it sits — erasing part of a code
            // only stops it scanning, so that is not offered. A barcode's
            // too.
            toolButton("qrcode", "Edit code") { editingCode = true }
                .sheet(isPresented: $editingCode) {
                    QRCodeSheet(store: store, id: el.id, payload: CodeGenerator.payload(from: el.src ?? "") ?? "")
                }
        } else if AnimStore.isAnim(el.src) {
            // An animated picture always plays in Present and in a video or
            // GIF; here, only when asked, and otherwise shows its first
            // frame. Erasing a frame would leave a still, so that is not
            // offered.
            Button {
                playAnimated.toggle()
            } label: {
                toolLabel(playAnimated ? "pause.circle" : "play.circle", "Play in the editor", active: playAnimated)
            }
            .buttonStyle(ToolButtonStyle())
            .accessibilityAddTraits(playAnimated ? [.isSelected] : [])
        } else {
            eraseMenu(el)
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
        // Grouped, which changes nothing on screen: a ViewBuilder block takes
        // at most ten children, and the image controls sit close to that.
        Group {
            toolButton("arrow.2.squarepath", "Replace") {
                store.replaceTargetId = el.id
                activeSheet = .insert
            }
            // A frame's or a grid cell's picture, taken out as a photo of
            // its own, the frame left empty.
            if store.canDetachImage {
                toolButton("photo.on.rectangle", "Detach image") { store.detachImage() }
            }
            // The photo behind the whole page instead, as it shows here; a
            // clip says so, as the Android twin's does.
            if DesignStore.canBecomeBackground(el) {
                let label = VideoStore.isVideo(el.src) ? "Set video as background" : "Use as background"
                toolButton("rectangle.inset.filled", label) {
                    store.useAsBackground(el.id)
                }
            }
            // The page recoloured from this photo, a new combination a tap.
            if PhotoColours.offered(el) {
                toolButton("paintpalette", "Apply colours to page") { store.applyPhotoColours() }
            }
        }
        // A border round the photo, following its frame: its ink, its
        // width and whether it is dashed or dotted, as a shape's.
        Group {
            colorChip(el.stroke ?? "#0d1216", "Border") { activeSheet = .colorStroke }
            borderSlider(el)
            borderStylePicker(el)
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
        let weight = el.thickness ?? 4
        let weightReach = reach("Weight", 1...60, weight)
        sliderControl("Weight", value: weight, in: weightReach,
                      onEditing: { holdReach("Weight", weightReach, $0) }) { v in
            // An elbow's or a curve's box is its ends padded by its weight:
            // laid round the same ends again.
            store.updateSelectedTransient { $0 = LineRoutes.withThickness($0, v) }
        }
        lineTypePicker(el)
        if LineRoutes.keepsLevel(el) {
            // Where an elbow's corner sits, or how far a curve bows: live,
            // one step a drag.
            let label = LineRoutes.routeType(of: el) == .elbow ? "Corner" : "Bend"
            sliderControl(label, value: (LineRoutes.bend(of: el) * 100).rounded(), in: -100...100) { v in
                store.updateSelectedTransient { e in
                    if LineRoutes.keepsLevel(e) { e = LineRoutes.withBend(e, v.rounded() / 100) }
                }
            }
        }
        dashMenu(el)
        // Each end on its own, eleven ways, and how big the heads are
        // (LineEnds), as the Android twin sets them.
        toolButton("arrow.left.and.right", "Ends") { activeSheet = .lineEnds }
    }

    /// Straight, Elbow or Curve (LineRoutes), the line's ends staying where
    /// they are: one step a tap, on every unlocked line selected, and
    /// nothing recorded when they already are.
    private func lineTypePicker(_ el: Element) -> some View {
        let current = LineRoutes.routeType(of: el)
        return Picker("Line type", selection: Binding(get: { current }, set: { type in
            let lines = store.selectedElements.filter { $0.type == .line && !$0.locked }
            guard lines.contains(where: { LineRoutes.routeType(of: $0) != type }) else { return }
            store.updateSelected { e in
                if e.type == .line { e = LineRoutes.withType(e, type) }
            }
            store.buzz(.tick)
        })) {
            ForEach(LineRoutes.RouteType.allCases) { type in Text(type.label).tag(type) }
        }
        .pickerStyle(.segmented)
        .frame(width: 210)
        .accessibilityLabel("Line type")
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
                        Label(Self.dashName(dash), systemImage: "checkmark")
                    } else {
                        Text(Self.dashName(dash))
                    }
                }
            }
        } label: {
            toolLabel("line.3.horizontal.decrease", "Dash", active: current != "solid")
        }
        .accessibilityLabel("Dash")
        .accessibilityValue(Self.dashName(current))
    }

    static let dashStyles = ["solid", "dashed", "dotted"]

    /// What one of those is called: Solid, Dashed or Dotted.
    static func dashName(_ dash: String) -> String {
        switch dash {
        case "dashed": return tr("Dashed")
        case "dotted": return tr("Dotted")
        default: return tr("Solid")
        }
    }

    /// A line's dash as one of those; none, or anything else, is solid.
    static func dashStyle(_ dash: String?) -> String {
        dashStyles.contains(dash ?? "") ? dash ?? "solid" : "solid"
    }

    // MARK: universal

    @ViewBuilder
    private var universalControls: some View {
        // Grouped to keep this block within a ViewBuilder's ten children.
        Group {
            // One grid's cells, every one: its spacing and corners, the
            // whole grid laid out again as they move.
            if store.selectedGridCanRelay, let grid = store.selectedGrid { gridControls(grid.cells) }
            // Several things selected — a sticky group, a band's worth —
            // recolour together, each its own way: text, lines, shapes and
            // drawn strokes. Several texts have the text controls' own
            // Colour chip.
            if store.selection.count > 1 && store.selectionTakesColour && store.textSelection == nil {
                multiColourChip
            }
            // An icon, sticker, graphic from the pack or library shape:
            // things like it, to swap in or add (SimilarSheet).
            if store.offersSimilar {
                toolButton("square.grid.2x2", "More like this") { activeSheet = .similar }
            }
            // An icon, shape, sticker or graphic shows only part of itself.
            if store.canCropGraphic {
                toolButton("crop", "Crop") { store.startGraphicCrop() }
            }
        }
        // Grouped to keep this block within a ViewBuilder's ten children.
        Group {
            // Any cell of a table made here: its rows, columns, cells and
            // header.
            if store.tableSelection != nil {
                toolButton("tablecells", "Table") { activeSheet = .table }
            }
            toolButton("square.3.layers.3d", "Position") { activeSheet = .position }
            toolButton("shadow", "Shadow") { activeSheet = .shadow }
            if store.singleSelection != nil { copyStyleButton }
        }
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

        lockMenu
        if let el = store.singleSelection, !el.locked { linkButton(el) }
        toolButton("plus.square.on.square", "Duplicate") { store.duplicateSelected() }
        // A selection built a tap at a time; the banner over this bar says
        // how many, with Select all and Done.
        toolButton("checklist", "Select multiple") {
            store.startSelectingMultiple()
            AccessibilityNotification.Announcement(DesignStore.selectMultipleOn).post()
        }
        if store.selection.count == 2 {
            toolButton("arrow.right", "Connect") { store.connectSelected() }
        }
        Group {
            toolButton("square.2.layers.3d.top.filled", "Forward") { store.reorderSelected(.forward) }
            toolButton("square.2.layers.3d.bottom.filled", "Backward") { store.reorderSelected(.backward) }
        }
    }

    /// The paint roller: copies this one's style and arms paint mode, in
    /// which the next taps paste it (StylePaint); lit while it is armed, and
    /// pressed again it is put away.
    private var copyStyleButton: some View {
        Button { store.toggleStylePainting() } label: {
            toolLabel("paintbrush.pointed", "Copy style", active: store.stylePainting)
        }
        .buttonStyle(ToolButtonStyle())
        .accessibilityAddTraits(store.stylePainting ? .isSelected : [])
        .accessibilityHint(store.stylePainting ? tr("Paint mode is on. Tap again to stop")
                           : tr("Then tap something to paste the style onto it"))
    }

    /// A grid's Layout — another of the library's layouts with as many
    /// cells or more, its pictures handed on, one step — then its Spacing,
    /// in page units, and Corners, in percent of each cell's shorter side —
    /// each release one Undo, as every slider here. The dividers between
    /// its cells are dragged on the canvas itself.
    @ViewBuilder
    private func gridControls(_ cells: [Element]) -> some View {
        let current = cells.first?.grid?.layout
        Menu {
            ForEach(PhotoGrids.layoutsFor(cells.count)) { layout in
                Button { store.changeGridLayout(to: layout) } label: {
                    Label(tr(layout.name), systemImage: layout.id == current ? "checkmark" : "square.grid.2x2")
                }
            }
        } label: {
            toolLabel("square.grid.2x2", "Layout")
        }
        .accessibilityLabel("Layout")
        sliderControl("Spacing", value: PhotoGrids.spacing(of: cells), in: 0...PhotoGrids.maxSpacing) { v in
            store.setGridSpacingTransient(v)
        }
        sliderControl("Corners", value: PhotoGrids.corners(of: cells), in: 0...PhotoGrids.maxCorners) { v in
            store.setGridCornersTransient(v)
        }
    }

    /// Lock, Lock position or Unlock for everything selected, each one
    /// step — the Android twin's Lock submenu. Its face says how the
    /// selection is locked: a filled padlock whole, one in outline in
    /// position only, open otherwise, and lit while locked either way.
    private var lockMenu: some View {
        let current = store.selectionLock
        return Menu {
            ForEach([ElementLock.Mode.full, .position, .unlocked], id: \.self) { mode in
                Button { store.lockSelected(mode) } label: {
                    Label(ElementLock.name(mode),
                          systemImage: current == mode ? "checkmark"
                              : mode == .unlocked ? "lock.open" : ElementLock.symbol(mode))
                }
            }
        } label: {
            toolLabel(current == .full || current == .position ? ElementLock.symbol(current ?? .full) : "lock.open",
                      "Lock", active: current == .full || current == .position)
        }
        .accessibilityValue(current == .full ? tr("Locked") : current == .position ? tr("Position locked") : "")
    }

    /// A colour chip with no one colour in it, since the selection has many.
    private var multiColourChip: some View {
        mixedChip("Colour") { activeSheet = .colorSelection }
            .accessibilityLabel("Colour of everything selected")
    }

    /// A chip in every colour, for things selected in more than one.
    private func mixedChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.15)))
                    .frame(width: 26, height: 26)
                ToolCaption(tr(label))
            }
        }
        .buttonStyle(ToolButtonStyle())
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
        .linkAlert(isPresented: $editingLink, draft: $linkDraft, linked: linked, design: store.design) { url in
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
                ToolCaption(tr("Cut out"))
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
            store.announce(tr("This photo is locked. Tap Unlock to edit it."), undoable: false)
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
                    store.announce(tr("This photo is locked. Tap Unlock to edit it."), undoable: false)
                    return
                }
                // Committed through the page so it lands in undo as one step,
                // and addressed by id rather than by selection: the cutout
                // finishes asynchronously and the selection may have moved on.
                // The picture before the cut is kept as the mask's base, so
                // the Restore brush can paint back what the cut took away —
                // the first picture's, however often it is cut again.
                store.applyToPage { page in
                    if let i = page.elements.firstIndex(where: { $0.id == id }) {
                        var mask = page.elements[i].mask ?? ImageMask()
                        if mask.base == nil { mask.base = src }
                        page.elements[i].mask = ImageMask.kept(mask)
                        page.elements[i].src = newSrc
                    }
                }
            }
        }
    }

    /// Stops the microphone and records what it wrote as one step.
    private func endDictation() {
        store.endDictation()
    }

    /// `label`, here and in the helpers below, is the catalogue's English,
    /// shown in the app's language.
    private func toolButton(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: system).font(Theme.controlGlyph)
                ToolCaption(tr(label))
            }
        }
        .buttonStyle(ToolButtonStyle())
        .toolLargeContent(system, tr(label))
    }

    /// The face of a toolButton without the button, for a Menu label.
    private func toolLabel(_ system: String, _ label: String, active: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: system).font(Theme.controlGlyph)
            ToolCaption(tr(label))
        }
        .foregroundStyle(active ? Theme.accent : Color.primary)
        .toolLargeContent(system, tr(label))
    }

    private func toggle(_ system: String, _ name: String, active: Bool,
                        action: @escaping () -> Void) -> some View {
        toggle(glyph: Image(systemName: system), name, active: active, action: action)
    }

    /// A toggle with any face. `mixed`: some of the texts selected have it
    /// and some not — a dashed ring, and "Mixed" to VoiceOver.
    private func toggle<Glyph: View>(glyph: Glyph, _ name: String, active: Bool, mixed: Bool = false,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glyph
                .font(.system(size: toggleGlyph, weight: .semibold))
                .frame(width: toggleSide, height: toggleSide)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Theme.accentSubtle : Color.clear))
                .overlay {
                    if mixed {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }
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
        .accessibilityLabel(tr(name))
        .accessibilityValue(mixed ? TypeReadouts.mixed : "")
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
                ToolCaption(tr(label))
            }
        }
        .buttonStyle(ToolButtonStyle())
        // "Fill, dark blue": what it is now, in words — or "photo", "red
        // pattern", "no fill" when it is not one colour.
        .accessibilityValue(spoken ?? ElementNames.colourName(hex))
    }

    struct HeldReach {
        var label: String
        var range: ClosedRange<Double>
    }

    /// A slider's reach: `base`, out to the value it holds, so the value is
    /// shown as it is and not snapped on the first touch — and, while that
    /// slider is dragged, the reach it had when the drag began: one worked
    /// out afresh from the value on every frame shrank under the thumb as
    /// it was dragged down. As the Android twin's tracks only widen.
    private func reach(_ label: String, _ base: ClosedRange<Double>, _ value: Double) -> ClosedRange<Double> {
        if let held = heldReach, held.label == label { return held.range }
        return min(base.lowerBound, value)...max(base.upperBound, value)
    }

    private func holdReach(_ label: String, _ range: ClosedRange<Double>, _ editing: Bool) {
        heldReach = editing ? HeldReach(label: label, range: range) : nil
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
            .accessibilityLabel(tr(label))
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
        "\(tr(label)) \(Self.readoutValue(label, value))"
    }

    /// The number a slider shows: a percentage for opacity and a grid's
    /// corners, else whole.
    static func readoutValue(_ label: String, _ value: Double) -> String {
        if label == "Opacity" { return "\(Int((value * 100).rounded()))%" }
        return label == "Corners" ? "\(Int(value.rounded()))%" : "\(Int(value.rounded()))"
    }

    private func alignIcon(_ align: String?) -> String {
        switch align ?? "center" {
        case "left": return "text.alignleft"
        case "right": return "text.alignright"
        case "justify": return "text.justify"
        default: return "text.aligncenter"
        }
    }

    /// A step of whole points from the size as it is — 12.5 steps to 14.5
    /// — within the range.
    private func bumpFontSize(_ delta: Double) {
        store.updateSelected { el in
            guard el.type == .text else { return }
            el.fontSize = TypeReadouts.wholeSize((el.fontSize ?? 42) + delta)
            el.h = FontLibrary.layoutHeight(for: el)
        }
    }
}

/// A type size typed on the number pad, or one of the usual ones picked: to
/// one decimal place from 1 to 800 (TypeReadouts.typedSize), for every text
/// selected, each box fitted to it again — as the Android twin's size
/// readout opens.
private struct TypeSizeEntry: View {
    /// The size now; nil when the texts selected differ.
    let current: Double?
    var onSet: (Double) -> Void
    @State private var draft: String
    @FocusState private var typing: Bool

    init(current: Double?, onSet: @escaping (Double) -> Void) {
        self.current = current
        self.onSet = onSet
        _draft = State(initialValue: current.map { TypeReadouts.fontSize($0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TextField("Size", text: $draft)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .frame(width: 96)
                    .focused($typing)
                    .onSubmit(useTyped)
                    .accessibilityLabel("Type size")
                Button("Set", action: useTyped)
                    .buttonStyle(.borderedProminent)
                    .disabled(TypeReadouts.typedSize(draft) == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(TypeReadouts.presetSizes, id: \.self) { size in
                        presetRow(size)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(minWidth: 200)
        .onAppear { typing = true }
    }

    private func presetRow(_ size: Double) -> some View {
        Button { onSet(size) } label: {
            HStack {
                Text("\(Int(size))").monospacedDigit()
                Spacer(minLength: 12)
                if size == current { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(size == current ? .isSelected : [])
    }

    private func useTyped() {
        guard let size = TypeReadouts.typedSize(draft) else { return }
        onSet(size)
    }
}

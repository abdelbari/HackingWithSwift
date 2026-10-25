// Editor sheets: background, effects, spacing, filters, crop,
// position, layers, resize. The colour picker and the font picker have
// files of their own — they grew past what belongs in a shared one, and
// past the size the Linux static checker could read in a single string.

import SwiftUI
import UIKit

/// Shared by every editor sheet, including the colour picker in its own
/// file — so not private, which at file scope means this file only.
let sheetDetents: Set<PresentationDetent> = [.medium, .large]

// MARK: - background

/// The page's gradients, in the shape of your choosing — linear, radial or
/// angular — as the Android twin offers them for a background. The shape
/// only changes the tiles and the next tap; the background changes when a
/// tile is tapped, and tapping the one already there records nothing. The
/// current one wears a ring.
struct BackgroundGradients: View {
    @Bindable var store: DesignStore
    var columns: [GridItem]
    @State private var kind = "linear"

    private var current: Paint? {
        if case .gradient(let paint) = store.page.background { return paint }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Gradient shape", selection: $kind) {
                Text("Linear").tag("linear")
                Text("Radial").tag("radial")
                Text("Angular").tag("angular")
            }
            .pickerStyle(.segmented)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ContentLibrary.gradients) { preset in
                    tile(preset)
                }
            }
        }
        .onAppear { kind = GradientPreset.kind(of: current) }
    }

    private func tile(_ preset: GradientPreset) -> some View {
        let paint = preset.paint(kind: kind)
        let chosen = GradientPreset.same(current, paint)
        return Button {
            guard !chosen else { return }
            store.applyToPage { $0.background = .gradient(paint) }
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .fill(paint.gradientStyle())
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(chosen ? Theme.accent : Color.black.opacity(0.12), lineWidth: chosen ? 3 : 1))
                .frame(height: 40)
        }
        .accessibilityLabel(tr("%@, %@ gradient", preset.name, ColorPickerSheet.gradientKindWord(kind)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

struct BackgroundSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                BackgroundChoices(store: store)
                    .padding()
            }
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

/// One of the library's pictures as the page's background: named for
/// VoiceOver, ringed when it is the one behind the page, and not applied
/// again when it already is — as the Android twin's backdrop tiles.
struct BackgroundPhotoTile: View {
    @Bindable var store: DesignStore
    let photo: PhotoDef

    var body: some View {
        let chosen = store.page.background == .image("asset:\(photo.id)")
        Button {
            guard !chosen else { return }
            store.applyToPage { $0.background = .image("asset:\(photo.id)") }
        } label: {
            photoThumb(photo.id)
                .overlay {
                    if chosen {
                        RoundedRectangle(cornerRadius: 9).stroke(Theme.accent, lineWidth: 3)
                    }
                }
        }
        .accessibilityLabel("Background \(photo.name)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

func photoThumb(_ id: String) -> some View {
    Group {
        if let ui = PhotoLibrary.image(id: id) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(4 / 3, contentMode: .fill)
        } else {
            Color(.systemGray5)
        }
    }
    .frame(height: 68)
    .clipShape(RoundedRectangle(cornerRadius: 9))
}

// MARK: - text effects

/// The effects as tiles, and under them the chosen one's settings: sliders
/// that draw live and are one Undo per drag, its colours, and Reset. Another
/// effect starts from its own defaults; tapping the one on keeps its settings.
/// With several boxes selected a tile sets every one, and the settings show
/// while they share an effect, each "Mixed" where they differ and moved to
/// one value on all of them (TextSelection); Warp stays one box's.
struct EffectsSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    /// The boxes the sheet reads: the one selected, or several.
    private var boxes: [Element] { TextSelection.reading(store.selectedElements, .effect) }
    private var current: TextEffect { TextSelection.effect(boxes) ?? .none }
    private var several: Bool { boxes.count > 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(TextEffect.allCases) { effect in
                            tile(effect)
                        }
                    }
                    if current != .none { settings(current) }
                    // Warp: the letters bent in their box, and Edit shape,
                    // which closes the sheet to show the handles.
                    if !several {
                        WarpSection(store: store, onEditShape: { if store.shapeEditingId != nil { dismiss() } })
                    }
                }
                .padding()
            }
            .navigationTitle("Text effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onDisappear { if store.hasPendingChanges { store.commit() } }
    }

    private func tile(_ effect: TextEffect) -> some View {
        let active = TextSelection.effect(boxes) == effect
        return Button {
            settleColour()
            store.setTextEffect(effect)
        } label: {
            VStack(spacing: 6) {
                effectPreview(effect)
                    .frame(width: 64, height: 44)
                Text(effect.displayName).font(.caption2)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? Theme.accent : .clear, lineWidth: 2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(effect.displayName) effect")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func effectPreview(_ effect: TextEffect) -> some View {
        var el = Element.text("Ag", fontSize: 30, w: 64)
        el.color = "#6d28d9"
        el.align = "center"
        el.effect = TextEffectSpec(type: effect.rawValue)
        el.h = 44
        return TextElementView(element: el)
    }

    /// The chosen effect's sliders and colours, in the Android twin's words.
    private func settings(_ effect: TextEffect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Adjust").font(.headline)
                Spacer()
                Button("Reset") {
                    settleColour()
                    store.updateSelected { el in
                        guard TextEffect.from(el.effect) == effect, let type = el.effect?.type else { return }
                        el.effect = TextEffectSpec(type: type)
                    }
                }
                .font(.callout)
                .disabled(boxes.allSatisfy { $0.effect?.isAtDefaults ?? true })
            }
            ForEach(effect.params) { param in
                dial(param, of: effect)
            }
            if effect.takesColor {
                colorRow(tr("Colour"), of: effect, second: false)
            }
            if effect.defaultColor2 != nil {
                colorRow(tr("Second colour"), of: effect, second: true)
            }
        }
    }

    /// A colour picked a moment ago, closed as a step of its own: the
    /// picker never says when it is done, so the next control does it
    /// rather than fold the colour into its own Undo.
    private func settleColour() {
        if store.hasPendingChanges { store.commit() }
    }

    /// Every selected, unlocked text with this effect, changed while a
    /// control moves; the store's commit makes it one step.
    private func live(_ effect: TextEffect, _ change: (inout TextEffectSpec) -> Void) {
        store.updateSelectedTransient { el in
            guard TextEffect.from(el.effect) == effect, var next = el.effect else { return }
            change(&next)
            el.effect = next
        }
    }

    private func dial(_ param: TextEffectParam, of effect: TextEffect) -> some View {
        let shared = TextSelection.effectValue(boxes, param)
        let value = shared ?? effect.defaultValue(param) ?? 0
        let number = param == .direction ? "\(Int(value.rounded()))°" : "\(Int(value.rounded()))"
        let readout = shared == nil ? TypeReadouts.mixed : number
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(param.label).font(.subheadline)
                Spacer()
                Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            // Named and read out on the slider itself, not beside it.
            .accessibilityHidden(true)
            Slider(value: Binding(
                get: { value },
                set: { v in live(effect) { $0.adjust(param, to: v) } }
            ), in: param.range, step: 1, onEditingChanged: { editing in
                if editing { settleColour() } else { store.commit() }
            })
            .accessibilityLabel("\(effect.displayName) \(param.label.lowercased())")
            .accessibilityValue(readout)
        }
    }

    /// A colour of the effect's own (shadow, glitch), or one that follows
    /// the text until Auto is turned off (splice, echo, highlight).
    private func colorRow(_ label: String, of effect: TextEffect, second: Bool) -> some View {
        let held = TypeReadouts.shared(boxes.map { second ? $0.effect?.color2 : $0.effect?.color }) ?? nil
        let optional = !second && effect.defaultColor == nil
        let ink = TypeReadouts.shared(boxes.map(\.color)).flatMap { $0 } ?? "#1f2430"
        let auto = effect == .highlight ? TextEffect.highlightHex(for: ink) : ink
        let shown = held ?? (second ? effect.defaultColor2 : effect.defaultColor) ?? auto
        return HStack {
            Text(label).font(.subheadline)
            Spacer()
            if optional {
                Toggle("Auto", isOn: Binding(
                    get: { held == nil },
                    set: { on in
                        settleColour()
                        store.updateSelected { el in
                            guard TextEffect.from(el.effect) == effect else { return }
                            el.effect?.setColor(on ? nil : shown)
                        }
                    }))
                    .fixedSize()
                    .accessibilityLabel("Automatic \(effect.displayName.lowercased()) colour")
            }
            ColorPicker("", selection: Binding(
                get: { Color(hex: shown) },
                set: { color in
                    let hex = UIColor(color).hexString
                    live(effect) { $0.setColor(hex, second: second) }
                }), supportsOpacity: false)
                .labelsHidden()
                .disabled(optional && held == nil)
                .accessibilityLabel("\(effect.displayName) \(label.lowercased())")
        }
    }
}

// MARK: - spacing

struct SpacingSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// The letter-spacing slider's ends, worked out once per box and size
    /// so they never move under a drag, and what they were worked out for.
    @State private var letterRange: ClosedRange<Double>?
    @State private var letterRangeFor = ""
    @State private var letterSliding = false
    /// The spacing whose readout was tapped, a value to type for it, and
    /// what is typed so far.
    @State private var typing: TypedSpacing?
    @State private var typedDraft = ""

    /// The spacings a value can be typed for, by the name the alert has.
    private enum TypedSpacing: String {
        case line = "Line height"
        case letter = "Letter spacing"
        case paragraph = "Paragraph spacing"

        /// The alert's title, in the app's words.
        var title: String { tr(rawValue) }

        /// What the alert asks for, in the readout's own terms.
        var message: String {
            switch self {
            case .line: return tr("A multiple of the type size, 0.5 to 2.5.")
            case .letter: return tr("A share of the type size in percent, -20 to 80.")
            case .paragraph: return tr("Ems after each line break, 0 to 2.")
            }
        }
    }

    var body: some View {
        NavigationStack {
            typedEntry(Form {
                if let el = store.singleSelection {
                    spacingSections(el)
                    textBoxSection(el)
                    if TextRoles.hasRole(el) { roleSection(el) }
                } else if store.textSelection != nil {
                    severalSections(store.selectedElements)
                }
            })
            .navigationTitle("Spacing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.commit(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
    }

    /// The alert a tapped readout opens: a value typed for that spacing, as
    /// the size's number takes one, set as one step — or nothing, for
    /// anything that is not a number. The Android twin's readouts open the
    /// same, with the same rules (TypeReadouts.typedLetterSpacing and the
    /// rest).
    private func typedEntry<Content: View>(_ content: Content) -> some View {
        content
            .alert(typing?.title ?? "", isPresented: Binding(get: { typing != nil },
                                                                set: { if !$0 { typing = nil } })) {
                TextField(typing?.title ?? "", text: $typedDraft)
                    .keyboardType(typing == .letter ? .numbersAndPunctuation : .decimalPad)
                Button("Set") { setTyped() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(typing?.message ?? "")
            }
            // The editor's plain Delete key must leave the field be.
            .onChange(of: typing != nil) { _, open in store.textFieldOpen = open }
    }

    /// Several boxes' line height, letter spacing — a share of each box's
    /// own type size, so 4% stays 4% at every size — and paragraph spacing,
    /// "Mixed" where they differ, moved or typed to one value on all of them
    /// (TextSelection).
    @ViewBuilder
    private func severalSections(_ boxes: [Element]) -> some View {
        let line = TextSelection.lineHeight(boxes)
        let letter = TextSelection.sharedLetterPercent(boxes)
        let paragraph = TextSelection.paragraphSpacing(boxes)
        let share = TypeReadouts.letterSpacingShare
        Section("Line height") {
            valueSlider(tr("Line height"), value: line ?? 1.25, in: TypeReadouts.lineHeightRange,
                        readout: line.map(TypeReadouts.lineHeight) ?? TypeReadouts.mixed,
                        onReadout: { startTypingSeveral(.line, line.map(TypeReadouts.lineHeight)) }) { v, e in
                e.lineHeight = v
            }
        }
        Section("Letter spacing") {
            valueSlider(tr("Letter spacing"), value: letter ?? 0, in: share.lowerBound * 100...share.upperBound * 100,
                        readout: letter.map { "\(Int($0.rounded()))%" } ?? TypeReadouts.mixed,
                        onReadout: { startTypingSeveral(.letter, letter.map { "\(Int($0.rounded()))" }) }) { v, e in
                e.letterSpacing = TextSelection.letterSpacing(percent: v, for: e)
            }
        }
        Section {
            valueSlider(tr("Paragraph spacing"), value: min(paragraph ?? 0, TypeReadouts.paragraphSpacingRange.upperBound),
                        in: TypeReadouts.paragraphSpacingRange,
                        readout: paragraph.map(TypeReadouts.paragraphSpacing) ?? TypeReadouts.mixed,
                        onReadout: { startTypingSeveral(.paragraph, paragraph.map { "\(Double(($0 * 10).rounded()) / 10)" }) }) { v, e in
                e.paragraphSpacing = v < 0.01 ? nil : v
            }
        } header: {
            Text("Paragraph spacing")
        } footer: {
            Text("Extra space after each line break, in ems.")
        }
    }

    /// A readout tapped with several boxes selected: what they share, to
    /// type over, or nothing while they differ.
    private func startTypingSeveral(_ spacing: TypedSpacing, _ shared: String?) {
        typedDraft = shared ?? ""
        typing = spacing
    }

    /// The readout tapped: its value as it reads, to type over.
    private func startTyping(_ spacing: TypedSpacing, _ el: Element) {
        let size = FontLibrary.effectiveFontSize(for: el)
        switch spacing {
        case .line: typedDraft = TypeReadouts.lineHeight(el.lineHeight ?? 1.25)
        case .letter: typedDraft = "\(Int(((el.letterSpacing ?? 0) / max(size, 1) * 100).rounded()))"
        case .paragraph: typedDraft = "\(Double(((el.paragraphSpacing ?? 0) * 10).rounded()) / 10)"
        }
        typing = spacing
    }

    /// The value typed set on the box, as one step, the box measured again.
    private func setTyped() {
        guard let spacing = typing else { return }
        guard let el = store.singleSelection else { return setTypedSeveral(spacing) }
        let size = FontLibrary.effectiveFontSize(for: el)
        switch spacing {
        case .line:
            guard let value = TypeReadouts.typedLineHeight(typedDraft) else { return }
            setSpacing { $0.lineHeight = value }
        case .letter:
            guard let value = TypeReadouts.typedLetterSpacing(typedDraft, size: size) else { return }
            setSpacing { $0.letterSpacing = value }
        case .paragraph:
            guard let value = TypeReadouts.typedParagraphSpacing(typedDraft) else { return }
            setSpacing { $0.paragraphSpacing = value < 0.01 ? nil : value }
        }
    }

    /// The value typed set on every box selected, as one step: letter
    /// spacing typed in percent, each box's share of its own size.
    private func setTypedSeveral(_ spacing: TypedSpacing) {
        switch spacing {
        case .line:
            guard let value = TypeReadouts.typedLineHeight(typedDraft) else { return }
            store.formatTexts(.spacing) { $0.lineHeight = value }
        case .letter:
            // Typed against a size of 100, the spacing is the percentage.
            guard let percent = TypeReadouts.typedLetterSpacing(typedDraft, size: 100) else { return }
            store.formatTexts(.spacing) { $0.letterSpacing = TextSelection.letterSpacing(percent: percent, for: $0) }
        case .paragraph:
            guard let value = TypeReadouts.typedParagraphSpacing(typedDraft) else { return }
            store.formatTexts(.spacing) { $0.paragraphSpacing = value < 0.01 ? nil : value }
        }
    }

    private func setSpacing(_ change: (inout Element) -> Void) {
        store.updateSelected { el in
            change(&el)
            if el.type == .text { el.h = FontLibrary.layoutHeight(for: el) }
        }
    }

    /// What the letter-spacing range is worked out for: the box, its stored
    /// size and whether the type is fitted — not the fitted size itself,
    /// which letter spacing changes as it is dragged.
    private func letterKey(_ el: Element) -> String {
        "\(el.id)|\(el.fontSize ?? 42)|\(el.fitText == true)"
    }

    /// Line height, letter spacing and paragraph spacing, each with its
    /// value beside it and spoken, in the Android twin's words and ranges.
    @ViewBuilder
    private func spacingSections(_ el: Element) -> some View {
        let size = FontLibrary.effectiveFontSize(for: el)
        let tracking = el.letterSpacing ?? 0
        let key = letterKey(el)
        let fresh = TypeReadouts.letterSpacingRange(size: size, current: tracking)
        let range = letterRangeFor == key ? (letterRange ?? fresh) : fresh
        let lineHeight = el.lineHeight ?? 1.25
        let paragraph = min(el.paragraphSpacing ?? 0, TypeReadouts.paragraphSpacingRange.upperBound)
        Section("Line height") {
            valueSlider(tr("Line height"), value: lineHeight, in: TypeReadouts.lineHeightRange,
                        readout: TypeReadouts.lineHeight(lineHeight),
                        onReadout: { startTyping(.line, el) }) { v, e in e.lineHeight = v }
        }
        Section("Letter spacing") {
            valueSlider(tr("Letter spacing"), value: tracking,
                        in: min(range.lowerBound, tracking)...max(range.upperBound, tracking),
                        readout: TypeReadouts.letterSpacing(tracking, size: size),
                        sliding: $letterSliding,
                        onReadout: { startTyping(.letter, el) }) { v, e in e.letterSpacing = v }
        }
        .onChange(of: key, initial: true) { _, next in
            guard !letterSliding else { return }
            letterRangeFor = next
            letterRange = fresh
        }
        Section {
            valueSlider(tr("Paragraph spacing"), value: paragraph, in: TypeReadouts.paragraphSpacingRange,
                        readout: TypeReadouts.paragraphSpacing(paragraph),
                        onReadout: { startTyping(.paragraph, el) }) { v, e in
                e.paragraphSpacing = v < 0.01 ? nil : v
            }
        } header: {
            Text("Paragraph spacing")
        } footer: {
            Text("Extra space after each line break, in ems.")
        }
    }

    /// Fit, vertical alignment, shrink-to-fit and the drop cap. Fitting and
    /// placing mean nothing to words bent round a curve, set along a path or
    /// stood in columns, and a drop cap nothing to a list or a curve, so
    /// those wait — offered still to turn off when they are on.
    private func textBoxSection(_ el: Element) -> some View {
        let bent = TextOutliner.followsAPath(el)
        let capped = el.dropCap == true
        return Section {
            Picker("Vertical alignment", selection: Binding(
                get: { el.vAlign ?? "top" },
                set: { v in store.updateSelected { $0.vAlign = v == "top" ? nil : v } })) {
                Text("Top").tag("top")
                Text("Middle").tag("middle")
                Text("Bottom").tag("bottom")
            }
            .pickerStyle(.segmented)
            .disabled(bent)
            Toggle("Auto-fit text to the box", isOn: Binding(
                get: { el.fitText == true },
                set: { on in
                    store.updateSelected {
                        if on {
                            $0.fitText = true
                        } else {
                            // Keep the size it had fitted to, so
                            // turning it off changes nothing visible.
                            $0.fontSize = FontLibrary.fittingFontSize(for: $0)
                            $0.fitText = nil
                        }
                    }
                }))
            .disabled(bent && el.fitText != true)
            Button("Shrink the box to the text") { store.shrinkWrapText() }
            Toggle("Drop cap", isOn: Binding(
                get: { capped },
                set: { on in
                    store.updateSelected {
                        $0.dropCap = on ? true : nil
                        $0.h = FontLibrary.layoutHeight(for: $0)
                    }
                }))
            .disabled(!capped && (FontLibrary.isList(el) || el.curve != nil))
        } header: {
            Text("Text box")
        } footer: {
            Text(bent
                 ? tr("Fitting and alignment wait while the words follow a curve, a path or stand in columns.")
                 : tr("With auto-fit on, drag the box and the type resizes to fill it; the alignment places shorter text within a taller box."))
        }
    }

    /// What the box is in the document's outline (TextRoles): its Role —
    /// Auto, inferred by size, or a title, a heading at a level, body, a
    /// quote or a caption — which a tagged PDF, a web page and VoiceOver's
    /// heading take; and Read as, how a screen reader takes it in an
    /// export whatever it looks like, Not read leaving it out. Each change
    /// one step, as the Android twin's Text panel rows.
    private func roleSection(_ el: Element) -> some View {
        let inferred = TextRoles.of(TextRoles.with(el, nil), in: store.design)
        return Section {
            Picker("Role", selection: Binding(
                get: { TextRoles.stored(el) ?? "" },
                set: { v in store.updateSelected { $0 = TextRoles.with($0, v.isEmpty ? nil : v) } })) {
                // Auto says what it comes to: "Auto · Heading 1".
                Text(inferred.map { TextRoles.name(nil) + " · " + TextRoles.name($0) } ?? TextRoles.name(nil)).tag("")
                ForEach(TextRoles.roles, id: \.self) { Text(TextRoles.name($0)).tag($0) }
            }
            Picker("Read as", selection: Binding(
                get: { TextRoles.readAs(el) ?? "" },
                set: { v in store.updateSelected { $0 = TextRoles.withReadAs($0, v.isEmpty ? nil : v) } })) {
                Text(TextRoles.readAsName(nil)).tag("")
                ForEach(TextRoles.readChoices, id: \.self) { Text(TextRoles.readAsName($0)).tag($0) }
            }
        } header: {
            Text("Role")
        }
    }

    /// A slider with its value beside it, named and valued for VoiceOver,
    /// and one undo step per drag. The value is a button: tapped, a value
    /// is typed instead (`onReadout`), as the type size's number is.
    private func valueSlider(_ name: String, value: Double, in range: ClosedRange<Double>, readout: String,
                             sliding: Binding<Bool>? = nil, onReadout: @escaping () -> Void,
                             _ set: @escaping (Double, inout Element) -> Void) -> some View {
        HStack(spacing: 12) {
            Slider(value: transientBinding(value, set), in: range, onEditingChanged: { editing in
                sliding?.wrappedValue = editing
                if !editing { store.commit() }
            })
            .accessibilityLabel(name)
            .accessibilityValue(readout)
            .accessibilityAction(named: "Type a value", onReadout)
            Button(action: onReadout) {
                Text(readout)
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 56, alignment: .trailing)
            }
            .buttonStyle(.borderless)
            .accessibilityHidden(true)
        }
    }

    private func transientBinding(_ value: Double,
                                  _ set: @escaping (Double, inout Element) -> Void) -> Binding<Double> {
        Binding(
            get: { value },
            set: { v in
                store.updateSelectedTransient { el in
                    set(v, &el)
                    if el.type == .text { el.h = FontLibrary.layoutHeight(for: el) }
                }
            })
    }
}

// MARK: - image filters

struct FiltersSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]
    /// Selective colour's chosen band, kept while the sheet is open; nil is
    /// the first chip.
    @State private var hueBand: String?
    /// The bands the photo's own colours fall in (PhotoPalette), which the
    /// chips lead with.
    @State private var bandsPresent: [String] = []

    /// A code has to stay crisp to scan: no effects for it, and no Auto
    /// adjust, as it is black and white already.
    private var isCode: Bool {
        CodeGenerator.isCode(store.singleSelection?.src)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    compareButton
                    presetGrid
                    strengthSlider
                    duotoneRow
                    adjustmentDials
                    if !isCode { effectsSection }
                    resetAllButton
                }
                .padding()
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        // A colour well's last change, which has no release to end its step;
        // and Hold to compare let go, should the sheet close under the finger.
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
            store.comparing = false
        }
    }

    /// Hold to compare: while it is held the canvas shows the photo as it
    /// was before its filter, dials, duotone and effects
    /// (PhotoEdits.original) — nothing written — and VoiceOver says so.
    private var compareButton: some View {
        let held = store.comparing
        return Label(held ? PhotoEdits.comparingNote : tr("Hold to compare"), systemImage: "eye")
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(held ? Theme.accent.opacity(0.18) : Color(.systemGray6)))
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 60, perform: {},
                                onPressingChanged: compare)
            .modifier(CompareAccessibility())
    }

    private func compare(_ pressing: Bool) {
        guard store.comparing != pressing else { return }
        store.comparing = pressing
        if pressing { AccessibilityNotification.Announcement(PhotoEdits.comparingNote).post() }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ImageFilterPreset.allCases) { preset in
                let active = ImageFilterPreset.from(store.singleSelection?.filter) == preset
                Button {
                    // The ringed tile again is no change, and no Undo step;
                    // another filter comes in whole.
                    if !active {
                        store.updateSelected {
                            $0.filter = preset.rawValue
                            $0.filterStrength = nil
                        }
                    }
                } label: {
                    VStack(spacing: 6) {
                        filterPreview(preset)
                        Text(preset.displayName).font(.caption)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .stroke(active ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.displayName) filter")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    /// How much of the chosen filter shows, once there is one: live, one
    /// step per drag, and all of it written as none.
    @ViewBuilder
    private var strengthSlider: some View {
        let preset = ImageFilterPreset.from(store.singleSelection?.filter)
        if preset != .none {
            let value = PhotoLook.strength(store.singleSelection?.filterStrength)
            // At rest at full strength, which is written as none.
            PreciseDial(label: tr("%@ strength", preset.displayName), value: (value * 100).rounded(),
                        range: 0...100, rest: 100,
                        live: { v in store.updateSelectedTransient { Self.setStrength(&$0, v) } },
                        done: { store.commit() },
                        set: { v in store.updateSelected { Self.setStrength(&$0, v) } })
        }
    }

    /// A photo's filter strength from a dial's `steps`, 0 to 100: all of
    /// it written as none.
    private static func setStrength(_ el: inout Element, _ steps: Double) {
        guard el.type == .image else { return }
        let strength = steps.rounded() / 100
        el.filterStrength = strength >= 1 ? nil : strength
    }

    /// Every look taken off in one step — filter and its strength, dials,
    /// duotone, straighten, show-whole and the effects — leaving where the
    /// photo sits alone.
    private var resetAllButton: some View {
        Button("Reset photo edits") {
            store.updateSelected { PhotoEdits.reset(&$0) }
        }
        .frame(maxWidth: .infinity)
        .disabled(!(store.singleSelection.map(PhotoEdits.any) ?? false))
    }

    /// Two colours a photo is mapped onto by luminance — the one treatment
    /// that makes an image belong to a brand rather than merely sit next to
    /// one. The document's own colours come first, because those are the ones
    /// it is supposed to match.
    private var duotoneRow: some View {
        let current = store.singleSelection?.duotone
        let docColors = ColorTools.documentColors(store.design, limit: 6)
        let fromDocument: Duotone? = docColors.count >= 2
            ? Duotone(dark: docColors.min { ColorTheory.hsl($0).l < ColorTheory.hsl($1).l } ?? docColors[0],
                      light: docColors.max { ColorTheory.hsl($0).l < ColorTheory.hsl($1).l } ?? docColors[1])
            : nil
        return VStack(alignment: .leading, spacing: 8) {
            Text("Duotone").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    duotoneTile(nil, name: tr("None"), active: current == nil)
                    if let fromDocument {
                        duotoneTile(fromDocument, name: tr("Document"), active: current == fromDocument)
                    }
                    ForEach(Duotone.presets, id: \.name) { preset in
                        duotoneTile(preset.tone, name: preset.name, active: current == preset.tone)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func duotoneTile(_ tone: Duotone?, name: String, active: Bool) -> some View {
        Button {
            store.updateSelected { $0.duotone = tone }
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(tone.map {
                        LinearGradient(colors: [Color(hex: $0.dark), Color(hex: $0.light)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    } ?? LinearGradient(colors: [Color(.systemGray5), Color(.systemGray4)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 62, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
                Text(name).font(.caption2)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 11)
                .stroke(active ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tone == nil ? tr("No duotone") : tr("%@ duotone", name))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// A preset is a look you pick; these are the dials you turn afterwards.
    /// Both are needed — a preset alone cannot rescue an underexposed photo,
    /// and a stack of dials is not a starting point.
    private var adjustmentDials: some View {
        let whole = store.adjustAreaShown == .whole
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Adjust").font(.headline)
                Spacer()
                if !isCode && whole {
                    Button("Auto adjust") { autoAdjust() }
                        .font(.callout)
                        .disabled(store.singleSelection?.src == nil)
                        .accessibilityHint("Sets the blacks, whites and brightness from the photo itself")
                }
                Button("Reset") { store.resetAllDials() }
                .font(.callout)
                .disabled(store.dialsShown?.isNeutral ?? true)
            }
            if !isCode { applyToRow }
            if !isCode { adjustLayerList }
            if !whole && store.adjustAreaShown == .painted {
                Button("Paint more") { if store.paintMoreOnAdjustArea() { dismiss() } }
                    .font(.callout)
            }
            // The dials in Canva's three groups, each in its order.
            dialGroup(tr("Light", context: "photo adjustments"), .light) {
                dial(tr("Brightness"), \.brightness, in: -1...1)
                dial(tr("Contrast"), \.contrast, in: -1...1)
                dial(tr("Highlights"), \.highlights, in: -1...1)
                dial(tr("Shadows"), \.shadows, in: -1...1)
                dial(tr("Whites"), \.whites, in: -1...1)
                dial(tr("Blacks"), \.blacks, in: -1...1)
            }
            dialGroup(tr("Colour"), .colour) {
                dial(tr("Saturation"), \.saturation, in: -1...1)
                dial(tr("Vibrance"), \.vibrance, in: -1...1)
                dial(tr("Warmth"), \.warmth, in: -1...1)
                dial(tr("Tint"), \.tint, in: -1...1)
                if !isCode && whole { selectiveColour }
            }
            dialGroup(tr("Texture"), .texture) {
                dial(tr("Clarity"), \.clarity, in: -1...1)
                dial(tr("Sharpness"), \.sharpness, in: -1...1)
                // An area is never vignetted, on either phone.
                if whole { dial(tr("Vignette"), \.vignette, in: 0...1) }
                dial(tr("Fade"), \.fade, in: 0...1)
            }
            if whole { curveRow }
        }
    }

    /// Apply to: the dials for the whole photo, a painted area — the brush
    /// taken up first, the sheet going meanwhile — the subject or the
    /// background (AreaAdjust).
    private var applyToRow: some View {
        let shown = store.adjustAreaShown
        return VStack(alignment: .leading, spacing: 6) {
            Text("Apply to").font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdjustArea.allCases) { choice in
                        areaChip(choice, chosen: choice == shown)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func areaChip(_ choice: AdjustArea, chosen: Bool) -> some View {
        Button {
            if store.applyAdjust(to: choice) { dismiss() }
        } label: {
            Text(choice.name)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(chosen ? Theme.accent.opacity(0.18) : Color(.systemGray6)))
                .overlay(Capsule().stroke(chosen ? Theme.accent : Theme.hairline, lineWidth: chosen ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The photo's adjusted areas, each to choose for the dials and with a
    /// delete button.
    @ViewBuilder
    private var adjustLayerList: some View {
        let places = store.adjustLayers.map { $0.index }
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(places, id: \.self) { index in adjustLayerRow(index) }
            }
        }
    }

    private func adjustLayerRow(_ index: Int) -> some View {
        let name = store.adjustLayerName(index)
        let chosen = store.adjustTarget == index
        return HStack {
            Button {
                store.adjustTarget = index
            } label: {
                Label(name, systemImage: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chosen ? .isSelected : [])
            Spacer()
            Button(role: .destructive) {
                store.removeAdjustLayer(at: index)
            } label: {
                Image(systemName: "trash").frame(width: 30, height: 30)
            }
            .accessibilityLabel(tr("Delete %@", name))
        }
    }

    /// Selective colour: one hue band at a time — the eight bands as chips,
    /// those the photo's own colours fall in first — and its hue,
    /// saturation and brightness shifted on their own (HueBands), live and
    /// one step a drag. The chosen band is kept while the sheet is open.
    private var selectiveColour: some View {
        let order = HueBands.chipOrder(present: bandsPresent)
        let chosen = hueBand ?? order.first ?? "red"
        let shift = store.singleSelection?.adjustments?.hsl[chosen] ?? .neutral
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(order, id: \.self) { key in bandChip(key, chosen: key == chosen) }
                }
                .padding(.vertical, 2)
            }
            .task(id: store.singleSelection.flatMap(VideoStore.atRest)) { readBands() }
            bandSlider(tr("Hue"), band: chosen, shift: shift, \.h)
            bandSlider(tr("Saturation"), band: chosen, shift: shift, \.s)
            bandSlider(tr("Brightness"), band: chosen, shift: shift, \.l)
        }
    }

    /// The bands the photo's colours fall in, most prominent first, read
    /// off its preview.
    private func readBands() {
        guard let src = store.singleSelection.flatMap(VideoStore.atRest),
              let full = PhotoLibrary.resolve(src) else {
            bandsPresent = []
            return
        }
        bandsPresent = HueBands.present(in: PhotoPalette.extract(from: PhotoLibrary.preview(full, key: src)))
    }

    /// One band's chip: a swatch of its hue and its name, marked when the
    /// band carries a shift.
    private func bandChip(_ key: String, chosen: Bool) -> some View {
        let band = HueBands.bands.first { $0.key == key } ?? HueBands.bands[0]
        let shifted = !(store.singleSelection?.adjustments?.hsl[key]?.isNeutral ?? true)
        return Button {
            hueBand = key
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hue: band.centre / 360, saturation: 0.85, brightness: 0.95))
                    .frame(width: 14, height: 14)
                Text(band.name).font(.callout)
                if shifted { Image(systemName: "circle.fill").font(.system(size: 5)) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(chosen ? Theme.accent.opacity(0.18) : Color(.systemGray6)))
            .overlay(Capsule().stroke(chosen ? Theme.accent : Theme.hairline, lineWidth: chosen ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(band.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// One of the chosen band's three dials, −100 to +100, set as any
    /// other dial is (PreciseDial).
    private func bandSlider(_ label: String, band: String, shift: HueShift,
                            _ key: WritableKeyPath<HueShift, Double>) -> some View {
        let name = HueBands.bands.first { $0.key == band }?.name ?? band
        func shifted(_ v: Double) -> HueShift {
            var next = shift
            next[keyPath: key] = v / 100
            return next
        }
        return PreciseDial(label: label, spoken: tr("%@ %@", name, label),
                           value: (shift[keyPath: key] * 100).rounded(), range: -100...100,
                           live: { v in
                               store.updateSelectedTransient { el in
                                   guard el.type == .image else { return }
                                   el.setHueShift(band, to: shifted(v))
                               }
                           },
                           done: { store.commit() },
                           set: { v in
                               store.updateSelected { el in
                                   guard el.type == .image else { return }
                                   el.setHueShift(band, to: shifted(v))
                               }
                           })
    }

    /// A group of dials under its name — Light, Colour, Texture — with a
    /// Reset that puts back only that group's dials, as one step.
    private func dialGroup<Dials: View>(_ name: String, _ group: DialPrecision.DialGroup,
                                        @ViewBuilder _ dials: () -> Dials) -> some View {
        let moved = DialPrecision.isMoved(store.dialsShown, group)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Reset") {
                    store.resetDials(group)
                }
                .font(.caption)
                .disabled(!moved)
                .accessibilityLabel(tr("Reset %@", name))
            }
            .padding(.top, 4)
            dials()
        }
    }

    /// Blacks, whites and brightness read off the picture's own lightness,
    /// drawn at 64 × 64 (see `PhotoLook.autoAdjust`), as one step with the
    /// other dials kept — none when they are already so.
    private func autoAdjust() {
        guard let photo = store.singleSelection,
              let picture = PhotoLibrary.resolve(VideoStore.atRest(photo)),
              let histogram = PhotoLook.histogram(of: picture) else { return }
        let adjusted = PhotoLook.autoAdjusted(photo.adjustments, histogram: histogram)
        let next = adjusted.isNeutral ? nil : adjusted
        guard next != photo.adjustments else { return }
        store.updateSelected { $0.adjustments = next }
    }

    // MARK: effects

    /// The photo's effects, a chip each — Blur, Pixelate, Focus, Outline,
    /// Glow and, for a still photo, Face retouch — a tap turning one on at its usual setting, or off, as one step;
    /// the dials of each that is on beneath, live and one step per drag.
    /// Blur is the sharpness dial below zero; an outline and a glow are the
    /// one edge, of two kinds, with its own colour well.
    private var effectsSection: some View {
        let photo = store.singleSelection
        let sharpness = photo?.adjustments?.sharpness ?? 0
        let blurred = sharpness < 0
        let focus = photo?.focusBlur
        let edge = photo?.edge
        return VStack(alignment: .leading, spacing: 10) {
            Text("Effects").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    effectChip(tr("Blur"), on: blurred) { el in
                        el.setAdjustment(\.sharpness, to: blurred ? 0 : -PhotoEffects.defaultBlur)
                    }
                    effectChip(tr("Pixelate"), on: photo?.pixelate != nil) { el in
                        el.pixelate = el.pixelate == nil ? PhotoEffects.defaultPixelate : nil
                    }
                    effectChip(tr("Focus"), on: focus != nil) { el in
                        el.focusBlur = el.focusBlur == nil ? FocusBlur() : nil
                    }
                    edgeChip("outline", tr("Outline"), current: edge)
                    edgeChip("glow", tr("Glow"), current: edge)
                    if DesignStore.isStillPhoto(photo) { faceRetouchChip(photo) }
                }
                .padding(.vertical, 2)
            }
            fxTiles(photo)
            HStack(spacing: 10) {
                brushButton(tr("Blur brush"), kind: .blur)
                brushButton(tr("Pixelate brush"), kind: .pixelate)
                if DesignStore.isStillPhoto(photo) { brushButton(tr("Retouch brush"), kind: .smooth) }
            }
            if blurred {
                effectSlider(tr("Blur"), value: -sharpness, in: 0.01...1,
                             readout: "\(Int((-sharpness * 100).rounded()))") { v, el in
                    el.setAdjustment(\.sharpness, to: -max(1, (v * 100).rounded()) / 100)
                }
            }
            if let pixelate = photo?.pixelate {
                effectSlider(tr("Pixel size"), value: pixelate, in: 0.01...1,
                             readout: "\(Int((pixelate * 100).rounded()))") { v, el in
                    el.pixelate = max(1, (v * 100).rounded()) / 100
                }
            }
            if let focus { focusControls(focus) }
            if let edge { edgeControls(edge) }
            if let fx = photo?.fx { fxControls(fx) }
            faceRetouchRows(photo)
        }
    }

    /// A blur or pixelate brushed onto part of the photo: the sheet goes and
    /// the brush is taken up on the canvas (BrushMode.swift).
    private func brushButton(_ name: String, kind: BrushSession.Kind) -> some View {
        Button {
            guard let id = store.singleSelection?.id else { return }
            dismiss()
            store.beginBrush(id, kind: kind)
        } label: {
            Label(name, systemImage: Self.brushSymbol(kind))
                .font(.callout)
        }
        .buttonStyle(.bordered)
        .disabled(store.singleSelection?.type != .image)
    }

    private static func brushSymbol(_ kind: BrushSession.Kind) -> String {
        switch kind {
        case .blur: return "drop"
        case .smooth: return "wand.and.stars"
        default: return "square.grid.3x3"
        }
    }

    /// The fx, a tile each in PhotoFx.kinds' order, each a live thumbnail
    /// of the selected photo with that fx on it — the chosen one at its own
    /// amount and seed, the rest as a tap gives them.
    private func fxTiles(_ photo: Element?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PhotoFx.kinds, id: \.self) { kind in fxTile(kind, photo: photo) }
            }
            .padding(.vertical, 2)
        }
    }

    /// One fx at a time, from one to another keeping the amount and the
    /// seed; a new one at half, from a seed of its own; the ringed tile
    /// again takes it off.
    private func fxTile(_ kind: String, photo: Element?) -> some View {
        let current = photo?.fx
        let on = current?.kind == kind
        let shown = on ? current : PhotoFx(kind: kind, amount: current?.amount ?? PhotoEffects.defaultFx,
                                           seed: current?.seed ?? 1)
        return Button {
            store.updateSelected { el in
                guard el.type == .image else { return }
                if on {
                    el.fx = nil
                } else {
                    el.fx = PhotoFx(kind: kind, amount: el.fx?.amount ?? PhotoEffects.defaultFx,
                                    seed: el.fx?.seed ?? PhotoEffects.newSeed())
                }
            }
        } label: {
            VStack(spacing: 4) {
                fxThumbnail(shown, photo: photo)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.accent : Theme.hairline,
                                                                      lineWidth: on ? 2 : 1))
                Text(PhotoFx.name(kind)).font(.caption).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PhotoFx.name(kind))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// A small copy of the selected photo with `fx` drawn on it.
    private func fxThumbnail(_ fx: PhotoFx?, photo: Element?) -> some View {
        Group {
            if let fx, let src = photo.flatMap(VideoStore.atRest), let full = PhotoLibrary.resolve(src) {
                Image(uiImage: PhotoEffects.fxPreview(PhotoLibrary.preview(full, key: src, maxEdge: 96), fx: fx,
                                                      key: src))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(.systemGray5)
            }
        }
        .frame(width: 64, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// How much of the fx, and Shuffle for another seed — other bands,
    /// strips or grain — where the seed draws any.
    @ViewBuilder
    private func fxControls(_ fx: PhotoFx) -> some View {
        let name = PhotoFx.name(fx.kind)
        effectSlider(tr("%@ amount", name), value: fx.share, in: 0.01...1,
                     readout: "\(Int((fx.share * 100).rounded()))") { v, el in
            el.fx?.amount = max(1, (v * 100).rounded()) / 100
        }
        if PhotoFx.seeded.contains(fx.kind) {
            Button {
                store.updateSelected { $0.fx?.seed = PhotoEffects.newSeed() }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .font(.callout)
        }
        if fx.kind == "posterize" { colourMixRow(fx) }
    }

    /// Posterize's Colour mix, as on the Android twin: None, each brand
    /// palette of two colours or more, and the design's own colours ("In
    /// this design") — a tap maps the photo's colours to the nearest of
    /// them (PhotoFx `colours`, Canva's ColorMix), at most
    /// PhotoFx.maxColours of them. No row when there is nothing to choose.
    @ViewBuilder
    private func colourMixRow(_ fx: PhotoFx) -> some View {
        let choices = Self.colourMixChoices(store.design)
        if choices.count > 1 {
            Text("Colour mix").font(.callout)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                        effectChip(choice.name, on: fx.colours == choice.colours) { $0.fx?.colours = choice.colours }
                    }
                }
            }
        }
    }

    /// The Colour mix choices: None first, then the brand's palettes, then
    /// the design's own colours, each at most PhotoFx.maxColours long.
    private static func colourMixChoices(_ design: Design) -> [(name: String, colours: [String]?)] {
        var choices: [(name: String, colours: [String]?)] = [(tr("None"), nil)]
        for palette in BrandKit.load().palettes where palette.colors.count >= 2 {
            choices.append((palette.name, Array(palette.colors.prefix(PhotoFx.maxColours))))
        }
        let inDesign = Array(ColorTools.documentColors(design).prefix(PhotoFx.maxColours))
        if inDesign.count >= 2 { choices.append((tr("In this design"), inDesign)) }
        return choices
    }

    private func effectChip(_ name: String, on: Bool, _ toggle: @escaping (inout Element) -> Void) -> some View {
        Button {
            store.updateSelected { el in
                guard el.type == .image else { return }
                toggle(&el)
            }
        } label: {
            chipLabel(name, on: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chipLabel(_ name: String, on: Bool) -> some View {
        Text(name)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(on ? Theme.accent.opacity(0.18) : Color(.systemGray6)))
            .overlay(Capsule().stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 2 : 1))
    }

    // MARK: face retouch

    /// Face retouch: on, its faces found once and kept (FaceRetouching.swift),
    /// or off; while they are looked for it says so. Only for a still photo.
    private func faceRetouchChip(_ photo: Element?) -> some View {
        let on = photo?.retouchFace != nil
        let finding = photo != nil && store.findingFaces == photo?.id
        return Button {
            guard let id = photo?.id else { return }
            if on {
                store.turnOffFaceRetouch()
            } else {
                store.turnOnFaceRetouch(id)
            }
        } label: {
            chipLabel(finding ? tr("Finding faces…") : tr("Face retouch"), on: on)
        }
        .buttonStyle(.plain)
        .disabled(finding)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Under the effects: how much the faces are smoothed, while it is on;
    /// and, when none were found, that said, with the Retouch brush to
    /// smooth by hand.
    @ViewBuilder
    private func faceRetouchRows(_ photo: Element?) -> some View {
        if let retouch = photo?.retouchFace {
            effectSlider(tr("Face retouch"), value: retouch.amount, in: 0...1,
                         readout: "\(Int((retouch.amount * 100).rounded()))") { v, el in
                el = FaceRetouch.withAmount(el, Self.hundredths(v))
            }
        } else if let photo, store.noFacesIn == photo.id {
            HStack(spacing: 10) {
                Label("No faces found", systemImage: "face.dashed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                brushButton(tr("Retouch brush"), kind: .smooth)
            }
        }
    }

    /// An outline or a glow; from one kind to the other keeps the size and
    /// colour.
    private func edgeChip(_ kind: String, _ name: String, current edge: PhotoEdge?) -> some View {
        let on = edge.map { ($0.kind == "glow") == (kind == "glow") } ?? false
        return effectChip(name, on: on) { el in
            if on {
                el.edge = nil
            } else if var mine = el.edge {
                mine.kind = kind
                el.edge = mine
            } else {
                el.edge = PhotoEdge(kind: kind, color: kind == "glow" ? PhotoEffects.glowColour : "#ffffff")
            }
        }
    }

    /// A share to the hundredth, as the sliders step.
    private static func hundredths(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    private static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    @ViewBuilder
    private func focusControls(_ focus: FocusBlur) -> some View {
        effectSlider(tr("Focus size"), value: focus.radius, in: 0...1, readout: Self.percent(focus.radius)) { v, el in
            el.focusBlur?.radius = Self.hundredths(v)
        }
        effectSlider(tr("Background blur"), value: focus.amount, in: 0.01...1,
                     readout: "\(Int((focus.amount * 100).rounded()))") { v, el in
            el.focusBlur?.amount = max(0.01, Self.hundredths(v))
        }
        effectSlider(tr("Focus across"), value: focus.x, in: 0...1, readout: Self.percent(focus.x)) { v, el in
            el.focusBlur?.x = Self.hundredths(v)
        }
        effectSlider(tr("Focus down"), value: focus.y, in: 0...1, readout: Self.percent(focus.y)) { v, el in
            el.focusBlur?.y = Self.hundredths(v)
        }
        Toggle("Keep the subject sharp", isOn: Binding(
            get: { focus.subject },
            set: { on in store.updateSelected { $0.focusBlur?.subject = on } }))
            .font(.subheadline)
    }

    @ViewBuilder
    private func edgeControls(_ edge: PhotoEdge) -> some View {
        let glow = PhotoEffects.isGlow(edge)
        let colour = glow ? tr("Glow colour") : tr("Outline colour")
        effectSlider(glow ? tr("Glow size") : tr("Outline size"), value: edge.width, in: 1...100,
                     readout: "\(Int(edge.width.rounded()))") { v, el in
            el.edge?.width = v.rounded()
        }
        HStack {
            Text(colour).font(.subheadline)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(hex: edge.color) },
                set: { color in
                    let hex = UIColor(color).hexString
                    store.updateSelectedTransient { $0.edge?.color = hex }
                }), supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel(colour)
        }
    }

    /// A named slider with its readout, live under the thumb and one undo
    /// step when let go.
    private func effectSlider(_ label: String, value: Double, in range: ClosedRange<Double>, readout: String,
                              _ set: @escaping (Double, inout Element) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(readout)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: Binding(
                get: { value },
                set: { v in
                    store.updateSelectedTransient { el in
                        guard el.type == .image else { return }
                        set(v, &el)
                    }
                }
            ), in: range, onEditingChanged: { editing in
                if !editing { store.commit() }
            })
            .accessibilityLabel(label)
            .accessibilityValue(readout)
        }
    }

    /// Tone curves as named presets — the five-point curves a photographer
    /// reaches for, chosen rather than dragged on a phone-sized graph.
    private var curveRow: some View {
        let current = store.singleSelection?.adjustments?.curve
        return HStack {
            Text("Tone curve").font(.subheadline)
            Spacer()
            Picker("Tone curve", selection: Binding(
                get: { current ?? "" },
                set: { id in
                    store.updateSelected { el in
                        var adjustments = el.adjustments ?? .neutral
                        adjustments.curve = id.isEmpty ? nil : id
                        el.adjustments = adjustments.isNeutral ? nil : adjustments
                    }
                })) {
                Text("None").tag("")
                ForEach(ToneCurve.presets) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
        }
    }

    /// One dial in steps (DialPrecision): live and one step a drag; a
    /// number typed, a reset or a VoiceOver step one step each.
    private func dial(_ label: String, _ key: WritableKeyPath<Adjustments, Double>,
                      in range: ClosedRange<Double>) -> some View {
        let current = store.dialsShown ?? .neutral
        return PreciseDial(label: label, value: (current[keyPath: key] * 100).rounded(),
                           range: DialPrecision.steps(range),
                           live: { v in store.setDial(key, to: v / 100, live: true) },
                           done: { store.commit() },
                           set: { v in store.setDial(key, to: v / 100, live: false) })
    }

    private func filterPreview(_ preset: ImageFilterPreset) -> some View {
        Group {
            if let src = store.singleSelection.flatMap(VideoStore.atRest),
               let full = PhotoLibrary.resolve(src) {
                // Filter a small copy: ten full-size variants of a 1200x900
                // artwork would be ~43 MB for a row of 76pt thumbnails.
                let base = PhotoLibrary.preview(full, key: src)
                // The chosen tile at the photo's strength; the rest as a tap
                // on them gives them, whole.
                let chosen = ImageFilterPreset.from(store.singleSelection?.filter) == preset
                Image(uiImage: ImageFilterEngine.apply(
                    preset,
                    adjustments: store.singleSelection?.adjustments ?? .neutral,
                    duotone: store.singleSelection?.duotone,
                    strength: chosen ? PhotoLook.strength(store.singleSelection?.filterStrength) : 1,
                    to: base, cacheKey: src + "|preview"))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(.systemGray5)
            }
        }
        .frame(width: 76, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Hold to compare as VoiceOver has it: a button to double-tap and hold.
private struct CompareAccessibility: ViewModifier {
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double-tap and hold to see the photo without its edits")
    }
}

// MARK: - crop

struct CropSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let el = store.singleSelection {
                    Section("Zoom") {
                        // As far in as crop mode goes, or further if a trim
                        // has taken it there.
                        Slider(value: cropBinding(el.cropScale ?? 1) { v, e in e.cropScale = v },
                               in: 1...max(Crop.maxZoom, el.cropScale ?? 1))
                        .accessibilityLabel("Zoom")
                        .accessibilityValue(Self.percent(el.cropScale ?? 1))
                    }
                    Section("Horizontal focus") {
                        Slider(value: cropBinding(el.cropX ?? 0.5) { v, e in e.cropX = v }, in: 0...1)
                            .accessibilityLabel("Horizontal focus")
                            .accessibilityValue(Self.percent(el.cropX ?? 0.5))
                    }
                    Section("Vertical focus") {
                        Slider(value: cropBinding(el.cropY ?? 0.5) { v, e in e.cropY = v }, in: 0...1)
                            .accessibilityLabel("Vertical focus")
                            .accessibilityValue(Self.percent(el.cropY ?? 0.5))
                    }
                    Section {
                        // A shortcut into crop mode, where the crop bar's
                        // dial turns the picture live and Done or Cancel
                        // decide — one straighten control, as on the
                        // Android twin's Photo panel.
                        Button { intoCrop(el) } label: {
                            LabeledContent("Straighten", value: Crop.straightenReadout(el.straighten))
                        }
                    } header: {
                        Text("Straighten")
                    } footer: {
                        Text("\(String(format: "%.1f", el.straighten ?? 0))° — the picture turns inside its frame and grows to keep covering it.")
                    }
                    Section("Frame") {
                        // Fill as a verb, the frame filled, not a colour's fill.
                        Picker(tr("Fill", context: "crop"), selection: Binding(
                            get: { el.cropFit == true ? 1 : 0 },
                            set: { choice in store.updateSelected { $0.cropFit = choice == 1 ? true : nil } })) {
                            Text(tr("Fill", context: "crop")).tag(0)
                            Text("Fit").tag(1)
                        }
                        .pickerStyle(.segmented)
                        // A frame locked in position keeps its shape.
                        aspectRow(el)
                            .disabled(el.holdsPlace)
                    }
                    Section {
                        Toggle("Ken Burns drift in video", isOn: Binding(
                            get: { el.kenBurns != nil },
                            set: { on in store.updateSelected { $0.kenBurns = on ? KenBurns() : nil } }))
                        if el.kenBurns != nil {
                            Button("Preview the drift") { store.playPreview() }
                        }
                    } footer: {
                        Text("The photo zooms in slowly over the page's hold, keeping its focus.")
                    }
                    Section {
                        Button {
                            focusOnSubject(el)
                        } label: { Label("Focus on the subject", systemImage: "viewfinder") }
                        Button("Reset crop") {
                            store.updateSelected {
                                $0.cropScale = 1; $0.cropX = 0.5; $0.cropY = 0.5
                                $0.straighten = nil; $0.cropFit = nil
                            }
                        }
                    }
                }
            }
            .navigationTitle("Crop & focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.commit(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func cropBinding(_ value: Double,
                             _ set: @escaping (Double, inout Element) -> Void) -> Binding<Double> {
        Binding(get: { value }, set: { v in store.updateSelectedTransient { set(v, &$0) } })
    }

    /// Crop mode on this photo, the sheet put away — the frame trimmed to
    /// `aspect` there when one is given (setCropAspect), so the crop bar's
    /// chips, dial, Rotate 90 and Flip carry on and Done keeps it all as one
    /// step or Cancel puts it all back, as the Android twin's Photo panel
    /// does.
    private func intoCrop(_ el: Element, _ aspect: CropAspect? = nil, turned: Bool = false) {
        if store.hasPendingChanges { store.commit() }
        dismiss()
        guard store.startCrop(el.id) else { return }
        if let aspect { store.setCropAspect(aspect, turned: turned) }
    }

    /// The frame's shapes, as the crop bar's chips have them (CropAspect):
    /// each a shortcut into crop mode that trims the frame there
    /// (intoCrop) — Free opens it with the frame as it is.
    private func aspectRow(_ el: Element) -> some View {
        let image = PhotoLibrary.resolve(el.src)?.size ?? .zero
        let match = CropAspect.matched(el, image: image)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in
                    aspectButton(el, aspect, match: match)
                }
            }
        }
    }

    /// One of aspectRow's chips: the lit one named the way round the frame
    /// has it, as the crop bar names it (CropRatioChips), and kept that way.
    private func aspectButton(_ el: Element, _ aspect: CropAspect, match: CropAspect.Match) -> some View {
        let lit = aspect == match.aspect
        let turned = lit && match.turned
        return Button(aspect.name(turned: turned)) { intoCrop(el, aspect, turned: turned) }
            .buttonStyle(.bordered)
            .tint(lit ? Theme.accent : .secondary)
            .controlSize(.small)
            .accessibilityAddTraits(lit ? .isSelected : [])
    }

    /// Put the crop's focus where Vision says the subject is, and zoom in a
    /// little if the crop is at rest — a focus point on an uncropped picture
    /// changes nothing visible.
    private func focusOnSubject(_ el: Element) {
        guard let image = PhotoLibrary.resolve(el.src) else { return }
        Task.detached(priority: .userInitiated) {
            let point = SmartCrop.focalPoint(in: image)
            await MainActor.run {
                guard let point else { return }
                store.updateSelected {
                    $0.cropX = point.x
                    $0.cropY = point.y
                    if ($0.cropScale ?? 1) < 1.05 { $0.cropScale = 1.3 }
                }
            }
        }
    }
}

// MARK: - position / arrange

struct PositionSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// How far one tap of an arrow moves the selection, as which of the
    /// design's unit's steps (Units.nudgeSteps): the smallest — 1 px, 0.1
    /// mm — each time the sheet opens, as on the Android twin, and never
    /// saved.
    @State private var nudgeChoice = 0
    @State private var nudges = 0
    /// An arrow held down: its repeats, until it lifts (NudgeRepeat), and
    /// which way it points.
    @State private var nudgeHold: Task<Void, Never>?
    @State private var nudgeHeld: String?
    /// The arrow a finger is on, as its press gesture keeps it: back to nil
    /// the moment the press ends or is cancelled — the Form's scroll or the
    /// sheet's drag taking the touch, a system gesture — so a hold never
    /// runs on with no finger on it.
    @GestureState private var nudgePress: NudgePress? = nil
    @Environment(\.scenePhase) private var scenePhase
    /// Keep proportions as switched in this panel; nil until it is, when it
    /// is what the one selected element starts with (RatioLock.startsOn).
    /// Never saved.
    @State private var keepProportions: Bool?

    private var keepsProportions: Bool {
        keepProportions ?? store.singleSelection.map(RatioLock.startsOn) ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Layer order") {
                    HStack {
                        orderButton(tr("To front"), "square.3.layers.3d.top.filled") { store.reorderSelected(.front) }
                        orderButton(tr("Forward"), "square.2.layers.3d.top.filled") { store.reorderSelected(.forward) }
                        orderButton(tr("Backward"), "square.2.layers.3d.bottom.filled") { store.reorderSelected(.backward) }
                        orderButton(tr("To back"), "square.3.layers.3d.bottom.filled") { store.reorderSelected(.back) }
                    }
                }
                // One thing, or one group as a single box, lines up with the
                // page; several with each other — and the heading says which,
                // in the Android twin's words.
                Section(store.alignsToPage ? tr("Line up with the page") : tr("Line up with each other")) {
                    HStack {
                        orderButton(tr("Left"), "align.horizontal.left") { store.alignSelected(.left) }
                        orderButton(tr("Center"), "align.horizontal.center") { store.alignSelected(.centerX) }
                        orderButton(tr("Right"), "align.horizontal.right") { store.alignSelected(.right) }
                    }
                    HStack {
                        orderButton(tr("Top"), "align.vertical.top") { store.alignSelected(.top) }
                        orderButton(tr("Middle"), "align.vertical.center") { store.alignSelected(.centerY) }
                        orderButton(tr("Bottom"), "align.vertical.bottom") { store.alignSelected(.bottom) }
                    }
                    // Several things centred as one box, keeping their places
                    // relative to each other.
                    Button {
                        store.centreOnPage()
                    } label: {
                        Label("Centre on page", systemImage: "plus.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(store.movableSelectionCount == 0)
                }
                if store.selection.count >= 3 {
                    Section("Distribute evenly") {
                        HStack {
                            orderButton(tr("Horizontally"), "arrow.left.and.right") {
                                store.distributeSelected(.horizontal)
                            }
                            orderButton(tr("Vertically"), "arrow.up.and.down") {
                                store.distributeSelected(.vertical)
                            }
                        }
                        // Distribute skips locked elements, so gate on the
                        // unlocked count — disabled rather than hidden, so the
                        // control doesn't appear and vanish with lock state.
                        .disabled(!store.canDistribute)
                    }
                }
                if store.selection.count >= 2 {
                    Section("Tidy up") {
                        HStack {
                            orderButton(tr("Row"), "rectangle.split.3x1") { store.tidySelected(.row) }
                            orderButton(tr("Column"), "rectangle.split.1x2") { store.tidySelected(.column) }
                            orderButton(tr("Grid"), "rectangle.split.3x3") { store.tidySelected(.grid) }
                        }
                        .disabled(store.movableSelectionCount < 2)
                        if let layout = store.tidyLayout { spacingRows(layout) }
                    }
                }
                nudgeSection
                Section("Flip") {
                    HStack {
                        orderButton(tr("Horizontal"), "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                            store.flipSelected(horizontal: true)
                        }
                        orderButton(tr("Vertical"), "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                            store.flipSelected(horizontal: false)
                        }
                    }
                }
                if let el = store.singleSelection {
                    // A lock, whole or of its position, keeps every number
                    // here as it is.
                    Section("Exact") {
                        lengthRow("X", px: el.x) { v in store.updateSelectedPlacement { $0.x = v } }
                        lengthRow("Y", px: el.y) { v in store.updateSelectedPlacement { $0.y = v } }
                        lengthRow(tr("Width"), px: el.w) { v in setWidth(v, of: el) }
                        // Text has no height to type: it follows its words.
                        if el.type != .text {
                            proportionsToggle
                            lengthRow(tr("Height"), px: el.h) { v in setHeight(v, of: el) }
                        }
                        numberRow(tr("Rotation"), value: el.rotation) { v in store.updateSelectedPlacement { $0.rotation = v } }
                    }
                    .disabled(el.holdsPlace)
                } else if let box = store.selectionBox {
                    selectionExact(box)
                }
            }
            .navigationTitle("Position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        // Another selection starts from its own proportions rule.
        .onChange(of: store.selection) { _, _ in keepProportions = nil }
    }

    /// The selection as one thing: its box moves and scales, and a rotation
    /// turns the whole about the centre. A turned group's Width and Height
    /// are its turned frame's, and a whole group's Turn is its own angle
    /// (groupTurn), which Turn to 0 straightens.
    private func selectionExact(_ box: CGRect) -> some View {
        let frame = store.turnedGroupFrame
        let size = frame?.size ?? box.size
        return Section("Exact (selection)") {
            lengthRow("X", px: box.minX) { v in
                store.setSelectionBox(CGRect(x: v, y: box.minY, width: box.width, height: box.height))
            }
            lengthRow("Y", px: box.minY) { v in
                store.setSelectionBox(CGRect(x: box.minX, y: v, width: box.width, height: box.height))
            }
            // Always scaled evenly, as on the Android twin: a
            // box of several things has no chain to switch off.
            lengthRow(tr("Width"), px: size.width) { v in
                scaleSelection(by: max(RatioLock.minSide, v) / max(size.width, 1), box: box)
            }
            lengthRow(tr("Height"), px: size.height) { v in
                scaleSelection(by: max(RatioLock.minSide, v) / max(size.height, 1), box: box)
            }
            groupTurnRows
        }
        .disabled(store.movableSelectionCount == 0)
    }

    /// The selection scaled evenly by `factor`: a whole group about its
    /// frame's middle, in its own axes, as on the Android twin; else its box
    /// from its top left corner.
    private func scaleSelection(by factor: Double, box: CGRect) {
        if store.selectedGroupTurn != nil {
            store.scaleGroup(by: factor)
        } else {
            store.setSelectionBox(CGRect(x: box.minX, y: box.minY, width: box.width * factor, height: box.height * factor))
        }
    }

    /// A whole group: Turn, its own angle, and Turn to 0 while it is turned.
    /// Several things that are no group: Rotate by.
    @ViewBuilder
    private var groupTurnRows: some View {
        if let turn = store.selectedGroupTurn {
            numberRow(tr("Turn"), value: turn) { v in store.setGroupTurn(v) }
            if turn != 0 {
                Button("Turn to 0") { store.setGroupTurn(0) }
            }
        } else {
            numberRow(tr("Rotate by"), value: 0) { v in store.rotateSelection(by: v) }
        }
    }

    /// The chain between Width and Height: on, either number brings the
    /// other with it in proportion (see RatioLock). Read as "Keep
    /// proportions, on" or "off", as on the Android twin.
    private var proportionsToggle: some View {
        Toggle(isOn: Binding(get: { keepsProportions }, set: { keepProportions = $0 })) {
            Label("Keep proportions", systemImage: "link")
        }
    }

    /// A width typed for one element: with the chain on, the height in
    /// proportion, its turned top-left corner held as a corner drag holds
    /// the opposite one (RatioLock.placed) — as one step either way.
    private func setWidth(_ typed: Double, of el: Element) {
        guard keepsProportions && el.type != .text else {
            store.updateSelectedPlacement { $0.w = max(RatioLock.minSide, typed) }
            return
        }
        place(el, at: RatioLock.size(width: typed, from: CGSize(width: el.w, height: el.h)))
    }

    /// A height typed for one element: the same, the other way round.
    private func setHeight(_ typed: Double, of el: Element) {
        guard keepsProportions else {
            store.updateSelectedPlacement { $0.h = max(RatioLock.minSide, typed) }
            return
        }
        place(el, at: RatioLock.size(height: typed, from: CGSize(width: el.w, height: el.h)))
    }

    private func place(_ el: Element, at size: CGSize) {
        let box = RatioLock.placed(el, at: size)
        store.updateSelectedPlacement {
            $0.x = Double(box.minX)
            $0.y = Double(box.minY)
            $0.w = Double(box.width)
            $0.h = Double(box.height)
        }
    }

    /// The design's steps: 1, 10 or 100 pixels, 0.1, 1 or 10 mm, 0.01, 0.1
    /// or 1 cm or in.
    private var nudgeSteps: [Double] { Units.nudgeSteps(store.design.physicalUnit) }

    /// The step picked, in page pixels.
    private var nudgeStep: Double {
        let steps = nudgeSteps
        return Units.stepPixels(steps[min(max(nudgeChoice, 0), steps.count - 1)], store.design)
    }

    /// The step picked as it reads: "10", "0.1 mm".
    private var nudgeStepName: String { Units.readout(nudgeStep, store.design) + Units.suffix(store.design) }

    /// Arrows that move the selection by one of three steps a tap — 1, 10
    /// or 100 pixels, or the design's own unit's (Units.nudgeSteps) — with
    /// where it is and how big read out live: the precise move a finger
    /// cannot make, and the only one for someone without a keyboard. Held,
    /// an arrow repeats (NudgeRepeat), and the whole hold is one Undo, as
    /// each tap is; locked elements stay put.
    private var nudgeSection: some View {
        Section {
            Picker("Step", selection: $nudgeChoice) {
                ForEach(nudgeSteps.indices, id: \.self) { i in
                    Text(Units.decimal(nudgeSteps[i], unit: store.design.physicalUnit)).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Move by \(nudgeStepName) at a time")
            HStack {
                nudgeButton("arrow.left", "left", dx: -1, dy: 0)
                nudgeButton("arrow.right", "right", dx: 1, dy: 0)
                nudgeButton("arrow.up", "up", dx: 0, dy: -1)
                nudgeButton("arrow.down", "down", dx: 0, dy: 1)
            }
            .disabled(store.movableSelectionCount == 0)
            .opacity(store.movableSelectionCount == 0 ? 0.4 : 1)
            .feel(.impact(weight: .light), trigger: nudges)
            // An arrow held as the sheet goes is let go with it.
            .onDisappear { stopNudging() }
        } header: {
            HStack {
                Text("Nudge")
                Spacer()
                if let readout = nudgeReadout {
                    Text(readout).monospacedDigit()
                }
            }
        }
        .onChange(of: nudgePress) { _, press in pressChanged(to: press) }
        // Or as the app leaves the screen.
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopNudging() } }
    }

    /// An arrow under a finger: which way it points, and its step.
    private struct NudgePress: Equatable {
        let direction: String
        let dx: Double
        let dy: Double
    }

    /// The hold starts as a finger lands on an arrow and stops, as one
    /// step, as the press ends — however it ends.
    private func pressChanged(to press: NudgePress?) {
        guard let press else {
            stopNudging()
            return
        }
        if nudgeHeld != press.direction { stopNudging() }
        startNudging(press.direction, dx: press.dx, dy: press.dy)
    }

    /// "x, y  ·  w × h" of the selection's box, as the Android twin reads
    /// it out: whole pixels, or the design's unit — "12.5, 40  ·  210 × 99
    /// mm".
    private var nudgeReadout: String? {
        guard let box = store.selectionBox else { return nil }
        guard store.design.physicalUnit != nil else {
            return "\(Int(box.minX)), \(Int(box.minY))  ·  \(Int(box.width)) × \(Int(box.height))"
        }
        let at = Units.readout(box.minX, store.design) + ", " + Units.readout(box.minY, store.design)
        return at + "  ·  " + Units.readout(width: box.width, height: box.height, store.design)
    }

    /// One arrow: a step as the finger lands, then, held, the repeats; let
    /// go, the hold is closed as one step. VoiceOver's activation is still
    /// one step at a time.
    private func nudgeButton(_ system: String, _ direction: String, dx: Double, dy: Double) -> some View {
        Image(systemName: system)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(nudgeHeld == direction ? 0.25 : 0.15)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($nudgePress) { _, press, _ in
                        press = NudgePress(direction: direction, dx: dx, dy: dy)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Self.nudgeLabel(direction, nudgeStepName))
            .accessibilityAction { nudgeOnce(dx: dx, dy: dy) }
    }

    /// What VoiceOver calls an arrow: "Nudge left 10".
    private static func nudgeLabel(_ direction: String, _ step: String) -> String {
        switch direction {
        case "left": return tr("Nudge left %@", step)
        case "right": return tr("Nudge right %@", step)
        case "up": return tr("Nudge up %@", step)
        default: return tr("Nudge down %@", step)
        }
    }

    /// A single step, as its own Undo.
    private func nudgeOnce(dx: Double, dy: Double) {
        store.nudgeSelected(dx: dx * nudgeStep, dy: dy * nudgeStep)
        nudges += 1
        announceNudge()
    }

    /// Where it went, said once, rather than every button renamed.
    private func announceNudge() {
        if let readout = nudgeReadout {
            AccessibilityNotification.Announcement(readout).post()
        }
    }

    /// The first step at once, then after NudgeRepeat's pause a step at its
    /// pace, quickening, with a tick felt every tenth — all in one step.
    private func startNudging(_ direction: String, dx: Double, dy: Double) {
        guard nudgeHold == nil, store.movableSelectionCount > 0 else { return }
        nudgeHeld = direction
        let x = dx * nudgeStep, y = dy * nudgeStep
        store.nudgeSelectedTransient(dx: x, dy: y)
        nudges += 1
        nudgeHold = Task { @MainActor in
            var steps = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(NudgeRepeat.delay(afterSteps: steps)))
                guard !Task.isCancelled else { return }
                steps += 1
                store.nudgeSelectedTransient(dx: x, dy: y)
                if NudgeRepeat.ticks(at: steps) { store.buzz(.tick) }
            }
        }
    }

    private func stopNudging() {
        guard let hold = nudgeHold else { return }
        hold.cancel()
        nudgeHold = nil
        nudgeHeld = nil
        store.commit()
        announceNudge()
    }

    /// Spacing after Tidy up: every gap of the tidied row, column or grid
    /// at once, by the slider — live, one Spacing step as it lets go — or
    /// typed in the design's unit. VoiceOver adjusts it a unit at a time.
    @ViewBuilder
    private func spacingRows(_ layout: Geometry.TidyLayout) -> some View {
        let range = Geometry.tidySpacingRange(page: store.pageSize)
        let unitStep = Units.stepPixels(1, store.design)
        let readout = Units.readout(layout.gap, store.design) + Units.suffix(store.design)
        lengthRow(tr("Spacing"), px: layout.gap) { typed in
            store.setTidySpacing(min(max(typed, range.lowerBound), range.upperBound))
        }
        Slider(value: Binding(get: { min(max(layout.gap, range.lowerBound), range.upperBound) },
                              set: { store.setTidySpacingLive($0) }),
               in: range, onEditingChanged: { editing in if !editing { store.commitSpacing() } })
            .accessibilityLabel(Text("Spacing"))
            .accessibilityValue(readout)
            .accessibilityAdjustableAction { direction in
                let next = layout.gap + (direction == .increment ? unitStep : -unitStep)
                store.setTidySpacing(min(max(next, range.lowerBound), range.upperBound))
            }
    }

    private func orderButton(_ label: String, _ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: system)
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
    }

    /// A length on the page: shown and typed in the design's unit when it
    /// has a physical one — "X (mm)", to a tenth of a millimetre or a
    /// hundredth of a centimetre or inch — and handed on in whole page
    /// pixels (Units.pixels), as Android's Units.typedLength makes them.
    private func lengthRow(_ label: String, px: Double, commit: @escaping (Double) -> Void) -> some View {
        let design = store.design
        guard let unit = design.physicalUnit else { return numberRow(label, value: px, commit: commit) }
        let dpi = design.effectiveDPI
        return numberRow("\(label) (\(unit))", value: Units.value(ofPixels: px, unit: unit, dpi: dpi),
                         places: Units.places(unit)) { typed in
            commit(Units.pixels(typed, unit: unit, dpi: dpi))
        }
    }

    private func numberRow(_ label: String, value: Double, places: Int = 1,
                           commit: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: Binding(get: { value }, set: { commit($0) }),
                      format: .number.precision(.fractionLength(0...places)))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }
}

// MARK: - layers

/// Everything on the page, top-most first: drag a row to reorder it, tap
/// to select, the eye to hide and the padlock to lock — each one undo step —
/// and press and hold for Rename…. Elements sharing a group fold into one
/// "Group (n)" row, which opens to list them and drags as one block.
/// Overlapping lists only what overlaps the selection. On a locked page the
/// rows are read only, each with a padlock, under a line with Unlock.
/// Select ticks several rows — buried and hidden ones too — to group,
/// align, lock, hide or delete together, or drag as one block.
/// The search box, the kind chips and All pages list what matches, a
/// section a page (LayerSearch); a row on another page goes there and
/// selects it.
struct LayersSheet: View {
    @Bindable var store: DesignStore
    /// The bar's Align: the Position sheet, with its alignment.
    var onAlign: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var filter: LayerRows.Filter = .all
    /// Select is on: a tap ticks a row (Layers.toggled) rather than taking
    /// it alone, and the bar below works what is ticked.
    @State private var selecting = false
    /// The groups opened to list their members; each starts folded.
    @State private var expanded: Set<String> = []
    /// The element Rename… is naming, and the name being typed.
    @State private var renaming: Element?
    @State private var typedName = ""
    /// The rows' elements a swipe would delete, while it asks first.
    @State private var askingDelete: [String]?
    /// What is searched for, kept while the app runs (LayerSearch.session).
    @State private var search = LayerSearch.session
    /// What the search found, matched a moment after the typing rests.
    @State private var found: [LayerSearch.PageHits] = []
    /// The query last said aloud, so only a new one is.
    @State private var spokenQuery: LayerSearch.Query?

    /// Whether the list shows what the search found rather than the page.
    private var searching: Bool { search.narrows || search.allPages }

    /// What a search runs again on: the query, the list, the page, what is
    /// selected (for Overlapping) and every change to the design.
    private struct SearchKey: Equatable {
        var query: LayerSearch.Query
        var filter: LayerRows.Filter
        var page: Int
        var selection: Set<String>
        var version: Int
    }

    private var searchKey: SearchKey {
        SearchKey(query: search, filter: filter, page: store.pageIndex, selection: store.selection,
                  version: store.historyVersion)
    }

    private var rows: [LayerRows.Row] {
        switch filter {
        case .all:
            return LayerRows.rows(store.page.elements, expanded: expanded)
        case .overlapping:
            return LayerRows.flat(LayerRows.overlapping(store.page.elements, selection: store.selection))
        }
    }

    /// The page's rows, or what the search found, with the search box, the
    /// chips and the scope over them and Select's bar under them.
    private func layerList(_ rows: [LayerRows.Row], locked: Bool) -> some View {
        List {
            if locked { lockedNote }
            if searching {
                foundSections
            } else {
                if rows.isEmpty { emptyState }
                ForEach(rows) { row in
                    rowView(row, in: rows)
                        .moveDisabled(locked || filter != .all || !row.draggable)
                        .deleteDisabled(locked || !row.elements.contains { !$0.locked })
                }
                .onMove(perform: moveAction(rows))
                .onDelete { offsets in delete(offsets.map { rows[$0] }) }
            }
        }
        .environment(\.editMode, .constant(searching ? .inactive : .active))
        .searchable(text: $search.text, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search layers"))
        .task(id: searchKey) { await match() }
        .onChange(of: search) { _, now in LayerSearch.session = now }
        .safeAreaInset(edge: .top) { LayerSearchBar(query: $search, filter: $filter) }
        .safeAreaInset(edge: .bottom) { if selecting { selectBar } }
    }

    var body: some View {
        NavigationStack {
            layerList(rows, locked: store.isPageLocked)
                .navigationTitle("Layers")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarLeading) { selectToggle }
                }
                .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                       presenting: renaming) { el in
                    TextField(madeName(el), text: $typedName)
                    Button("Rename") { store.renameLayer(el.id, to: typedName) }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("Up to \(LayerNames.maxLength) characters. Leave it empty for the name Canvia gives it.")
                }
                .alert((askingDelete?.count ?? 0) > 1 ? tr("Delete these?") : tr("Delete this?"),
                       isPresented: Binding(get: { askingDelete != nil }, set: { if !$0 { askingDelete = nil } }),
                       presenting: askingDelete) { ids in
                    Button("Delete", role: .destructive) { remove(Set(ids)) }
                    Button("Cancel", role: .cancel) {}
                } message: { ids in
                    Text(ids.count > 1 ? tr("Some of them have their position locked.") : tr("Its position is locked."))
                }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    // MARK: search

    /// What the search found, matched LayerSearch.debounceMilliseconds
    /// after the last change — off the main thread for a design of more
    /// than LayerSearch.offMainOver elements — and its count said aloud
    /// when the query is new: "12 layers found on 4 pages".
    private func match() async {
        guard searching else { return }
        try? await Task.sleep(for: .milliseconds(LayerSearch.debounceMilliseconds))
        guard !Task.isCancelled else { return }
        let pages = store.design.pages, current = store.pageIndex, query = search
        let only: Set<String>? = filter == .overlapping
            ? Set(LayerRows.overlapping(store.page.elements, selection: store.selection).map(\.id)) : nil
        let count = pages.reduce(0) { $0 + $1.elements.count }
        let hits: [LayerSearch.PageHits]
        if count > LayerSearch.offMainOver {
            hits = await Task.detached(priority: .userInitiated) {
                LayerSearch.hits(pages, current: current, query: query, only: only)
            }.value
        } else {
            hits = LayerSearch.hits(pages, current: current, query: query, only: only)
        }
        guard !Task.isCancelled else { return }
        found = hits
        if spokenQuery != query {
            spokenQuery = query
            UIAccessibility.post(notification: .announcement,
                                 argument: LayerSearch.spokenCount(hits))
        }
    }

    /// A section a page with hits, "Page 3 - Intro", its rows top-most
    /// first; nothing found, the search's own empty state.
    @ViewBuilder
    private var foundSections: some View {
        let sections = found.filter { $0.page < store.design.pages.count }
        if sections.allSatisfy({ $0.ids.isEmpty }) {
            ContentUnavailableView.search(text: search.text)
                .listRowBackground(Color.clear)
        }
        ForEach(sections) { hits in
            let page = store.design.pages[hits.page]
            let byId = Dictionary(page.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let elements = hits.ids.reversed().compactMap { byId[$0] }
            if !elements.isEmpty {
                Section(LayerSearch.heading(page, number: hits.page + 1)) {
                    ForEach(elements) { el in foundRow(el, page: hits.page) }
                }
            }
        }
    }

    /// A hit's row: on this page as any row of Overlapping, tapped alone;
    /// on another, its name and a tap that goes to that page and selects it
    /// there. A selection stays on one page, so Select refuses it.
    @ViewBuilder
    private func foundRow(_ el: Element, page: Int) -> some View {
        if page == store.pageIndex {
            rowView(.element(el, member: false), in: [])
        } else {
            HStack(spacing: 12) {
                layerThumb(el)
                Text(layerName(el)).lineLimit(1)
                Spacer(minLength: 4)
            }
            .opacity(el.isHidden ? 0.45 : 1)
            .contentShape(Rectangle())
            .onTapGesture { pickOnPage(el, page: page) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { pickOnPage(el, page: page) }
        }
    }

    /// `el` on page `page` selected there, the editor going to that page.
    /// With Select on, a tick that would join it to things ticked on this
    /// page is refused and said — a selection stays on one page — but with
    /// nothing ticked yet it goes there and ticks it, as on the Android
    /// twin.
    private func pickOnPage(_ el: Element, page: Int) {
        guard !selecting || store.selection.isEmpty else {
            store.announce(LayerSearch.onePageNote, undoable: false)
            return
        }
        store.setPage(page)
        store.selectLayer(el.id)
    }

    /// Over a locked page's rows: why nothing here can be changed, and
    /// Unlock.
    private var lockedNote: some View {
        HStack {
            Label(PageLocks.lockedNote, systemImage: "lock.fill")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Unlock") { store.setPageLocked(false) }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
        }
        .moveDisabled(true)
        .deleteDisabled(true)
    }

    @ViewBuilder
    private var emptyState: some View {
        if filter == .overlapping {
            ContentUnavailableView("Select something to see what overlaps it.",
                                   systemImage: "square.on.square.dashed")
                .listRowBackground(Color.clear)
        } else {
            ContentUnavailableView("Nothing on this page yet",
                                   systemImage: "square.3.layers.3d",
                                   description: Text("Everything you add will be listed here, top-most first, and can be dragged into a new order."))
                .listRowBackground(Color.clear)
        }
    }

    /// Dragging reorders the page in All; Overlapping is not the page's
    /// order, so nothing there drags.
    private func moveAction(_ rows: [LayerRows.Row]) -> ((IndexSet, Int) -> Void)? {
        guard filter == .all else { return nil }
        return { source, destination in
            // Select on, a ticked row's handle takes every ticked row.
            let moving = selecting ? Layers.dragged(rows, selection: store.selection, source: source) : source
            store.moveLayers(rows, from: moving, to: destination)
        }
    }

    /// The rows swiped away, as one undo step: every unlocked element they
    /// stand for — a group row its whole group. Something locked in
    /// position among them asks first, as Delete does.
    private func delete(_ picked: [LayerRows.Row]) {
        let removable = picked.flatMap(\.elements).filter { !$0.locked }
        guard !removable.isEmpty else { return }
        if removable.contains(where: { ElementLock.mode(of: $0) == .position }) {
            askingDelete = removable.map(\.id)
        } else {
            remove(Set(removable.map(\.id)))
        }
    }

    private func remove(_ ids: Set<String>) {
        store.applyToPage { page in
            page.elements.removeAll { ids.contains($0.id) }
        }
        store.selection.subtract(ids)
    }

    private func rowView(_ row: LayerRows.Row, in rows: [LayerRows.Row]) -> some View {
        // The group VoiceOver's Move into group above joins; none outside All.
        var above: String?
        if filter == .all, let at = rows.firstIndex(where: { $0.id == row.id }) {
            above = LayerRows.groupAbove(rows, at: at)
        }
        return HStack(spacing: 10) {
            if selecting { tickMark(row) }
            rowContent(row, above: above)
        }
    }

    @ViewBuilder
    private func rowContent(_ row: LayerRows.Row, above: String?) -> some View {
        switch row {
        case .element(let el, let member, let depth):
            elementRow(el, member: member, depth: depth, above: above)
        case .group(let id, let members, let depth):
            groupRow(id, members: members, depth: depth)
        }
    }

    /// Select's circle on a row: filled while all the row stands for is
    /// selected.
    private func tickMark(_ row: LayerRows.Row) -> some View {
        let on = row.elements.allSatisfy { store.selection.contains($0.id) }
        return Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(on ? Theme.accent : Color.secondary)
            .contentShape(Rectangle())
            .onTapGesture { tick(row.id) }
            .accessibilityHidden(true)
    }

    /// Select, in the header: on, each row has a circle and a tap ticks it;
    /// off again, what was ticked stays selected on the canvas.
    private var selectToggle: some View {
        Button {
            selecting.toggle()
        } label: {
            Label("Select", systemImage: selecting ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .disabled(store.isPageLocked)
        .accessibilityLabel("Select several")
        .accessibilityAddTraits(selecting ? .isSelected : [])
    }

    /// Row `rowId` ticked, or unticked (Layers.toggled).
    private func tick(_ rowId: String) {
        guard !store.isPageLocked else { return }
        store.selectLayers(Layers.toggled(rows, selection: store.selection, rowId: rowId))
    }

    /// Under the ticked rows: how many, and Group, Align, Lock or Unlock,
    /// Hide or Show and Delete — each one undo step, through the store's
    /// own calls, as the toolbar's are.
    private var selectBar: some View {
        let picked = store.selectedElements
        return HStack(spacing: 4) {
            Text(trn("%d selected|%d selected", picked.count))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            selectBarButtons(picked)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func selectBarButtons(_ picked: [Element]) -> some View {
        let ids = store.selection
        let allHidden = !picked.isEmpty && picked.allSatisfy(\.isHidden)
        // A locked row is ticked for Unlock only: Align, Hide and Delete pass
        // over it, as on the Android twin.
        let free = Set(picked.filter { !$0.locked }.map(\.id))
        let anyUnlocked = !free.isEmpty
        // With any ticked row locked the button unlocks them all.
        let anyLocked = picked.contains { $0.locked }
        barButton(tr("Group"), "square.on.square") { store.groupSelected() }
            .disabled(!store.canGroup)
        barButton(tr("Align"), "align.horizontal.left") { onAlign() }
            .disabled(!anyUnlocked)
        barButton(anyLocked ? tr("Unlock") : tr("Lock"), anyLocked ? "lock.open" : "lock") {
            store.setLock(ids, anyLocked ? .unlocked : .full)
        }
        .disabled(picked.isEmpty)
        barButton(allHidden ? tr("Show") : tr("Hide"), allHidden ? "eye" : "eye.slash") {
            store.setHidden(free, hidden: !allHidden)
        }
        .disabled(!anyUnlocked)
        barButton(tr("Delete"), "trash") { store.deleteSelected() }
            .disabled(!anyUnlocked)
    }

    private func barButton(_ name: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 36, height: 32)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(name)
    }

    /// An element's row: faded, with its eye struck through, while hidden.
    /// A member of an opened group is indented under it, one step for each
    /// group it is listed inside, and a tap takes it
    /// alone, as it does on a row of Overlapping, which lists elements one
    /// by one — as on the Android twin; any other row's tap takes its group,
    /// as on the canvas.
    private func elementRow(_ el: Element, member: Bool, depth: Int, above: String?) -> some View {
        let name = layerName(el)
        let selected = store.selection.contains(el.id)
        let alone = member || filter == .overlapping || searching
        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                layerThumb(el)
                Text(name).lineLimit(1)
            }
            .opacity(el.isHidden ? 0.45 : 1)
            .padding(.leading, member ? 24 * CGFloat(max(depth, 1)) : 0)
            .accessibilityElement(children: .combine)
            .accessibilityValue([el.isHidden ? tr("Hidden") : nil, lockValue(ElementLock.mode(of: el))]
                .compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { pick(el, alone: alone) }
            .accessibilityAction(named: "Rename…") { startRename(el) }
            .accessibilityActions { membershipActions(el, above: above) }
            Spacer(minLength: 4)
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            rowControls([el.id], hidden: el.isHidden, mode: ElementLock.mode(of: el), name: name)
        }
        .contentShape(Rectangle())
        .onTapGesture { pick(el, alone: alone) }
        .contextMenu {
            Button { startRename(el) } label: { Label("Rename…", systemImage: "pencil") }
        }
    }

    /// VoiceOver's moves of a row across a group's edge, as a drag makes
    /// them: Remove from group for an element in one, and Move into group
    /// above when the row above it at its level is a group's.
    @ViewBuilder
    private func membershipActions(_ el: Element, above: String?) -> some View {
        if el.group != nil {
            Button("Remove from group") { store.removeFromGroup([el.id]) }
        }
        if let above {
            Button("Move into group above") { store.addToGroup([el.id], group: above) }
        }
    }

    /// A group's row, "Group (3)": folded until its disclosure opens it, a
    /// tap takes the whole group, and the eye and padlock work every member.
    /// A group inside an opened one is indented a step for each level, and
    /// its tap takes that group alone.
    private func groupRow(_ id: String, members: [Element], depth: Int) -> some View {
        let open = expanded.contains(id)
        let name = LayerRows.groupName(members.count)
        let ids = Set(members.map(\.id))
        let allHidden = members.allSatisfy(\.isHidden)
        let selected = ids.isSubset(of: store.selection)
        return HStack(spacing: 12) {
            Button {
                if open { expanded.remove(id) } else { expanded.insert(id) }
            } label: {
                Image(systemName: open ? "chevron.down" : "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 20, height: 28)
            }
            .buttonStyle(.borderless)
            .padding(.leading, 24 * CGFloat(depth))
            .accessibilityLabel(open ? tr("Close %@", name) : tr("Open %@", name))
            HStack(spacing: 12) {
                Image(systemName: "square.on.square")
                    .frame(width: 28, height: 28)
                Text(name).lineLimit(1)
            }
            .opacity(allHidden ? 0.45 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { pickGroup(id, members: members, depth: depth) }
            Spacer(minLength: 4)
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            rowControls(ids, hidden: allHidden, mode: Self.sharedLock(members), name: name)
        }
        .contentShape(Rectangle())
        .onTapGesture { pickGroup(id, members: members, depth: depth) }
    }

    /// The eye and the padlock — or, on a locked page, only a padlock that
    /// does nothing, the row read only.
    @ViewBuilder
    private func rowControls(_ ids: Set<String>, hidden: Bool, mode: ElementLock.Mode, name: String) -> some View {
        if store.isPageLocked {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .accessibilityLabel(PageLocks.lockedNote)
        } else {
            eyeButton(ids, hidden: hidden, name: name)
            lockButton(ids, mode: mode, name: name)
        }
    }

    /// Hides what the row stands for, or — when all of it is hidden — shows
    /// it again.
    private func eyeButton(_ ids: Set<String>, hidden: Bool, name: String) -> some View {
        Button { store.setHidden(ids, hidden: !hidden) } label: {
            Image(systemName: hidden ? "eye.slash" : "eye")
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(hidden ? Theme.accent : Color.secondary)
        .accessibilityLabel(hidden ? tr("Show %@", name) : tr("Hide %@", name))
    }

    /// The padlock: the toolbar's Lock menu — Lock, Lock position, Unlock —
    /// for what the row stands for, each one undo step. Closed while all of
    /// it is locked whole, open with the accent while its position is.
    private func lockButton(_ ids: Set<String>, mode: ElementLock.Mode, name: String) -> some View {
        Menu {
            ForEach([ElementLock.Mode.full, .position, .unlocked], id: \.self) { choice in
                Button { store.setLock(ids, choice) } label: {
                    Label(ElementLock.name(choice), systemImage: mode == choice ? "checkmark" : ElementLock.symbol(choice))
                }
            }
        } label: {
            Image(systemName: mode == .unlocked ? "lock.open" : ElementLock.symbol(mode))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(mode == .unlocked ? Color.secondary : Theme.accent)
        .accessibilityLabel("Lock \(name)")
        .accessibilityValue(lockValue(mode) ?? tr("Unlocked"))
    }

    /// How a row's lock is read out: nil unlocked.
    private func lockValue(_ mode: ElementLock.Mode) -> String? {
        switch mode {
        case .unlocked: return nil
        case .position: return tr("Position locked")
        case .full: return tr("Locked")
        }
    }

    /// A group row's lock: the members' one lock when they share it, else
    /// none, so the menu offers to lock them all.
    private static func sharedLock(_ members: [Element]) -> ElementLock.Mode {
        let modes = Set(members.map { ElementLock.mode(of: $0) })
        return modes.count == 1 ? modes.first ?? .unlocked : .unlocked
    }

    /// A row tapped selects what it stands for; nothing, on a locked page.
    private func pick(_ el: Element, alone: Bool) {
        guard !store.isPageLocked else { return }
        if selecting { return tick(el.id) }
        if alone { store.selectLayer(el.id) } else { store.select(el.id) }
    }

    private func pickGroup(_ id: String, members: [Element], depth: Int) {
        guard !store.isPageLocked else { return }
        if selecting { return tick("group:" + id) }
        if depth > 0 {
            store.selectLayers(Set(members.map(\.id)))
        } else if let top = members.first {
            store.select(top.id)
        }
    }

    private func startRename(_ el: Element) {
        guard !store.isPageLocked else { return }
        typedName = el.layerName ?? ""
        renaming = el
    }

    /// The name VoiceOver and the snap guides use too: the one given it in
    /// Rename…, else "Heading: SALE", "Red oval", "QR code" — as the Android
    /// twin's Layers panel.
    private func layerName(_ el: Element) -> String {
        ElementNames.name(of: el)
    }

    /// The name the element would have without one of its own: what Rename…
    /// shows in an empty field.
    private func madeName(_ el: Element) -> String {
        var plain = el
        plain.layerName = nil
        return ElementNames.name(of: plain)
    }

    @ViewBuilder
    private func layerThumb(_ el: Element) -> some View {
        switch el.type {
        case .shape:
            LibraryShape(definition: ContentLibrary.shape(el.shapeId), cornerRadius: 0)
                .fill(Color(hex: el.fill?.primaryColor ?? "#888888"))
                .frame(width: 28, height: 28)
        case .image:
            if let ui = PhotoLibrary.resolve(VideoStore.atRest(el)) {
                Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo").frame(width: 28, height: 28)
            }
        case .sticker:
            Text(el.glyph ?? "⭐").font(.title3).frame(minWidth: 28, minHeight: 28)
        case .text:
            Text("T").font(.body.weight(.bold))
                .foregroundStyle(Color(hex: el.color ?? "#333333"))
                .frame(width: 28, height: 28)
        case .line:
            Rectangle().fill(Color(hex: el.color ?? "#333333"))
                .frame(width: 24, height: 3).frame(width: 28, height: 28)
        }
    }
}

// MARK: - resize design

/// A size typed for Resize: checked against the range the app makes, said
/// under the fields, and applied only when both sides are in it — as the
/// custom-size sheet on Home checks it, and as the Android twin's Resize
/// does. It used to clamp whatever was typed, and make a size nobody asked
/// for. Typed in px, in, mm or cm; a physical unit is made at 300 dpi.
private struct ResizeCustomSection: View {
    @Binding var customW: String
    @Binding var customH: String
    @Binding var unit: String
    let onResize: (Double, Double) -> Void

    var body: some View {
        let size = CustomSizes.size(width: customW, height: customH, unit: unit)
        let typedWrong = !customW.isEmpty && CustomSizes.side(customW, unit: unit) == nil
            || !customH.isEmpty && CustomSizes.side(customH, unit: unit) == nil
        return Section {
            UnitPicker(unit: $unit)
                .onChange(of: unit) { old, new in
                    customW = CustomSizes.convert(customW, from: old, to: new)
                    customH = CustomSizes.convert(customH, from: old, to: new)
                }
            HStack {
                TextField("Width", text: $customW).keyboardType(unit == "px" ? .numberPad : .decimalPad)
                swapButton
                TextField("Height", text: $customH).keyboardType(unit == "px" ? .numberPad : .decimalPad)
                Text(unit).foregroundStyle(.secondary)
            }
            Button(CustomSizes.resizeTitle(width: customW, height: customH, unit: unit)) {
                guard let size else { return }
                onResize(size.width, size.height)
            }
            .fontWeight(.semibold)
            .disabled(size == nil)
        } header: {
            Text("Custom")
        } footer: {
            Text(typedWrong ? CustomSizes.outOfRangeText : tr("Each side %@.", CustomSizes.rangeText))
                .foregroundStyle(typedWrong ? Color(.systemRed) : Color.secondary)
        }
        // Digits only, five at most, however they arrive; one decimal point
        // in a physical unit.
        .onChange(of: customW) { _, typed in
            let clean = CustomSizes.field(typed, unit: unit)
            if clean != typed { customW = clean }
        }
        .onChange(of: customH) { _, typed in
            let clean = CustomSizes.field(typed, unit: unit)
            if clean != typed { customH = clean }
        }
    }

    /// Between the fields: the width and the height typed, swapped.
    private var swapButton: some View {
        Button {
            let width = customW
            customW = customH
            customH = width
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Swap width and height")
    }
}

/// Two ways to a new size: resize this design in place — reflowed or
/// scaled, the whole of it or this page — or Copy & resize, which ticks any
/// number of sizes and makes a new design at each, leaving this one alone.
/// Copy & resize is where it opens when there is anything on the page.
struct ResizeSheet: View {
    @Bindable var store: DesignStore
    /// Told the copies Copy & resize made, for the editor's "Made 3 resized
    /// copies".
    var onCopies: ([Design]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copying: Bool
    @State private var customW = ""
    @State private var customH = ""
    @State private var unit = "px"
    @State private var reflow = true
    @State private var pageOnly = false
    /// The preset chosen to resize to, by id; nil while the size is the
    /// one typed under Custom. It opens on the page's own size's preset.
    @State private var chosen: String?
    /// Portrait | Landscape picked for the chosen preset: it turned to stand
    /// that way (CustomSizes.turned); nil as the preset is listed.
    @State private var landscape: Bool?
    @State private var ticked: [ResizeTarget] = []
    @State private var progress: String?
    @State private var failed = false
    @State private var task: Task<Void, Never>?

    /// `copying` picks the mode it opens in; nil is Copy & resize when the
    /// design has anything on it, else Resize this design.
    init(store: DesignStore, copying: Bool? = nil, onCopies: @escaping ([Design]) -> Void = { _ in }) {
        _store = Bindable(wrappedValue: store)
        self.onCopies = onCopies
        _copying = State(initialValue: copying ?? CopyResize.hasContent(store.design))
        // In the design's own unit, at its size as it reads — a poster at
        // 96 dpi is 420 × 594 mm — as Android's Resize fills it. Set here
        // rather than on appear, so the unit picker's change never converts
        // the fields a second time; a size typed on paper is made at 300 dpi.
        let own = store.design.physicalUnit ?? "px"
        let dpi = store.design.effectiveDPI
        _unit = State(initialValue: own)
        _customW = State(initialValue: Units.format(Units.value(ofPixels: store.pageWidth, unit: own, dpi: dpi), unit: own))
        _customH = State(initialValue: Units.format(Units.value(ofPixels: store.pageHeight, unit: own, dpi: dpi), unit: own))
        // The preset the page is now, either way round, in the design's
        // unit — turned, when it stands the other way — as on Android.
        let w = store.pageWidth, h = store.pageHeight
        let match = SizePreset.all.first { p in
            p.unit == store.design.physicalUnit && ((p.w == w && p.h == h) || (p.w == h && p.h == w))
        }
        _chosen = State(initialValue: match?.id)
        _landscape = State(initialValue: match.flatMap { $0.w != w ? CustomSizes.isLandscape(width: w, height: h) : nil })
    }

    private func resize(_ w: Double, _ h: Double, units: UnitChoice) {
        if pageOnly {
            store.resizePage(width: w, height: h, reflow: reflow)
        } else if reflow {
            store.magicResize(width: w, height: h, units: units)
        } else {
            store.resizeDesign(width: w, height: h, units: units)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: $copying) {
                        Text("Resize this design").tag(false)
                        Text("Copy & resize").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(copying
                         ? tr("A new design for each size ticked, reflowed to fit, in the same folder. This design stays as it is.")
                         : tr("Changes this design. Undo brings it back."))
                }
                if copying {
                    CopyResizeRows(ticked: $ticked)
                } else {
                    resizeRows
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if copying {
                    CopyResizeButton(count: ticked.count, progress: progress, failed: failed) { makeCopies() }
                }
            }
            .navigationTitle(copying ? tr("Copy & resize") : tr("Resize design"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled(progress != nil)
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private var resizeRows: some View {
        Section {
            Picker("How", selection: $reflow) {
                Text("Reflow").tag(true)
                Text("Scale").tag(false)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(reflow
                 ? tr("Reflow keeps each element's place on the new page — a footer stays at the foot, a corner logo in its corner — and sizes follow the smaller ratio.")
                 : tr("Scale shrinks or grows everything uniformly to fit, centred, leaving margins when the shape changes."))
        }
        if store.design.pages.count > 1 {
            Section {
                Picker("Apply to", selection: $pageOnly) {
                    Text("Whole design").tag(false)
                    Text("This page only").tag(true)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(pageOnly
                     ? tr("Pages can have sizes of their own — a story after a square post. Exports, the video and the PDF keep each page's shape.")
                     : tr("Every page takes the new size; pages that had their own size join it."))
            }
        }
        Section("Presets") {
            orientationRow
            ForEach(SizePreset.all) { preset in
                presetRow(preset)
            }
            if let preset = chosenPreset {
                presetButton(preset)
            }
        }
        // A size typed under Custom is not remembered among the recent
        // sizes: only a preset is, on both phones.
        ResizeCustomSection(customW: $customW, customH: $customH, unit: $unit) { w, h in
            resize(w, h, units: .typed(unit))
            dismiss()
        }
        .onChange(of: customW) { _, _ in chosen = nil }
        .onChange(of: customH) { _, _ in chosen = nil }
    }

    private var chosenPreset: SizePreset? {
        chosen.flatMap { id in SizePreset.all.first { $0.id == id } }
    }

    /// `preset` turned the way picked for it, or as it is listed.
    private func turnedSize(_ preset: SizePreset) -> (width: Double, height: Double) {
        landscape.map { CustomSizes.turned(width: preset.w, height: preset.h, landscape: $0) }
            ?? (width: preset.w, height: preset.h)
    }

    /// The size Resize makes: the chosen preset, turned the way picked, or
    /// the size typed under Custom.
    private var target: (width: Double, height: Double)? {
        guard let preset = chosenPreset else { return CustomSizes.size(width: customW, height: customH, unit: unit) }
        return turnedSize(preset)
    }

    /// Portrait | Landscape, under the Presets heading: the way the size
    /// Resize makes stands — the chosen preset, or the size typed — and off
    /// for a square. Picking the other way turns the chosen preset (A4 to
    /// 297 × 210 mm) or swaps the fields typed. Both phones' rule.
    private var orientationRow: some View {
        let wide = target.flatMap { CustomSizes.isLandscape(width: $0.width, height: $0.height) }
        return Picker(selection: Binding(get: { wide }, set: { turn(to: $0) })) {
            Text("Portrait").tag(Bool?.some(false))
            Text("Landscape").tag(Bool?.some(true))
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .disabled(wide == nil)
    }

    private func turn(to pick: Bool?) {
        guard let pick else { return }
        if chosen != nil {
            landscape = pick
        } else {
            let fields = CustomSizes.turnedFields(width: customW, height: customH, landscape: pick)
            customW = fields.width
            customH = fields.height
        }
    }

    /// A preset to resize to: a tap chooses it as it is listed, for
    /// Portrait | Landscape to turn; the chosen one is ticked, at the size
    /// it will make.
    private func presetRow(_ preset: SizePreset) -> some View {
        let picked = chosen == preset.id
        let size = picked ? turnedSize(preset) : (width: preset.w, height: preset.h)
        return Button {
            chosen = preset.id
            landscape = nil
        } label: {
            HStack {
                Label(preset.name, systemImage: preset.icon)
                Spacer()
                Text(Units.dimensions(width: size.width, height: size.height, unit: preset.unit, dpi: preset.dpi))
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                if picked {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// Resize to the chosen preset — one step, Reflow or Scale, the whole
    /// design or this page — and it joins the recent sizes as it was made,
    /// turned if it was turned.
    private func presetButton(_ preset: SizePreset) -> some View {
        let size = turnedSize(preset)
        let title = Units.dimensions(width: size.width, height: size.height, unit: preset.unit, dpi: preset.dpi)
        return Button(tr("Resize to %@", title)) {
            resize(size.width, size.height, units: UnitChoice(unit: preset.unit, dpi: preset.dpi))
            CustomSizes.remember(width: size.width, height: size.height)
            dismiss()
        }
        .fontWeight(.semibold)
    }

    /// One copy per size ticked, of the design as it is on screen; this
    /// design is not touched and no undo step is recorded.
    private func makeCopies() {
        store.finishCrop()
        store.endTextEdit()
        let source = store.design
        let targets = ticked
        failed = false
        task = Task { @MainActor in
            defer { progress = nil; task = nil }
            do {
                let made = try await CopyResize.make(source, targets: targets, progress: { progress = $0 })
                // None saved is said, and the sheet stays to try again.
                guard !made.isEmpty else { failed = true; return }
                onCopies(made)
                dismiss()
            } catch {
                // Cancelled is the sheet going: nothing to say.
                if !(error is CancellationError) { failed = true }
            }
        }
    }
}

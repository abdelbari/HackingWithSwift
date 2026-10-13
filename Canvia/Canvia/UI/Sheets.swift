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
        .accessibilityLabel("\(preset.name), \(kind) gradient")
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
struct EffectsSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    private var spec: TextEffectSpec? { store.singleSelection?.effect }
    private var current: TextEffect { TextEffect.from(spec) }

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
        let active = current == effect
        return Button {
            settleColour()
            store.updateSelected {
                guard $0.effect?.type != effect.rawValue else { return }
                $0.effect = TextEffectSpec(type: effect.rawValue)
            }
        } label: {
            VStack(spacing: 6) {
                effectPreview(effect)
                    .frame(width: 64, height: 44)
                Text(effect.displayName).font(.system(size: 11))
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
                .disabled(spec?.isAtDefaults ?? true)
            }
            ForEach(effect.params) { param in
                dial(param, of: effect)
            }
            if effect.takesColor {
                colorRow("Colour", of: effect, second: false)
            }
            if effect.defaultColor2 != nil {
                colorRow("Second colour", of: effect, second: true)
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
        let value = TextEffect.value(spec, param, for: effect)
        let readout = param == .direction ? "\(Int(value.rounded()))°" : "\(Int(value.rounded()))"
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
        let held = second ? spec?.color2 : spec?.color
        let optional = !second && effect.defaultColor == nil
        let ink = store.singleSelection?.color ?? "#1f2430"
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

    var body: some View {
        NavigationStack {
            Form {
                if let el = store.singleSelection {
                    spacingSections(el)
                    textBoxSection(el)
                }
            }
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
            valueSlider("Line height", value: lineHeight, in: TypeReadouts.lineHeightRange,
                        readout: TypeReadouts.lineHeight(lineHeight)) { v, e in e.lineHeight = v }
        }
        Section("Letter spacing") {
            valueSlider("Letter spacing", value: tracking,
                        in: min(range.lowerBound, tracking)...max(range.upperBound, tracking),
                        readout: TypeReadouts.letterSpacing(tracking, size: size),
                        sliding: $letterSliding) { v, e in e.letterSpacing = v }
        }
        .onChange(of: key, initial: true) { _, next in
            guard !letterSliding else { return }
            letterRangeFor = next
            letterRange = fresh
        }
        Section {
            valueSlider("Paragraph spacing", value: paragraph, in: TypeReadouts.paragraphSpacingRange,
                        readout: TypeReadouts.paragraphSpacing(paragraph)) { v, e in
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
                 ? "Fitting and alignment wait while the words follow a curve, a path or stand in columns."
                 : "With auto-fit on, drag the box and the type resizes to fill it; the alignment places shorter text within a taller box.")
        }
    }

    /// A slider with its value beside it, named and valued for VoiceOver,
    /// and one undo step per drag.
    private func valueSlider(_ name: String, value: Double, in range: ClosedRange<Double>, readout: String,
                             sliding: Binding<Bool>? = nil,
                             _ set: @escaping (Double, inout Element) -> Void) -> some View {
        HStack(spacing: 12) {
            Slider(value: transientBinding(value, set), in: range, onEditingChanged: { editing in
                sliding?.wrappedValue = editing
                if !editing { store.commit() }
            })
            .accessibilityLabel(name)
            .accessibilityValue(readout)
            Text(readout)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)
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

    /// A code has to stay crisp to scan: no effects for it, and no Auto
    /// adjust, as it is black and white already.
    private var isCode: Bool {
        CodeGenerator.payload(from: store.singleSelection?.src ?? "") != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
        // A colour well's last change, which has no release to end its step.
        .onDisappear { if store.hasPendingChanges { store.commit() } }
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
            effectSlider("\(preset.displayName) strength", value: value, in: 0...1,
                         readout: "\(Int((value * 100).rounded()))%") { v, el in
                let strength = (v * 100).rounded() / 100
                el.filterStrength = strength >= 1 ? nil : strength
            }
        }
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
                    duotoneTile(nil, name: "None", active: current == nil)
                    if let fromDocument {
                        duotoneTile(fromDocument, name: "Document", active: current == fromDocument)
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
        .accessibilityLabel(tone == nil ? "No duotone" : "\(name) duotone")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// A preset is a look you pick; these are the dials you turn afterwards.
    /// Both are needed — a preset alone cannot rescue an underexposed photo,
    /// and a stack of dials is not a starting point.
    private var adjustmentDials: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Adjust").font(.headline)
                Spacer()
                if !isCode {
                    Button("Auto adjust") { autoAdjust() }
                        .font(.callout)
                        .disabled(store.singleSelection?.src == nil)
                        .accessibilityHint("Sets the blacks, whites and brightness from the photo itself")
                }
                Button("Reset") {
                    store.updateSelected { $0.adjustments = nil }
                }
                .font(.callout)
                .disabled(store.singleSelection?.adjustments?.isNeutral ?? true)
            }
            // The dials in Canva's three groups, each in its order.
            dialGroup("Light") {
                dial("Brightness", \.brightness, in: -1...1)
                dial("Contrast", \.contrast, in: -1...1)
                dial("Highlights", \.highlights, in: -1...1)
                dial("Shadows", \.shadows, in: -1...1)
                dial("Whites", \.whites, in: -1...1)
                dial("Blacks", \.blacks, in: -1...1)
            }
            dialGroup("Colour") {
                dial("Saturation", \.saturation, in: -1...1)
                dial("Vibrance", \.vibrance, in: -1...1)
                dial("Warmth", \.warmth, in: -1...1)
                dial("Tint", \.tint, in: -1...1)
            }
            dialGroup("Texture") {
                dial("Clarity", \.clarity, in: -1...1)
                dial("Sharpness", \.sharpness, in: -1...1)
                dial("Vignette", \.vignette, in: 0...1)
                dial("Fade", \.fade, in: 0...1)
            }
            curveRow
        }
    }

    /// A group of dials under its name — Light, Colour, Texture.
    private func dialGroup<Dials: View>(_ name: String, @ViewBuilder _ dials: () -> Dials) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
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

    /// The photo's effects, a chip each — Blur, Pixelate, Focus, Outline and
    /// Glow — a tap turning one on at its usual setting, or off, as one step;
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
                    effectChip("Blur", on: blurred) { el in
                        el.setAdjustment(\.sharpness, to: blurred ? 0 : -PhotoEffects.defaultBlur)
                    }
                    effectChip("Pixelate", on: photo?.pixelate != nil) { el in
                        el.pixelate = el.pixelate == nil ? PhotoEffects.defaultPixelate : nil
                    }
                    effectChip("Focus", on: focus != nil) { el in
                        el.focusBlur = el.focusBlur == nil ? FocusBlur() : nil
                    }
                    edgeChip("outline", "Outline", current: edge)
                    edgeChip("glow", "Glow", current: edge)
                }
                .padding(.vertical, 2)
            }
            if blurred {
                effectSlider("Blur", value: -sharpness, in: 0.01...1,
                             readout: "\(Int((-sharpness * 100).rounded()))") { v, el in
                    el.setAdjustment(\.sharpness, to: -max(1, (v * 100).rounded()) / 100)
                }
            }
            if let pixelate = photo?.pixelate {
                effectSlider("Pixel size", value: pixelate, in: 0.01...1,
                             readout: "\(Int((pixelate * 100).rounded()))") { v, el in
                    el.pixelate = max(1, (v * 100).rounded()) / 100
                }
            }
            if let focus { focusControls(focus) }
            if let edge { edgeControls(edge) }
        }
    }

    private func effectChip(_ name: String, on: Bool, _ toggle: @escaping (inout Element) -> Void) -> some View {
        Button {
            store.updateSelected { el in
                guard el.type == .image else { return }
                toggle(&el)
            }
        } label: {
            Text(name)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(on ? Theme.accent.opacity(0.18) : Color(.systemGray6)))
                .overlay(Capsule().stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
        effectSlider("Focus size", value: focus.radius, in: 0...1, readout: Self.percent(focus.radius)) { v, el in
            el.focusBlur?.radius = Self.hundredths(v)
        }
        effectSlider("Background blur", value: focus.amount, in: 0.01...1,
                     readout: "\(Int((focus.amount * 100).rounded()))") { v, el in
            el.focusBlur?.amount = max(0.01, Self.hundredths(v))
        }
        effectSlider("Focus across", value: focus.x, in: 0...1, readout: Self.percent(focus.x)) { v, el in
            el.focusBlur?.x = Self.hundredths(v)
        }
        effectSlider("Focus down", value: focus.y, in: 0...1, readout: Self.percent(focus.y)) { v, el in
            el.focusBlur?.y = Self.hundredths(v)
        }
        Toggle("Keep the subject sharp", isOn: Binding(
            get: { focus.subject },
            set: { on in store.updateSelected { $0.focusBlur?.subject = on } }))
            .font(.subheadline)
    }

    @ViewBuilder
    private func edgeControls(_ edge: PhotoEdge) -> some View {
        let name = PhotoEffects.isGlow(edge) ? "Glow" : "Outline"
        effectSlider("\(name) size", value: edge.width, in: 1...100,
                     readout: "\(Int(edge.width.rounded()))") { v, el in
            el.edge?.width = v.rounded()
        }
        HStack {
            Text("\(name) colour").font(.subheadline)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(hex: edge.color) },
                set: { color in
                    let hex = UIColor(color).hexString
                    store.updateSelectedTransient { $0.edge?.color = hex }
                }), supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("\(name) colour")
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

    private func dial(_ label: String, _ key: WritableKeyPath<Adjustments, Double>,
                      in range: ClosedRange<Double>) -> some View {
        let current = store.singleSelection?.adjustments ?? .neutral
        let readout = String(format: "%+.0f", current[keyPath: key] * 100)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(readout)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // The slider itself carries the name and the number shown, so
            // VoiceOver says "Brightness, +20" rather than a bare percentage.
            .accessibilityHidden(true)
            Slider(value: Binding(
                get: { current[keyPath: key] },
                set: { value in
                    store.updateSelectedTransient { $0.setAdjustment(key, to: value) }
                }
            ), in: range, onEditingChanged: { editing in
                if !editing { store.commit() }
            })
            .accessibilityLabel(label)
            .accessibilityValue(readout)
        }
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
                        Slider(value: cropBinding(el.straighten ?? 0) { v, e in
                            e.straighten = abs(v) < 0.05 ? nil : v
                        }, in: -45...45)
                        .accessibilityLabel("Straighten")
                        .accessibilityValue("\(String(format: "%.1f", el.straighten ?? 0))°")
                    } header: {
                        Text("Straighten")
                    } footer: {
                        Text("\(String(format: "%.1f", el.straighten ?? 0))° — the picture turns inside its frame and grows to keep covering it.")
                    }
                    Section("Frame") {
                        Picker("Fill", selection: Binding(
                            get: { el.cropFit == true ? 1 : 0 },
                            set: { choice in store.updateSelected { $0.cropFit = choice == 1 ? true : nil } })) {
                            Text("Fill").tag(0)
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

    /// The frame's proportions, as the platforms name them. Reshaping keeps
    /// the frame's centre and its width; the picture inside re-covers it.
    static let aspects: [(name: String, ratio: Double)] = [
        ("1:1", 1), ("4:5", 4.0 / 5), ("3:2", 3.0 / 2), ("4:3", 4.0 / 3), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16),
    ]

    private func aspectRow(_ el: Element) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.aspects, id: \.name) { aspect in
                    let active = abs(el.w / max(el.h, 1) - aspect.ratio) < 0.01
                    Button(aspect.name) {
                        store.updateSelected { e in
                            let centre = CGPoint(x: e.x + e.w / 2, y: e.y + e.h / 2)
                            e.h = (e.w / aspect.ratio).rounded()
                            e.x = centre.x - e.w / 2
                            e.y = centre.y - e.h / 2
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(active ? Theme.accent : .secondary)
                    .controlSize(.small)
                }
            }
        }
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
    /// How far one tap of an arrow moves the selection: 1 each time the
    /// sheet opens, as on the Android twin, and never saved.
    @State private var nudgeStep = 1.0
    @State private var nudges = 0
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
                        orderButton("To front", "square.3.layers.3d.top.filled") { store.reorderSelected(.front) }
                        orderButton("Forward", "square.2.layers.3d.top.filled") { store.reorderSelected(.forward) }
                        orderButton("Backward", "square.2.layers.3d.bottom.filled") { store.reorderSelected(.backward) }
                        orderButton("To back", "square.3.layers.3d.bottom.filled") { store.reorderSelected(.back) }
                    }
                }
                // One thing, or one group as a single box, lines up with the
                // page; several with each other — and the heading says which,
                // in the Android twin's words.
                Section(store.alignsToPage ? "Line up with the page" : "Line up with each other") {
                    HStack {
                        orderButton("Left", "align.horizontal.left") { store.alignSelected(.left) }
                        orderButton("Center", "align.horizontal.center") { store.alignSelected(.centerX) }
                        orderButton("Right", "align.horizontal.right") { store.alignSelected(.right) }
                    }
                    HStack {
                        orderButton("Top", "align.vertical.top") { store.alignSelected(.top) }
                        orderButton("Middle", "align.vertical.center") { store.alignSelected(.centerY) }
                        orderButton("Bottom", "align.vertical.bottom") { store.alignSelected(.bottom) }
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
                            orderButton("Horizontally", "arrow.left.and.right") {
                                store.distributeSelected(.horizontal)
                            }
                            orderButton("Vertically", "arrow.up.and.down") {
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
                            orderButton("Row", "rectangle.split.3x1") { store.tidySelected(.row) }
                            orderButton("Column", "rectangle.split.1x2") { store.tidySelected(.column) }
                            orderButton("Grid", "rectangle.split.3x3") { store.tidySelected(.grid) }
                        }
                        .disabled(store.movableSelectionCount < 2)
                    }
                }
                nudgeSection
                Section("Flip") {
                    HStack {
                        orderButton("Horizontal", "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                            store.flipSelected(horizontal: true)
                        }
                        orderButton("Vertical", "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                            store.flipSelected(horizontal: false)
                        }
                    }
                }
                if let el = store.singleSelection {
                    // A lock, whole or of its position, keeps every number
                    // here as it is.
                    Section("Exact") {
                        numberRow("X", value: el.x) { v in store.updateSelectedPlacement { $0.x = v } }
                        numberRow("Y", value: el.y) { v in store.updateSelectedPlacement { $0.y = v } }
                        numberRow("Width", value: el.w) { v in setWidth(v, of: el) }
                        // Text has no height to type: it follows its words.
                        if el.type != .text {
                            proportionsToggle
                            numberRow("Height", value: el.h) { v in setHeight(v, of: el) }
                        }
                        numberRow("Rotation", value: el.rotation) { v in store.updateSelectedPlacement { $0.rotation = v } }
                    }
                    .disabled(el.holdsPlace)
                } else if let box = store.selectionBox {
                    // The selection as one thing: its box moves and scales,
                    // and a rotation turns the whole about the centre.
                    Section("Exact (selection)") {
                        numberRow("X", value: box.minX) { v in
                            store.setSelectionBox(CGRect(x: v, y: box.minY, width: box.width, height: box.height))
                        }
                        numberRow("Y", value: box.minY) { v in
                            store.setSelectionBox(CGRect(x: box.minX, y: v, width: box.width, height: box.height))
                        }
                        // Always scaled evenly, as on the Android twin: a
                        // box of several things has no chain to switch off.
                        numberRow("Width", value: box.width) { v in
                            let w = max(RatioLock.minSide, v)
                            store.setSelectionBox(CGRect(x: box.minX, y: box.minY, width: w, height: box.height * w / max(box.width, 1)))
                        }
                        numberRow("Height", value: box.height) { v in
                            let h = max(RatioLock.minSide, v)
                            store.setSelectionBox(CGRect(x: box.minX, y: box.minY, width: box.width * h / max(box.height, 1), height: h))
                        }
                        numberRow("Rotate by", value: 0) { v in store.rotateSelection(by: v) }
                    }
                    .disabled(store.movableSelectionCount == 0)
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

    /// Arrows that move the selection 1, 10 or 100 page units a tap, with
    /// where it is and how big read out live: the precise move a finger
    /// cannot make, and the only one for someone without a keyboard. Each
    /// tap is its own Undo; locked elements stay put.
    private var nudgeSection: some View {
        Section {
            Picker("Step", selection: $nudgeStep) {
                Text("1").tag(1.0)
                Text("10").tag(10.0)
                Text("100").tag(100.0)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Move by \(Int(nudgeStep)) at a time")
            HStack {
                nudgeButton("arrow.left", "left", dx: -1, dy: 0)
                nudgeButton("arrow.right", "right", dx: 1, dy: 0)
                nudgeButton("arrow.up", "up", dx: 0, dy: -1)
                nudgeButton("arrow.down", "down", dx: 0, dy: 1)
            }
            .disabled(store.movableSelectionCount == 0)
            .feel(.impact(weight: .light), trigger: nudges)
        } header: {
            HStack {
                Text("Nudge")
                Spacer()
                if let readout = nudgeReadout {
                    Text(readout).monospacedDigit()
                }
            }
        }
    }

    /// "x, y  ·  w × h" of the selection's box, whole units, as the Android
    /// twin reads it out.
    private var nudgeReadout: String? {
        guard let box = store.selectionBox else { return nil }
        return "\(Int(box.minX)), \(Int(box.minY))  ·  \(Int(box.width)) × \(Int(box.height))"
    }

    private func nudgeButton(_ system: String, _ direction: String, dx: Double, dy: Double) -> some View {
        Button {
            store.nudgeSelected(dx: dx * nudgeStep, dy: dy * nudgeStep)
            nudges += 1
            // Where it went, said once, rather than every button renamed.
            if let readout = nudgeReadout {
                AccessibilityNotification.Announcement(readout).post()
            }
        } label: {
            Image(systemName: system)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Nudge \(direction) \(Int(nudgeStep))")
    }

    private func orderButton(_ label: String, _ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: system)
                Text(label).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
    }

    private func numberRow(_ label: String, value: Double, commit: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: Binding(get: { value }, set: { commit($0) }), format: .number.precision(.fractionLength(0...1)))
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
/// Overlapping lists only what overlaps the selection.
struct LayersSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter: LayerRows.Filter = .all
    /// The groups opened to list their members; each starts folded.
    @State private var expanded: Set<String> = []
    /// The element Rename… is naming, and the name being typed.
    @State private var renaming: Element?
    @State private var typedName = ""
    /// The rows' elements a swipe would delete, while it asks first.
    @State private var askingDelete: [String]?

    private var rows: [LayerRows.Row] {
        switch filter {
        case .all:
            return LayerRows.rows(store.page.elements, expanded: expanded)
        case .overlapping:
            return LayerRows.flat(LayerRows.overlapping(store.page.elements, selection: store.selection))
        }
    }

    var body: some View {
        NavigationStack {
            let rows = self.rows
            List {
                if rows.isEmpty { emptyState }
                ForEach(rows) { row in
                    rowView(row)
                        .moveDisabled(filter != .all || !row.movable)
                        .deleteDisabled(!row.elements.contains { !$0.locked })
                }
                .onMove(perform: moveAction(rows))
                .onDelete { offsets in delete(offsets.map { rows[$0] }) }
            }
            .environment(\.editMode, .constant(.active))
            .safeAreaInset(edge: .top) { filterPicker }
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                   presenting: renaming) { el in
                TextField(madeName(el), text: $typedName)
                Button("Rename") { store.renameLayer(el.id, to: typedName) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Up to \(LayerNames.maxLength) characters. Leave it empty for the name Canvia gives it.")
            }
            .alert((askingDelete?.count ?? 0) > 1 ? "Delete these?" : "Delete this?",
                   isPresented: Binding(get: { askingDelete != nil }, set: { if !$0 { askingDelete = nil } }),
                   presenting: askingDelete) { ids in
                Button("Delete", role: .destructive) { remove(Set(ids)) }
                Button("Cancel", role: .cancel) {}
            } message: { ids in
                Text(ids.count > 1 ? "Some of them have their position locked." : "Its position is locked.")
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private var filterPicker: some View {
        Picker("Show", selection: $filter) {
            ForEach(LayerRows.Filter.allCases) { choice in
                Text(choice.rawValue).tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
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
            store.moveLayers(rows, from: source, to: destination)
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

    @ViewBuilder
    private func rowView(_ row: LayerRows.Row) -> some View {
        switch row {
        case .element(let el, let member):
            elementRow(el, member: member)
        case .group(let id, let members):
            groupRow(id, members: members)
        }
    }

    /// An element's row: faded, with its eye struck through, while hidden.
    /// A member of an opened group is indented under it, and a tap takes it
    /// alone, as it does on a row of Overlapping, which lists elements one
    /// by one — as on the Android twin; any other row's tap takes its group,
    /// as on the canvas.
    private func elementRow(_ el: Element, member: Bool) -> some View {
        let name = layerName(el)
        let selected = store.selection.contains(el.id)
        let alone = member || filter == .overlapping
        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                layerThumb(el)
                Text(name).lineLimit(1)
            }
            .opacity(el.isHidden ? 0.45 : 1)
            .padding(.leading, member ? 24 : 0)
            .accessibilityElement(children: .combine)
            .accessibilityValue([el.isHidden ? "Hidden" : nil, lockValue(ElementLock.mode(of: el))]
                .compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { pick(el, alone: alone) }
            .accessibilityAction(named: "Rename…") { startRename(el) }
            Spacer(minLength: 4)
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            eyeButton([el.id], hidden: el.isHidden, name: name)
            lockButton([el.id], mode: ElementLock.mode(of: el), name: name)
        }
        .contentShape(Rectangle())
        .onTapGesture { pick(el, alone: alone) }
        .contextMenu {
            Button { startRename(el) } label: { Label("Rename…", systemImage: "pencil") }
        }
    }

    /// A group's row, "Group (3)": folded until its disclosure opens it, a
    /// tap takes the whole group, and the eye and padlock work every member.
    private func groupRow(_ id: String, members: [Element]) -> some View {
        let open = expanded.contains(id)
        let name = LayerRows.groupName(members.count)
        let ids = Set(members.map(\.id))
        let allHidden = members.allSatisfy(\.isHidden)
        let selected = ids.isSubset(of: store.selection)
        return HStack(spacing: 12) {
            Button {
                if open { expanded.remove(id) } else { expanded.insert(id) }
            } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 20, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(open ? "Close \(name)" : "Open \(name)")
            HStack(spacing: 12) {
                Image(systemName: "square.on.square")
                    .frame(width: 28, height: 28)
                Text(name).lineLimit(1)
            }
            .opacity(allHidden ? 0.45 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { pickGroup(members) }
            Spacer(minLength: 4)
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            eyeButton(ids, hidden: allHidden, name: name)
            lockButton(ids, mode: Self.sharedLock(members), name: name)
        }
        .contentShape(Rectangle())
        .onTapGesture { pickGroup(members) }
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
        .accessibilityLabel(hidden ? "Show \(name)" : "Hide \(name)")
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
        .accessibilityValue(lockValue(mode) ?? "Unlocked")
    }

    /// How a row's lock is read out: nil unlocked.
    private func lockValue(_ mode: ElementLock.Mode) -> String? {
        switch mode {
        case .unlocked: return nil
        case .position: return "Position locked"
        case .full: return "Locked"
        }
    }

    /// A group row's lock: the members' one lock when they share it, else
    /// none, so the menu offers to lock them all.
    private static func sharedLock(_ members: [Element]) -> ElementLock.Mode {
        let modes = Set(members.map { ElementLock.mode(of: $0) })
        return modes.count == 1 ? modes.first ?? .unlocked : .unlocked
    }

    private func pick(_ el: Element, alone: Bool) {
        if alone { store.selectLayer(el.id) } else { store.select(el.id) }
    }

    private func pickGroup(_ members: [Element]) {
        if let top = members.first { store.select(top.id) }
    }

    private func startRename(_ el: Element) {
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
            Text(el.glyph ?? "⭐").font(.system(size: 20)).frame(width: 28, height: 28)
        case .text:
            Text("T").font(.system(size: 18, weight: .bold))
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
                Text("×")
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
            Text(typedWrong ? CustomSizes.outOfRangeText : "Each side \(CustomSizes.rangeText).")
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
                         ? "A new design for each size ticked, reflowed to fit, in the same folder. This design stays as it is."
                         : "Changes this design. Undo brings it back.")
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
            .navigationTitle(copying ? "Copy & resize" : "Resize design")
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
                 ? "Reflow keeps each element's place on the new page — a footer stays at the foot, a corner logo in its corner — and sizes follow the smaller ratio."
                 : "Scale shrinks or grows everything uniformly to fit, centred, leaving margins when the shape changes.")
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
                     ? "Pages can have sizes of their own — a story after a square post. Exports, the video and the PDF keep each page's shape."
                     : "Every page takes the new size; pages that had their own size join it.")
            }
        }
        Section("Presets") {
            ForEach(SizePreset.all) { preset in
                Button {
                    resize(preset.w, preset.h, units: UnitChoice(unit: preset.unit, dpi: preset.dpi))
                    dismiss()
                } label: {
                    HStack {
                        Label(preset.name, systemImage: preset.icon)
                        Spacer()
                        Text(preset.dimensions)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        ResizeCustomSection(customW: $customW, customH: $customH, unit: $unit) { w, h in
            resize(w, h, units: .typed(unit))
            dismiss()
        }
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

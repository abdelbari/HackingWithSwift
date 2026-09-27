// Editor sheets: background, fonts, effects, spacing, filters, crop,
// position, layers, resize. The colour picker has its own file — it grew
// past what belongs in a shared one, and past the size the Linux static
// checker could read in a single string.

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

// MARK: - fonts

struct FontSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The face every text selected shares; none is ticked when they differ.
        let current = store.sharedText { $0.fontFamily ?? "sans" }
        NavigationStack {
            List {
                ForEach(FontLibrary.stacks) { stack in
                    Button {
                        store.updateSelected { $0.fontFamily = stack.key }
                        dismiss()
                    } label: {
                        HStack {
                            Text(stack.name)
                                .font(FontLibrary.font(family: stack.key, size: 20, weight: 500, italic: false))
                            Spacer()
                            if current == stack.key {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel("\(stack.name) font")
                    .accessibilityAddTraits(current == stack.key ? .isSelected : [])
                }
            }
            .navigationTitle("Fonts")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

// MARK: - text effects

struct EffectsSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TextEffect.allCases) { effect in
                        let active = TextEffect.from(store.singleSelection?.effect) == effect
                        Button {
                            store.updateSelected { $0.effect = TextEffectSpec(type: effect.rawValue) }
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
                }
                .padding()
            }
            .navigationTitle("Text effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func effectPreview(_ effect: TextEffect) -> some View {
        var el = Element.text("Ag", fontSize: 30, w: 64)
        el.color = "#6d28d9"
        el.align = "center"
        el.effect = TextEffectSpec(type: effect.rawValue)
        el.h = 44
        return TextElementView(element: el)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    presetGrid
                    duotoneRow
                    adjustmentDials
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
    }

    private var presetGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ImageFilterPreset.allCases) { preset in
                let active = ImageFilterPreset.from(store.singleSelection?.filter) == preset
                Button {
                    store.updateSelected { $0.filter = preset.rawValue }
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

    /// Every look taken off in one step — filter, dials, duotone,
    /// straighten and show-whole — leaving where the photo sits alone.
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
                Button("Reset") {
                    store.updateSelected { $0.adjustments = nil }
                }
                .font(.callout)
                .disabled(store.singleSelection?.adjustments?.isNeutral ?? true)
            }
            dial("Brightness", \.brightness, in: -1...1)
            dial("Contrast", \.contrast, in: -1...1)
            dial("Saturation", \.saturation, in: -1...1)
            dial("Warmth", \.warmth, in: -1...1)
            dial("Sharpness", \.sharpness, in: -1...1)
            dial("Vignette", \.vignette, in: 0...1)
            curveRow
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
                    store.updateSelectedTransient { el in
                        var adjustments = el.adjustments ?? .neutral
                        adjustments[keyPath: key] = value
                        // Back to nil when every dial is centred, so an
                        // untouched image keeps the filter cache key it had.
                        el.adjustments = adjustments.isNeutral ? nil : adjustments
                    }
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
            if let src = store.singleSelection?.src,
               let full = PhotoLibrary.resolve(src) {
                // Filter a small copy: ten full-size variants of a 1200x900
                // artwork would be ~43 MB for a row of 76pt thumbnails.
                let base = PhotoLibrary.preview(full, key: src)
                Image(uiImage: ImageFilterEngine.apply(
                    preset,
                    adjustments: store.singleSelection?.adjustments ?? .neutral,
                    duotone: store.singleSelection?.duotone,
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
                        aspectRow(el)
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
                    .disabled(store.unlockedSelectionCount == 0)
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
                        .disabled(store.unlockedSelectionCount < 2)
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
                    Section("Exact") {
                        numberRow("X", value: el.x) { v in store.updateSelected { $0.x = v } }
                        numberRow("Y", value: el.y) { v in store.updateSelected { $0.y = v } }
                        numberRow("Width", value: el.w) { v in store.updateSelected { $0.w = max(8, v) } }
                        if el.type != .text {
                            numberRow("Height", value: el.h) { v in store.updateSelected { $0.h = max(8, v) } }
                        }
                        numberRow("Rotation", value: el.rotation) { v in store.updateSelected { $0.rotation = v } }
                    }
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
                        numberRow("Width", value: box.width) { v in
                            let w = max(8, v)
                            store.setSelectionBox(CGRect(x: box.minX, y: box.minY, width: w, height: box.height * w / max(box.width, 1)))
                        }
                        numberRow("Height", value: box.height) { v in
                            let h = max(8, v)
                            store.setSelectionBox(CGRect(x: box.minX, y: box.minY, width: box.width * h / max(box.height, 1), height: h))
                        }
                        numberRow("Rotate by", value: 0) { v in store.rotateSelection(by: v) }
                    }
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
            .disabled(store.unlockedSelectionCount == 0)
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

struct LayersSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.page.elements.isEmpty {
                    ContentUnavailableView("Nothing on this page yet",
                                           systemImage: "square.3.layers.3d",
                                           description: Text("Everything you add will be listed here, top-most first, and can be dragged into a new order."))
                        .listRowBackground(Color.clear)
                }
                // Top-most first; List reordering maps back to array indices.
                ForEach(Array(store.page.elements.reversed())) { el in
                    HStack(spacing: 12) {
                        layerThumb(el)
                        Text(layerName(el)).lineLimit(1)
                        Spacer()
                        if el.locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                        if store.selection.contains(el.id) {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.select(el.id) }
                }
                .onMove { source, destination in
                    let count = store.page.elements.count
                    var reversed = Array(store.page.elements.reversed())
                    reversed.move(fromOffsets: source, toOffset: destination)
                    store.applyToPage { $0.elements = reversed.reversed() }
                    _ = count
                }
                .onDelete { offsets in
                    let reversed = Array(store.page.elements.reversed())
                    let removable = Set(offsets.map { reversed[$0] }
                        .filter { !$0.locked }
                        .map(\.id))
                    guard !removable.isEmpty else { return }
                    store.applyToPage { page in
                        page.elements.removeAll { removable.contains($0.id) }
                    }
                    store.selection.subtract(removable)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// The name VoiceOver and the snap guides use too: "Heading: SALE",
    /// "Red oval", "QR code" — as the Android twin's Layers panel.
    private func layerName(_ el: Element) -> String {
        ElementNames.name(of: el)
    }

    @ViewBuilder
    private func layerThumb(_ el: Element) -> some View {
        switch el.type {
        case .shape:
            LibraryShape(definition: ContentLibrary.shape(el.shapeId), cornerRadius: 0)
                .fill(Color(hex: el.fill?.primaryColor ?? "#888888"))
                .frame(width: 28, height: 28)
        case .image:
            if let ui = PhotoLibrary.resolve(el.src) {
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
/// for.
private struct ResizeCustomSection: View {
    @Binding var customW: String
    @Binding var customH: String
    let onResize: (Double, Double) -> Void

    var body: some View {
        let size = CustomSizes.size(width: customW, height: customH)
        let typedWrong = !customW.isEmpty && CustomSizes.side(customW) == nil
            || !customH.isEmpty && CustomSizes.side(customH) == nil
        return Section {
            HStack {
                TextField("Width", text: $customW).keyboardType(.numberPad)
                Text("×")
                TextField("Height", text: $customH).keyboardType(.numberPad)
                Text("px").foregroundStyle(.secondary)
            }
            Button(CustomSizes.resizeTitle(width: customW, height: customH)) {
                guard let size else { return }
                onResize(size.width, size.height)
            }
            .fontWeight(.semibold)
            .disabled(size == nil)
        } header: {
            Text("Custom")
        } footer: {
            Text(typedWrong ? CustomSizes.outOfRangeText : "Each side \(CustomSizes.rangeText) pixels.")
                .foregroundStyle(typedWrong ? Color(.systemRed) : Color.secondary)
        }
        // Digits only, five at most, however they arrive.
        .onChange(of: customW) { _, typed in
            let clean = CustomSizes.digits(typed)
            if clean != typed { customW = clean }
        }
        .onChange(of: customH) { _, typed in
            let clean = CustomSizes.digits(typed)
            if clean != typed { customH = clean }
        }
    }
}

struct ResizeSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var customW = ""
    @State private var customH = ""
    @State private var reflow = true
    @State private var pageOnly = false

    private func resize(_ w: Double, _ h: Double) {
        if pageOnly {
            store.resizePage(width: w, height: h, reflow: reflow)
        } else if reflow {
            store.magicResize(width: w, height: h)
        } else {
            store.resizeDesign(width: w, height: h)
        }
    }

    var body: some View {
        NavigationStack {
            List {
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
                            resize(preset.w, preset.h)
                            dismiss()
                        } label: {
                            HStack {
                                Label(preset.name, systemImage: preset.icon)
                                Spacer()
                                Text("\(Int(preset.w)) × \(Int(preset.h))")
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                ResizeCustomSection(customW: $customW, customH: $customH) { w, h in
                    resize(w, h)
                    dismiss()
                }
            }
            .navigationTitle("Resize design")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                customW = String(Int(store.pageWidth))
                customH = String(Int(store.pageHeight))
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

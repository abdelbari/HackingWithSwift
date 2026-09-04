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

struct BackgroundSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]
    private let photoColumns = [GridItem(.adaptive(minimum: 90), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Solid colors").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ContentLibrary.defaultSwatches, id: \.self) { hex in
                            Button {
                                store.applyToPage { $0.background = .color(hex) }
                            } label: {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Color(hex: hex))
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.12)))
                                    .frame(height: 40)
                            }
                        }
                    }

                    Text("Gradients").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ContentLibrary.gradients) { preset in
                            Button {
                                store.applyToPage { $0.background = .gradient(preset.paint) }
                            } label: {
                                let pts = preset.paint.unitPoints
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(LinearGradient(
                                        stops: preset.stops.map { .init(color: Color(hex: $0.color), location: $0.offset) },
                                        startPoint: pts.start, endPoint: pts.end))
                                    .frame(height: 40)
                            }
                        }
                    }

                    Text("Photos").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: photoColumns, spacing: 10) {
                        ForEach(PhotoLibrary.photos) { photo in
                            Button {
                                store.applyToPage { $0.background = .image("asset:\(photo.id)") }
                            } label: {
                                photoThumb(photo.id)
                            }
                        }
                    }
                }
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
                            if store.singleSelection?.fontFamily == stack.key {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
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

    var body: some View {
        NavigationStack {
            Form {
                if let el = store.singleSelection {
                    Section("Line height") {
                        Slider(value: transientBinding(el.lineHeight ?? 1.25) { v, e in e.lineHeight = v },
                               in: 0.8...2.4, step: 0.05)
                    }
                    Section("Letter spacing") {
                        Slider(value: transientBinding(el.letterSpacing ?? 0) { v, e in e.letterSpacing = v },
                               in: -2...20, step: 0.5)
                    }
                    Section {
                        Slider(value: transientBinding(el.paragraphSpacing ?? 0) { v, e in
                            e.paragraphSpacing = v < 0.01 ? nil : v
                        }, in: 0...2, step: 0.1)
                    } header: {
                        Text("Paragraph spacing")
                    } footer: {
                        Text("Extra space after each line break, in ems.")
                    }
                    Section {
                        Picker("Vertical alignment", selection: Binding(
                            get: { el.vAlign ?? "top" },
                            set: { v in store.updateSelected { $0.vAlign = v == "top" ? nil : v } })) {
                            Text("Top").tag("top")
                            Text("Middle").tag("middle")
                            Text("Bottom").tag("bottom")
                        }
                        .pickerStyle(.segmented)
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
                        Button("Shrink the box to the text") { store.shrinkWrapText() }
                        Toggle("Drop cap", isOn: Binding(
                            get: { el.dropCap == true },
                            set: { on in
                                store.updateSelected {
                                    $0.dropCap = on ? true : nil
                                    $0.h = FontLibrary.layoutHeight(for: $0)
                                }
                            }))
                    } header: {
                        Text("Text box")
                    } footer: {
                        Text("With auto-fit on, drag the box and the type resizes to fill it; the alignment places shorter text within a taller box.")
                    }
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
            }
        }
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
        }
    }

    private func dial(_ label: String, _ key: WritableKeyPath<Adjustments, Double>,
                      in range: ClosedRange<Double>) -> some View {
        let current = store.singleSelection?.adjustments ?? .neutral
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(String(format: "%+.0f", current[keyPath: key] * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
                        Slider(value: cropBinding(el.cropScale ?? 1) { v, e in e.cropScale = v },
                               in: 1...3)
                    }
                    Section("Horizontal focus") {
                        Slider(value: cropBinding(el.cropX ?? 0.5) { v, e in e.cropX = v }, in: 0...1)
                    }
                    Section("Vertical focus") {
                        Slider(value: cropBinding(el.cropY ?? 0.5) { v, e in e.cropY = v }, in: 0...1)
                    }
                    Section {
                        Slider(value: cropBinding(el.straighten ?? 0) { v, e in
                            e.straighten = abs(v) < 0.05 ? nil : v
                        }, in: -45...45)
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
                Section(store.selection.count > 1 ? "Align selection" : "Align to page") {
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

    private func layerName(_ el: Element) -> String {
        switch el.type {
        case .text: return String((el.text ?? "Text").split(separator: "\n").first ?? "Text")
        case .shape: return ContentLibrary.shape(el.shapeId).name
        case .image: return "Image"
        case .sticker: return "Sticker \(el.glyph ?? "")"
        case .line: return "Line"
        }
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

struct ResizeSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var customW = ""
    @State private var customH = ""
    @State private var reflow = true

    private func resize(_ w: Double, _ h: Double) {
        if reflow { store.magicResize(width: w, height: h) } else { resize(w, h) }
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
                Section("Custom") {
                    HStack {
                        TextField("Width", text: $customW).keyboardType(.numberPad)
                        Text("×")
                        TextField("Height", text: $customH).keyboardType(.numberPad)
                        Button("Apply") {
                            let w = min(4000, max(40, Double(customW) ?? store.design.width))
                            let h = min(4000, max(40, Double(customH) ?? store.design.height))
                            store.resizeDesign(width: w, height: h)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Resize design")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                customW = String(Int(store.design.width))
                customH = String(Int(store.design.height))
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}
